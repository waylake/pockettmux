import Foundation
import Network

/// One authenticated WebSocket connection (phone ↔ agent).
/// All state is confined to `q` (a per-connection serial queue).
final class Connection: @unchecked Sendable {
    let id: UUID = UUID()
    private let conn: NWConnection
    private let q: DispatchQueue
    private let token: String
    private var authenticated = false
    private var attachedSession: String?
    private let tmux: TmuxControl

    private var outputBuffer = [UInt8]()
    private var screenTimer: DispatchSourceTimer?
    private var pendingReset = false
    private var authDeadline: DispatchWorkItem?
    private var resizeWorkItem: DispatchWorkItem?

    init(conn: NWConnection, token: String) {
        self.conn = conn
        self.q = DispatchQueue(label: "io.pockettmux.conn.\(UUID().uuidString.prefix(6))")
        self.token = token
        self.tmux = TmuxControl(queue: q)
        wireTmux()
    }

    func start() {
        conn.stateUpdateHandler = { st in
            if case .failed(let e) = st { print("conn \(self.id) failed: \(e)") }
            if case .ready = st { print("conn \(self.id) ws-ready") }
        }
        conn.start(queue: q)
        receiveLoop()
        authDeadline = DispatchWorkItem { [weak self] in
            guard let self, !self.authenticated else { return }
            self.send(Sender.error(code: "auth", message: "hello timeout"))
            self.close()
        }
        q.asyncAfter(deadline: .now() + 10, execute: authDeadline!)
    }

    // MARK: - tmux wiring (all on q)

    private func wireTmux() {
        tmux.onActiveOutput = { [weak self] bytes in
            guard let self else { return }
            // Coalesce pane output into ~16 ms screen frames; never buffer unbounded.
            self.outputBuffer.append(contentsOf: bytes)
            if self.outputBuffer.count > 1_000_000 {
                self.flushScreen()
            }
        }
        tmux.onEvent = { [weak self] ev in self?.handle(ev) }
    }

    private func handle(_ ev: TmuxControlEvent) {
        switch ev {
        case .output: break // handled by onActiveOutput
        case .sessionChanged(let id, let name):
            send(Sender.json("session.attached", ["id": id, "name": name]))
        case .sessionsChanged:
            send(Sender.sessionList(TmuxQueries.list()))
        case .exit(let reason):
            let session = attachedSession ?? ""
            attachedSession = nil
            send(Sender.exit(code: 0, message: reason ?? "session closed", session: session))
        case .error(let text):
            send(Sender.error(code: "tmux", message: text))
        default:
            break // window/pane/layout noise — not actionable on the phone yet
        }
    }

    private func startScreenTimer() {
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(4))
        t.setEventHandler { [weak self] in self?.flushScreen() }
        screenTimer = t
        t.resume()
    }

    private var lastFrameLog = 0.0
    private func flushScreen() {
        guard !outputBuffer.isEmpty, let session = attachedSession else { return }
        let bytes = outputBuffer
        outputBuffer.removeAll(keepingCapacity: true)
        let mode = pendingReset ? "reset" : "update"
        pendingReset = false
        // diag: log every frame, throttled to ~10/s
        let now = Date().timeIntervalSince1970
        if now - lastFrameLog > 0.1 {
            lastFrameLog = now
            print("diag: \(mode) frame \(bytes.count)B for \(session)")
        }
        send(Sender.screen(mode: mode, data: Data(bytes), session: session))
    }

    // MARK: - receive / dispatch

    private func receiveLoop() {
        conn.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                switch meta.opcode {
                case .text, .binary:
                    if let data { self.dispatch(data) }
                case .ping:
                    self.reply(.pong, payload: data)
                case .pong:
                    break
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
        if !authenticated {
            guard case .hello(let auth, let version) = (try? CMessageDecoder.decode(data)) ?? .unknown(type: "") else {
                send(Sender.error(code: "auth", message: "expected hello first"))
                close()
                return
            }
            guard version == 1, constantTimeEqual(auth, token) else {
                send(Sender.error(code: "auth", message: "invalid token"))
                close()
                return
            }
            authenticated = true
            authDeadline?.cancel()
            send(Sender.helloAck(agentVersion: AgentInfo.version, tmuxVersion: TmuxQueries.version()))
            startScreenTimer()
            tmux.ensureFlusher()
            return
        }

        let msg: CMessage
        do { msg = try CMessageDecoder.decode(data) } catch {
            send(Sender.error(code: "badframe", message: "malformed frame"))
            return
        }
        switch msg {
        case .hello:
            send(Sender.error(code: "badframe", message: "already authed"))
        case .listSessions:
            send(Sender.sessionList(TmuxQueries.list()))
        case .createSession(let name):
            switch TmuxQueries.create(name: name) {
            case true:
                pushSessions()
            case false:
                send(Sender.error(code: "tmux", message: "could not create session '\(name)'"))
            case nil:
                send(Sender.error(code: "badframe", message: "invalid session name"))
            }
        case .destroySession(let id):
            if tmux.state == .attached && id == attachedSession {
                tmux.detach()
                attachedSession = nil
            }
            if TmuxQueries.destroy(id: id) {
                pushSessions()
            } else {
                send(Sender.error(code: "tmux", message: "could not destroy session \(id)"))
            }
        case .attachSession(let id):
            // Ignore a duplicate attach for the session we're already showing —
            // re-sending makes the control client get killed+respawned (the
            // Mac window briefly resizes and tmux emits %exit → "session ended").
            if attachedSession == id && tmux.state == .attached { break }
            print("diag: attach \(id) (prev \(attachedSession ?? "none"))")
            attachedSession = id
            pendingReset = true
            tmux.attach(sessionID: id)
        case .detach:
            tmux.detach()
            attachedSession = nil
            send(Sender.json("detach"))
        case .input(let data):
            tmux.sendInput([UInt8](data))
        case .resize(let cols, let rows):
            // The phone reports several sizes while its terminal settles
            // (45x42 → 45x27 → 45x25); applying each one resizes the shared
            // window repeatedly (visible flicker on the Mac). Apply the last
            // one after a short quiet period instead.
            resizeWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.tmux.resize(cols: cols, rows: rows) }
            resizeWorkItem = item
            q.asyncAfter(deadline: .now() + 0.3, execute: item)
        case .ping:
            send(Sender.pong())
        case .unknown(let type):
            send(Sender.error(code: "badframe", message: "unknown type '\(type)'"))
        }
    }

    private func pushSessions() {
        send(Sender.sessionList(TmuxQueries.list()))
    }

    // MARK: - outbound

    private func reply(_ opcode: NWProtocolWebSocket.Opcode, payload: Data?) {
        let meta = NWProtocolWebSocket.Metadata(opcode: opcode)
        let ctx = NWConnection.ContentContext(identifier: "ws", metadata: [meta])
        conn.send(content: payload, contentContext: ctx, isComplete: true, completion: .contentProcessed { _ in })
    }

    private func send(_ data: Data) {
        reply(.text, payload: data)
    }

    private func close() {
        tmux.detach()
        screenTimer?.cancel()
        screenTimer = nil
        conn.cancel()
        onClose?()
    }

    var onClose: (() -> Void)?

    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ba = [UInt8](a.utf8), bb = [UInt8](b.utf8)
        guard ba.count == bb.count else { return false }
        var acc: UInt8 = 0
        for i in ba.indices { acc |= ba[i] ^ bb[i] }
        return acc == 0
    }
}
