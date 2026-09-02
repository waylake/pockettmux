import Foundation
import Combine
import UIKit
import PocketTmuxKit

enum ConnState: Equatable {
    case idle, connecting, connected, reconnecting
}

/// The session the control client is showing, plus its window list.
struct AttachedState: Equatable {
    var session: SessionInfo
    var windows: [WindowInfo]

    var activeWindow: WindowInfo? { windows.first { $0.active } ?? windows.first }
}

/// One `sessionDetached` frame, surfaced so the Terminal screen can react.
/// `retrying` is true when the client is already re-attaching on its own.
struct DetachEvent: Equatable {
    let id = UUID()
    let reason: DetachReason
    let retrying: Bool
}

/// WebSocket client (URLSessionWebSocketTask) for the PocketTmux agent —
/// protocol v2 via `WireCodec`. MainActor-confined; one instance at the root.
@MainActor
final class AgentClient: ObservableObject {
    @Published private(set) var status: ConnState = .idle
    /// The profile `connect(profile:)` was last called with; nil after `disconnect()`.
    @Published private(set) var profileID: HostProfile.ID?
    @Published private(set) var host: HostIdentity?
    @Published private(set) var sessions: [SessionInfo] = []
    @Published private(set) var attached: AttachedState?
    @Published private(set) var rtt: TimeInterval?
    @Published private(set) var lastError: String?
    @Published private(set) var banner: String?
    @Published private(set) var detachEvent: DetachEvent?
    @Published var pendingScreen: Data?          // consumed by TerminalHost
    @Published var terminalTitle = ""
    /// Last size SwiftTerm reported; sent with `sessionAttach` so the agent
    /// sizes the window before the first paint.
    var lastTerminalSize: (cols: Int, rows: Int)?

    static let pingInterval: TimeInterval = 10
    static let pongTimeout: TimeInterval = 15

    private var profile: HostProfile?
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var policy = ReconnectPolicy()
    private var wantConnected = false
    /// Session the user asked for — survives drops so `helloAck` re-attaches.
    /// Also deduplicates `attach()` (a row tap and the Terminal screen's
    /// appear both call it): a second `session.attach` would be a no-op on
    /// the agent, but we don't even send it.
    private var wantedSessionID: String?
    /// Attach sent, `sessionAttached` not yet seen.
    private var requestedSessionID: String?
    private var retriedAttach = false
    private var lastPongSentAt: Double = 0

    // MARK: - Connection lifecycle

    /// Connects to `profile`. A no-op when already connected to the same
    /// profile with the same address/token; otherwise drops the current
    /// socket first. Callers that need to react to "already connected"
    /// check `status` after the call.
    func connect(profile: HostProfile) {
        if status == .connected, let current = self.profile, current.id == profile.id,
           current.matches(host: profile.host, port: profile.port), current.token == profile.token {
            self.profile = profile
            return
        }
        closeSocket()
        self.profile = profile
        profileID = profile.id
        wantConnected = true
        wantedSessionID = nil
        policy.reset()
        lastError = nil
        host = nil
        sessions = []
        status = .connecting
        open()
    }

    func disconnect() {
        wantConnected = false
        wantedSessionID = nil
        closeSocket()
        profile = nil
        profileID = nil
        host = nil
        sessions = []
        rtt = nil
        status = .idle
    }

    /// Scene became active: iOS may have killed the socket in the background,
    /// so skip the backoff and try right away.
    func resumeIfNeeded() {
        guard wantConnected, status == .reconnecting else { return }
        reconnectTask?.cancel()
        policy.reset()
        open()
    }

