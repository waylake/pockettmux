import Foundation
import Combine

enum ConnState: Equatable {
    case idle, connecting, connected, reconnecting
}

/// WebSocket client (URLSessionWebSocketTask) for the PocketTmux agent.
/// MainActor-confined view model; one instance lives at the app root.
@MainActor
final class AgentClient: ObservableObject {
    @Published private(set) var status: ConnState = .idle
    @Published private(set) var sessions: [SessionInfo] = []
    @Published private(set) var attachedSession: SessionInfo?
    @Published private(set) var lastError: String?
    @Published private(set) var agentBanner: String?      // transient (exit / errors)
    @Published var pendingScreen: Data?                   // consumed by TerminalHost
    @Published var terminalTitle: String = ""

    private var task: URLSessionWebSocketTask?
    private var recvTask: Task<Void, Never>?
    private var host = ""
    private var port = 7682
    private var token = ""
    private var credit: CachedProfile?

    private var wantConnected = false
    private var wantAttach = false
    /// Session the user asked to attach to — survives drops so reconnect
    /// re-attaches. Deduplicates `attach()` (a row tap + `TerminalScreen`
    /// `.appearOnce` both call it; a second `session.attach` makes the agent
    /// kill+respawn the control client → `%exit` → "session ended").
    private var pendingAttach: SessionInfo?
    private var reconnectDelay = 1.0
    private var bannerTask: Task<Void, Never>?

    // MARK: - Connection lifecycle

    func connect(_ profile: CachedProfile) async {
        credit = profile
        host = profile.host
        port = profile.port
        token = profile.token
        wantConnected = true
        reconnectDelay = 1.0
        Keychain.save(profile)
        await open()
    }

    func disconnect() {
        wantConnected = false
        wantAttach = false
        pendingAttach = nil
        recvTask?.cancel()
        recvTask = nil
        task?.cancel()
        task = nil
        status = .idle
        attachedSession = nil
        sessions = []
    }

    private func open() async {
        status = .connecting
        pendingScreen = nil
        guard let url = URL(string: "ws://\(host):\(port)/ws") else {
            fail(with: L.cantReach); return
        }
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        send(type: "hello", payload: ["v": 1, "auth": token])
        recvTask?.cancel()
        recvTask = Task { [weak self] in
            while let task = self?.task {
                do {
                    let msg = try await task.receive()
                    switch msg {
                    case .string(let s):
                        await self?.handle(text: s)
                    case .data(let d):
                        if let s = String(data: d, encoding: .utf8) { await self?.handle(text: s) }
                    @unknown default: break
                    }
                } catch {
                    await self?.dropped()
                    break
                }
            }
        }
    }

    private func handle(text: String) {
        guard let ev = WireCoder.decode(text) else { return }
        switch ev {
        case .helloAck:
            status = .connected
            lastError = nil
            // Restore a prior attach across reconnects/Mac sleep.
            if wantAttach, let session = pendingAttach ?? attachedSession {
                attach(session)
            }
            _ = listNow()
        case .sessionList(let list):
            sessions = list
        case .screen(let mode, let data):
            if mode == "reset" { terminalTitle = attachedSession?.name ?? terminalTitle }
            print("CLIENT: screen \(mode) \(data.count)B")
            pendingScreen = data
        case .sessionAttached(let id, let name):
            if attachedSession?.id != id {
                attachedSession = sessions.first { $0.id == id }
                    ?? SessionInfo(id: id, name: name, windows: 0, attached: 1, created: 0, activity: Date().timeIntervalSince1970)
            }
            terminalTitle = name
        case .exit(let message):
            showBanner(L.sessionEnd + (message.isEmpty ? "" : " — \(message)"))
            attachedSession = nil
            pendingAttach = nil
            wantAttach = false
        case .error(let code, let message):
            if code == "auth" {
                fail(with: L.invalidToken)
            } else {
                showBanner(message)
            }
        }
    }

    private func dropped() {
        guard wantConnected else { status = .idle; return }
        status = .reconnecting
        task = nil
        attachedSession = nil
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.open()
        }
    }

    private func fail(with message: String) {
        lastError = message
        status = wantConnected ? .reconnecting : .idle
        task?.cancel()
        task = nil
        // Let the user retry from the connect screen.
        if wantConnected && credit != nil {
            reconnectDelay = min(reconnectDelay * 2, 30)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(5 * 1_000_000_000))
                if self?.status == .reconnecting { await self?.open() }
            }
        }
    }

    private func showBanner(_ message: String) {
        agentBanner = message
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.agentBanner = nil
        }
    }

    // MARK: - Commands

    /// Re-query sessions (returns current list, e.g. after create/destroy).
    func listNow() -> [SessionInfo] {
        send(type: "session.list", payload: [:])
        return sessions
    }

    func createSession(name: String) {
        send(type: "session.create", payload: ["name": name])
    }

    func attach(_ session: SessionInfo) {
        print("CLIENT: attach \(session.id)")
        pendingAttach = session
        wantAttach = true
        // Dedupe: a row tap and TerminalScreen.appearOnce both call attach();
        // re-sending makes the agent kill+respawn the control client (the
        // shared window briefly resizes and the session "ends" with %exit).
        guard attachedSession?.id != session.id else { return }
        guard status == .connected else { return }   // helloAck re-sends it
        attachedSession = session
        send(type: "session.attach", payload: ["id": session.id])
    }

    func detach() {
        pendingAttach = nil
        wantAttach = false
        // Clear attachedSession or a re-attach of the same session is swallowed
        // by attach()'s dedupe guard (attachedSession?.id == session.id).
        attachedSession = nil
        send(type: "session.detach", payload: [:])
    }

    func destroy(_ session: SessionInfo) {
        send(type: "session.destroy", payload: ["id": session.id])
        if attachedSession?.id == session.id {
            attachedSession = nil
            pendingAttach = nil
            wantAttach = false
        }
    }

    func sendInput(_ bytes: [UInt8]) {
        guard wantAttach else { return }
        send(type: "input", payload: ["data": Data(bytes).base64EncodedString()])
    }

    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        print("CLIENT: resize \(cols)x\(rows)")
        send(type: "resize", payload: ["cols": cols, "rows": rows])
    }

    private func send(type: String, payload: [String: Any]) {
        guard let task, task.state == .running else { return }
        let text = WireCoder.envelope(type: type, payload: payload)
        task.send(.string(text)) { _ in }
    }
}
