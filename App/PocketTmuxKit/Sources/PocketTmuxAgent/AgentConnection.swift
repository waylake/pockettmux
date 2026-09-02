import Foundation
import Network
import PocketTmuxKit

/// A connected phone, as the Mac app lists it.
public struct AgentClientInfo: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var identity: ClientIdentity?
    public var remoteAddress: String
    public var connectedAt: Date
    public var attachedSession: SessionInfo?

    public var displayName: String { identity?.name ?? remoteAddress }
}

/// One WebSocket connection (phone ↔ agent). All state is confined to `queue`.
final class AgentConnection: @unchecked Sendable {
    let id = UUID()
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let token: String
    private let host: HostIdentity
    private let tmux: TmuxRunner
    private let log: AgentLog
    private let control: TmuxControl

    private var authenticated = false
    private var identity: ClientIdentity?
    private var attachedSession: SessionInfo?
    private let connectedAt = Date()
    private var authDeadline: DispatchWorkItem?

    private var outputBuffer = [UInt8]()
    private var screenTimer: DispatchSourceTimer?
    private var resizeDebounce: DispatchWorkItem?

    /// Called on `queue` whenever the info the server publishes changed.
    var onChange: ((AgentConnection) -> Void)?
    var onClose: ((AgentConnection) -> Void)?
    /// tmux reported a session-level change (new/renamed/killed session).
    var onSessionsChanged: (() -> Void)?

    /// Bounded output coalescing: above this the buffer is flushed at once
    /// rather than waiting for the timer (F8).
    private static let flushThreshold = 512 * 1024

    init(connection: NWConnection, token: String, host: HostIdentity, tmux: TmuxRunner, log: AgentLog) {
        self.connection = connection
        self.queue = DispatchQueue(label: "com.waylake.pockettmux.conn")
        self.token = token
        self.host = host
        self.tmux = tmux
        self.log = log
        self.control = TmuxControl(queue: queue, tmux: tmux, log: log)
        control.onEvent = { [weak self] event in self?.handle(event) }
    }

    var info: AgentClientInfo {
        // Read on the caller's thread: identity/attachedSession are written
        // once per state change on `queue`; a torn read only affects a label.
        AgentClientInfo(id: id, identity: identity, remoteAddress: remoteDescription,
                        connectedAt: connectedAt, attachedSession: attachedSession)
    }