    private func closeSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        requestedSessionID = nil
        attached = nil
        rtt = nil
    }

    private func open() {
        guard wantConnected, let profile else { return }
        pendingScreen = nil
        guard let url = profile.socketURL else {
            lastError = L.cantReach
            wantConnected = false
            status = .idle
            return
        }
        print("CLIENT: open \(url.absoluteString)")
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        send(.hello(auth: profile.token, client: Self.identity))
        receiveTask = Task { [weak self] in await self?.receiveLoop(t) }
    }

    private func receiveLoop(_ t: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await t.receive()
                guard task === t else { return }
                switch message {
                case .string(let s): handle(Data(s.utf8))
                case .data(let d): handle(d)
                @unknown default: break
                }
            } catch {
                guard task === t else { return }
                dropped(error)
                return
            }
        }
    }

    private func handle(_ data: Data) {
        let message: ServerMessage
        do {
            message = try WireCodec.decodeServer(data)
        } catch WireError.unknownType {
            return   // forward-compat: newer agent, unknown frame
        } catch {
            print("CLIENT: malformed frame (\(data.count)B)")
            return
        }
        switch message {
        case .helloAck(let identity, _):
            print("CLIENT: hello.ack \(identity.name) \(identity.tmux) wanted=\(wantedSessionID ?? "-")")
            host = identity
            status = .connected
            lastError = nil
            policy.reset()
            retriedAttach = false
            startPing()
            if let id = wantedSessionID { sendAttach(id) }   // restore across drops; agent repaints
            send(.sessionList)
        case .sessionList(let list):
            sessions = list.sorted { $0.activity > $1.activity }
        case .sessionAttached(let session, let windows):
            requestedSessionID = nil
            retriedAttach = false
            attached = AttachedState(session: session, windows: windows)
        case .sessionDetached(let reason):
            handleDetached(reason)
        case .windows(let sessionID, let windows):
            if attached?.session.id == sessionID { attached?.windows = windows }
        case .screen(let mode, let data):
            print("CLIENT: screen \(mode.rawValue) \(data.count)B")
            pendingScreen = data
        case .pong(let sentAt):
            lastPongSentAt = max(lastPongSentAt, sentAt)
            rtt = max(0, Date().timeIntervalSince1970 - sentAt)
        case .error(let code, let message):
            if code == .auth { authFailed() } else { showBanner(message) }
        }
    }

    private func handleDetached(_ reason: DetachReason) {
        print("CLIENT: detached \(reason.rawValue)")
        requestedSessionID = nil
        var retrying = false
        switch reason {
        case .replaced:
            return   // a newer attach from us is in flight; its sessionAttached follows
        case .requested:
            break
        case .sessionKilled:
            wantedSessionID = nil
            showBanner(L.sessionEndedOnMac)
        case .controlExited:
            if let id = wantedSessionID, !retriedAttach, status == .connected {
                retriedAttach = true
                retrying = true
                sendAttach(id)
            } else {
                wantedSessionID = nil
            }
            showBanner(L.sessionLost)
        }
        attached = nil
        detachEvent = DetachEvent(reason: reason, retrying: retrying)
    }

    private func authFailed() {
        lastError = L.invalidToken
        wantConnected = false
        wantedSessionID = nil
        closeSocket()
        status = .idle
    }

    private func dropped(_ error: Error?) {
        task = nil
        pingTask?.cancel()
        pingTask = nil
        requestedSessionID = nil
        attached = nil
        rtt = nil
        guard wantConnected else { status = .idle; return }
        if let error { lastError = error.localizedDescription }
        status = .reconnecting
        let delay = policy.nextDelay()
        print("CLIENT: dropped, retry in \(String(format: "%.1f", delay))s")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    // MARK: - Liveness

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pingInterval))
                guard !Task.isCancelled, let self else { return }
                self.ping()
            }
        }
    }

    private func ping() {
        guard let socket = task else { return }
        let sentAt = Date().timeIntervalSince1970
        send(.ping(sentAt: sentAt))
        Task { [weak self, weak socket] in
            try? await Task.sleep(for: .seconds(Self.pongTimeout))
            // Only the socket that sent this ping can time out on it; a
            // reconnect in the meantime starts its own ping cycle.
            guard let self, let socket, self.task === socket, self.lastPongSentAt < sentAt else { return }
            print("CLIENT: pong timeout")
            socket.cancel(with: .abnormalClosure, reason: nil)
            self.dropped(nil)
        }
    }

    private func showBanner(_ message: String) {
        banner = message
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    // MARK: - Sessions

    func listSessions() {
        send(.sessionList)
    }

    func createSession(name: String) {
        send(.sessionCreate(name: name))
    }

    func renameSession(id: String, name: String) {
        send(.sessionRename(id: id, name: name))
    }

    func killSession(id: String) {
        if wantedSessionID == id {
            wantedSessionID = nil
            requestedSessionID = nil
            attached = nil
        }
        send(.sessionKill(id: id))
    }

    func attach(sessionID: String) {
        wantedSessionID = sessionID
        retriedAttach = false
        guard attached?.session.id != sessionID, requestedSessionID != sessionID else { return }
        guard status == .connected else { return }   // helloAck sends it
        sendAttach(sessionID)
    }

    private func sendAttach(_ id: String) {
        requestedSessionID = id
        print("CLIENT: attach \(id) size=\(lastTerminalSize.map { "\($0.cols)x\($0.rows)" } ?? "unknown")")
        send(.sessionAttach(id: id, cols: lastTerminalSize?.cols, rows: lastTerminalSize?.rows))
    }

    func detach() {
        wantedSessionID = nil
        requestedSessionID = nil
        attached = nil
        pendingScreen = nil
        send(.sessionDetach)
    }

    // MARK: - Windows

    func selectWindow(id: String) {
        send(.windowSelect(id: id))
    }

    func createWindow() {
        send(.windowCreate)
    }

    func killWindow(id: String) {
        send(.windowKill(id: id))
    }

    func renameWindow(id: String, name: String) {
        send(.windowRename(id: id, name: name))
    }

    // MARK: - Terminal I/O

    func sendInput(_ bytes: [UInt8]) {
        guard wantedSessionID != nil, !bytes.isEmpty else { return }
        send(.input(Data(bytes)))
    }

    func paste(_ text: String) {
        guard wantedSessionID != nil, !text.isEmpty else { return }
        send(.paste(text))
    }

    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        lastTerminalSize = (cols, rows)
        guard attached != nil || requestedSessionID != nil else { return }
        print("CLIENT: resize \(cols)x\(rows)")
        send(.resize(cols: cols, rows: rows))
    }

    private func send(_ message: ClientMessage) {
        guard let task, task.state == .running else { return }
        task.send(.string(String(decoding: WireCodec.encode(message), as: UTF8.self))) { _ in }
    }

    // MARK: - Identity

    private static var identity: ClientIdentity {
        var sys = utsname()
        uname(&sys)
        let machine = withUnsafeBytes(of: sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return ClientIdentity(name: UIDevice.current.name, model: machine, app: "PocketTmux iOS \(version)")
    }
}
