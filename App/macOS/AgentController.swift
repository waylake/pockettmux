import AppKit
import Foundation
import PocketTmuxAgent
import PocketTmuxKit
import ServiceManagement

/// Owns the `AgentServer` and mirrors everything the views show:
/// snapshot (running / clients / error), tmux sessions, log, token,
/// launch-at-login. Configuration changes are stop → new server → start.
@MainActor
final class AgentController: ObservableObject {
    static let shared = AgentController()

    /// Last snapshot from the current server; nil while stopped.
    @Published private(set) var snapshot: AgentSnapshot?
    @Published private(set) var sessions: [SessionInfo] = []
    @Published private(set) var logEntries: [LogEntry] = []
    @Published private(set) var token: String = TokenStore.loadOrCreate()
    @Published private(set) var addresses: [HostInfo.Address] = HostInfo.addresses()
    /// `AgentError` from init/start (tmux missing, bad port); listener
    /// failures arrive asynchronously in `snapshot.lastError`.
    @Published private(set) var startError: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var launchAtLoginError: String?

    let log = AgentLog()

    /// Non-nil from `start()` until `stop()`, whether or not the listener is up yet.
    @Published private(set) var server: AgentServer?
    private var pollTimer: Timer?
    private var pollers = 0

    private init() {
        log.onEntry = { [weak self] entry in
            guard let self else { return }
            MainActor.assumeIsolated { self.append(entry) }
        }
        log.info("PocketTmux \(AgentInfo.version) — token in \(TokenStore.fileURL.path)")
    }

    // MARK: - State

    var isRunning: Bool { snapshot?.isRunning ?? false }
    var hasServer: Bool { server != nil }
    var port: UInt16 { snapshot?.port ?? MacSettings.port }
    var clients: [AgentClientInfo] { snapshot?.clients ?? [] }
    var attachedClients: Int { snapshot?.attachedClients ?? 0 }

    /// Whatever should be shown in shu in the panel header, if anything.
    var errorText: String? { startError ?? snapshot?.lastError }

    var tmuxPath: String? { TmuxLocator.resolve(override: MacSettings.tmuxPath) }
    var autoDetectedTmuxPath: String? { TmuxLocator.resolve(override: nil) }
    var tmuxVersion: String { tmuxPath.map { TmuxRunner(path: $0).version() } ?? "tmux not found" }

    /// Sessions a phone is attached to, by session id.
    var attachedSessionIDs: Set<String> {
        Set(clients.compactMap { $0.attachedSession?.id })
    }

    // MARK: - Lifecycle

    func start() {
        stop()
        startError = nil
        let configuration = MacSettings.configuration(token: token)
        do {
            let server = try AgentServer(configuration: configuration, log: log)
            server.onSnapshot = { [weak self, weak server] snapshot in
                guard let self, let server else { return }
                MainActor.assumeIsolated {
                    guard self.server === server else { return }
                    self.snapshot = snapshot
                }
            }
            server.onSessionsChanged = { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated { self.refreshSessions() }
            }
            self.server = server
            try server.start()
            snapshot = server.snapshot
        } catch {
            startError = error.localizedDescription
            snapshot = nil
            server = nil
        }
        refreshAddresses()
        refreshSessions()
    }

    func stop() {
        guard let server else { return }
        server.onSnapshot = nil
        server.onSessionsChanged = nil
        server.stop()
        self.server = nil
        snapshot = nil
        startError = nil
    }

    /// Settings changed: pick them up now if the agent is running.
    func restartIfRunning() {
        if server != nil { start() }
    }

    func regenerateToken() {
        token = TokenStore.regenerate()
        log.warning("token regenerated — paired iPhones must pair again")
        restartIfRunning()
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Sessions

    /// The menu-bar panel polls while it is open; `onSessionsChanged` pushes
    /// the rest of the time.
    func beginPolling() {
        pollers += 1
        refreshAddresses()
        refreshSessions()
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.refreshSessions() }
        }
    }

    func endPolling() {
        pollers = max(0, pollers - 1)
        guard pollers == 0 else { return }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshAddresses() {
        addresses = HostInfo.addresses()
    }

    func refreshSessions() {
        guard let path = tmuxPath else {
            sessions = []
            return
        }
        let runner = TmuxRunner(path: path)
        Task.detached(priority: .userInitiated) {
            let list = runner.sessions().sorted { $0.activity > $1.activity }
            await MainActor.run { self.sessions = list }
        }
    }

    func killSession(id: String) {
        guard let path = tmuxPath else { return }
        let runner = TmuxRunner(path: path)
        Task.detached(priority: .userInitiated) {
            if !runner.killSession(id: id) {
                await MainActor.run { self.log.error("kill-session \(id) failed") }
            }
            await MainActor.run { self.refreshSessions() }
        }
    }

    /// `tmux attach -t '$3'` in a new Terminal.app tab. Session ids are
    /// `$N`, but everything is quoted anyway (shell, then AppleScript).
    func openInTerminal(session: SessionInfo) {
        guard let path = tmuxPath else { return }
        let shell = "\(Self.shellQuoted(path)) attach -t \(Self.shellQuoted(session.id))"
        let source = """
        tell application "Terminal"
            activate
            do script "\(Self.appleScriptQuoted(shell))"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let detail = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            log.error("open in Terminal failed: \(detail)")
        } else {
            log.info("opened \(session.name) in Terminal")
        }
    }

    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptQuoted(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Log

    func clearLog() {
        log.clear()
        logEntries = []
    }

    var logText: String { logEntries.map(\.line).joined(separator: "\n") }

    private func append(_ entry: LogEntry) {
        logEntries.append(entry)
        if logEntries.count > log.capacity { logEntries.removeFirst(logEntries.count - log.capacity) }
    }
}

extension AgentController {
    /// Copy to the general pasteboard.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