    private var remoteDescription: String {
        if case .hostPort(let host, _) = connection.endpoint { return "\(host)" }
        return "\(connection.endpoint)"
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.log.info("client \(self.remoteDescription) connected")
            case .failed(let error):
                self.log.warning("client \(self.remoteDescription) failed: \(error)")
                self.close()
            case .cancelled: self.close()
            default: break
            }
        }
        connection.start(queue: queue)
        receiveLoop()
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, !self.authenticated else { return }
            self.reject(.error(code: .auth, message: "hello timeout"))
        }
        authDeadline = deadline
        queue.asyncAfter(deadline: .now() + 10, execute: deadline)
    }

    func close() {
        guard connection.state != .cancelled else { return }
        control.detach()
        screenTimer?.cancel()
        screenTimer = nil
        authDeadline?.cancel()
        connection.cancel()
        onClose?(self)
        onClose = nil
    }

    // MARK: - tmux events (on queue)

    private func handle(_ event: TmuxControl.Event) {
        switch event {
        case .attached(let session, let windows):
            attachedSession = session
            send(.sessionAttached(session: session, windows: windows))
            onChange?(self)
        case .windowsChanged(let windows):
            if let session = attachedSession { send(.windows(sessionID: session.id, windows: windows)) }
        case .reset(let bytes):
            outputBuffer.removeAll(keepingCapacity: true)
            send(.screen(mode: .reset, data: Data(bytes)))
        case .output(let bytes):
            outputBuffer.append(contentsOf: bytes)
            if outputBuffer.count > Self.flushThreshold { flushScreen() }
        case .detached(let reason):
            outputBuffer.removeAll(keepingCapacity: true)
            attachedSession = nil
            send(.sessionDetached(reason: reason))
            onChange?(self)
        case .sessionsChanged:
            onSessionsChanged?()
            send(.sessionList(tmux.sessions()))
        case .error(let message):
            send(.error(code: .tmux, message: message))
        }
    }

    private func startScreenTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in self?.flushScreen() }
        screenTimer = timer
        timer.resume()
    }

    private func flushScreen() {
        guard !outputBuffer.isEmpty else { return }
        let data = Data(outputBuffer)
        outputBuffer.removeAll(keepingCapacity: true)
        send(.screen(mode: .update, data: data))
    }

    // MARK: - receive / dispatch

    private func receiveLoop() {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                switch meta.opcode {
                case .text, .binary:
                    if let data { self.dispatch(data) }
                case .ping:
                    self.sendRaw(data, opcode: .pong)
                case .close:
                    self.close()
                    return
                default:
                    break
                }
            }
            if error == nil {
                self.receiveLoop()
            } else {
                self.close()
            }
        }
    }

    private func dispatch(_ data: Data) {
        let message: ClientMessage
        do {
            message = try WireCodec.decodeClient(data)
        } catch WireError.unknownType(let type) {
            if authenticated {
                send(.error(code: .unsupported, message: "unknown frame '\(type)'"))
            } else {
                reject(.error(code: .auth, message: "expected hello v\(WireProtocol.version)"))
            }
            return
        } catch {
            if authenticated {
                send(.error(code: .badFrame, message: "malformed frame"))
            } else {
                reject(.error(code: .badFrame, message: "malformed frame"))
            }
            return
        }
        if authenticated {
            handle(message)
        } else {
            authenticate(message)
        }
    }

    private func authenticate(_ message: ClientMessage) {
        guard case .hello(let auth, let client) = message else {
            reject(.error(code: .auth, message: "expected hello first"))
            return
        }
        guard TokenCompare.equal(auth, token) else {
            log.warning("auth failed from \(remoteDescription) (\(client.name))")
            reject(.error(code: .auth, message: "invalid token"))
            return
        }
        authenticated = true
        identity = client
        authDeadline?.cancel()
        log.info("\(client.name) (\(client.app)) authenticated")
        send(.helloAck(host: host, capabilities: AgentInfo.capabilities))
        startScreenTimer()
        onChange?(self)
    }

    private func handle(_ message: ClientMessage) {
        switch message {
        case .hello:
            send(.error(code: .badFrame, message: "already authenticated"))
        case .sessionList:
            send(.sessionList(tmux.sessions()))
        case .sessionCreate(let name):
            guard TmuxNames.isValidName(name) else { return send(.error(code: .badFrame, message: "invalid session name")) }
            guard tmux.createSession(name: name.trimmingCharacters(in: .whitespaces)) else {
                return send(.error(code: .tmux, message: "could not create '\(name)' (name taken?)"))
            }
            sessionsChanged()
        case .sessionRename(let id, let name):
            guard TmuxNames.isSessionID(id), TmuxNames.isValidName(name) else {
                return send(.error(code: .badFrame, message: "invalid session id or name"))
            }
            guard tmux.renameSession(id: id, name: name.trimmingCharacters(in: .whitespaces)) else {
                return send(.error(code: .tmux, message: "could not rename session"))
            }
            sessionsChanged()
        case .sessionAttach(let id, let cols, let rows):
            guard TmuxNames.isSessionID(id) else { return send(.error(code: .badFrame, message: "invalid session id")) }
            // A duplicate attach for the session we're already showing is a
            // no-op: re-spawning the control client would make tmux emit %exit
            // for the first one and the phone would see "session ended".
            if attachedSession?.id == id, control.state != .idle { return }
            guard tmux.session(id: id) != nil else { return send(.error(code: .tmux, message: "no such session \(id)")) }
            control.attach(sessionID: id, cols: cols, rows: rows)
        case .sessionDetach:
            control.detach()
        case .sessionKill(let id):
            guard TmuxNames.isSessionID(id) else { return send(.error(code: .badFrame, message: "invalid session id")) }
            if attachedSession?.id == id { control.detach() }
            guard tmux.killSession(id: id) else { return send(.error(code: .tmux, message: "could not kill session \(id)")) }
            sessionsChanged()
        case .windowSelect(let id):
            guard TmuxNames.isWindowID(id) else { return send(.error(code: .badFrame, message: "invalid window id")) }
            guard attachedSession != nil else { return send(.error(code: .notAttached, message: "not attached")) }
            control.selectWindow(id: id)
        case .windowCreate:
            guard attachedSession != nil else { return send(.error(code: .notAttached, message: "not attached")) }
            control.createWindow()
        case .windowKill(let id):
            guard TmuxNames.isWindowID(id) else { return send(.error(code: .badFrame, message: "invalid window id")) }
            guard attachedSession != nil else { return send(.error(code: .notAttached, message: "not attached")) }
            control.killWindow(id: id)
        case .windowRename(let id, let name):
            guard TmuxNames.isWindowID(id), TmuxNames.isValidName(name) else {
                return send(.error(code: .badFrame, message: "invalid window id or name"))
            }
            guard attachedSession != nil else { return send(.error(code: .notAttached, message: "not attached")) }
            control.renameWindow(id: id, name: name.trimmingCharacters(in: .whitespaces))
        case .input(let data):
            control.sendInput([UInt8](data))
        case .paste(let text):
            guard attachedSession != nil else { return send(.error(code: .notAttached, message: "not attached")) }
            control.paste(text)
        case .resize(let cols, let rows):
            guard (2...1000).contains(cols), (1...1000).contains(rows) else { return }
            // The phone reports several sizes while its layout settles; apply
            // the last one after a short quiet period so the shared window
            // doesn't visibly flicker on the Mac.
            resizeDebounce?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.control.resize(cols: cols, rows: rows) }
            resizeDebounce = item
            queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: item)
        case .ping(let sentAt):
            send(.pong(sentAt: sentAt))
        }
    }

    private func sessionsChanged() {
        onSessionsChanged?()
        send(.sessionList(tmux.sessions()))
    }

    // MARK: - outbound

    private func send(_ message: ServerMessage) {
        sendRaw(WireCodec.encode(message), opcode: .text)
    }

    /// Send one last frame, then close once it has actually left — cancelling
    /// right after `send` drops the frame and the phone sees a bare disconnect.
    private func reject(_ message: ServerMessage) {
        guard connection.state != .cancelled else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: WireCodec.encode(message), contentContext: context, isComplete: true,
                        completion: .contentProcessed { [weak self] _ in self?.close() })
    }

    private func sendRaw(_ data: Data?, opcode: NWProtocolWebSocket.Opcode) {
        guard connection.state != .cancelled else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }
}
