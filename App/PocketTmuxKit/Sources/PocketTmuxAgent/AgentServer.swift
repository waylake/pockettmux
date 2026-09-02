import Foundation
import Network
import PocketTmuxKit

/// What the Mac app shows: is the agent up, on which port, who is connected.
public struct AgentSnapshot: Equatable, Sendable {
    public var isRunning = false
    public var port: UInt16
    public var startedAt: Date?
    public var clients: [AgentClientInfo] = []
    public var bonjourName: String?
    public var lastError: String?

    public var attachedClients: Int { clients.filter { $0.attachedSession != nil }.count }
}

public enum AgentError: LocalizedError, Equatable {
    case tmuxNotFound
    case alreadyRunning
    case listen(String)

    public var errorDescription: String? {
        switch self {
        case .tmuxNotFound: return "tmux was not found (brew install tmux, or set its path in Settings)"
        case .alreadyRunning: return "the agent is already running"
        case .listen(let detail): return "could not listen: \(detail)"
        }
    }
}

/// The WebSocket server (Network.framework, no third-party dependencies).
/// Binds every interface so LAN and Tailscale reach it; auth is the token.
public final class AgentServer: @unchecked Sendable {
    public let configuration: AgentConfiguration
    public let log: AgentLog
    public let tmux: TmuxRunner

    /// Delivered on the main queue after every change.
    public var onSnapshot: (@Sendable (AgentSnapshot) -> Void)?
    /// Delivered on the main queue when tmux sessions were created / renamed /
    /// killed through any connection (the Mac app refreshes its list).
    public var onSessionsChanged: (@Sendable () -> Void)?

    private let queue = DispatchQueue(label: "com.waylake.pockettmux.server")
    private var listener: NWListener?
    private var connections: [UUID: AgentConnection] = [:]
    private var state: AgentSnapshot
    private let sleep = SleepInhibitor()

    public init(configuration: AgentConfiguration, log: AgentLog) throws {
        guard let path = TmuxLocator.resolve(override: configuration.tmuxPath) else { throw AgentError.tmuxNotFound }
        self.configuration = configuration
        self.log = log
        self.tmux = TmuxRunner(path: path)
        self.state = AgentSnapshot(port: configuration.port)
    }

    public var snapshot: AgentSnapshot {
        queue.sync { state }
    }

    public func start() throws {
        try queue.sync {
            guard listener == nil else { throw AgentError.alreadyRunning }
            let params = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.maximumMessageSize = 4 * 1024 * 1024
            params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            params.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: configuration.port) else { throw AgentError.listen("bad port") }
            let listener: NWListener
            do { listener = try NWListener(using: params, on: port) } catch { throw AgentError.listen("\(error)") }
            if configuration.advertiseBonjour {
                let txt = NWTXTRecord(["name": configuration.hostName, "v": "\(WireProtocol.version)"])
                listener.service = NWListener.Service(name: configuration.hostName, type: WireProtocol.bonjourType,
                                                      txtRecord: txt)
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self] listenerState in self?.listenerChanged(listenerState) }
            listener.serviceRegistrationUpdateHandler = { [weak self] change in
                guard let self, case .add(let endpoint) = change, case .service(let name, _, _, _) = endpoint else { return }
                self.state.bonjourName = name
                self.publish()
            }
            self.listener = listener
            state.lastError = nil
            listener.start(queue: queue)
        }
    }

    public func stop() {
        queue.sync {
            for connection in connections.values { connection.close() }
            connections.removeAll()
            listener?.cancel()
            listener = nil
            sleep.set(active: false)
            state.isRunning = false
            state.startedAt = nil
            state.clients = []
            state.bonjourName = nil
            log.info("agent stopped")
            publish()
        }
    }

    // MARK: - on queue

    private func listenerChanged(_ listenerState: NWListener.State) {
        switch listenerState {
        case .ready:
            state.isRunning = true
            state.startedAt = Date()
            let endpoint = "ws://0.0.0.0:\(configuration.port)\(WireProtocol.path)"
            log.info("pockettmuxd \(AgentInfo.version) listening on \(endpoint) (\(tmux.version()))")
        case .failed(let error):
            state.isRunning = false
            state.startedAt = nil
            state.lastError = Self.describe(error)
            log.error("listener failed: \(error)")
            listener?.cancel()
            listener = nil
        case .cancelled:
            state.isRunning = false
        default:
            return
        }
        publish()
    }

    private static func describe(_ error: NWError) -> String {
        if case .posix(let code) = error, code == .EADDRINUSE { return "port already in use" }
        return "\(error)"
    }

    private func accept(_ nwConnection: NWConnection) {
        let host = HostIdentity(name: configuration.hostName, agent: AgentInfo.version, tmux: tmux.version())
        let connection = AgentConnection(connection: nwConnection, token: configuration.token, host: host,
                                         tmux: tmux, log: log)
        connections[connection.id] = connection
        connection.onChange = { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.refreshClients() }
        }
        connection.onClose = { [weak self] closed in
            guard let self else { return }
            self.queue.async {
                self.connections.removeValue(forKey: closed.id)
                self.log.info("client \(closed.info.displayName) disconnected")
                self.refreshClients()
            }
        }
        connection.onSessionsChanged = { [weak self] in
            guard let self, let handler = self.onSessionsChanged else { return }
            DispatchQueue.main.async { handler() }
        }
        connection.start()
        refreshClients()
    }

    private func refreshClients() {
        state.clients = connections.values.map(\.info).sorted { $0.connectedAt < $1.connectedAt }
        sleep.set(active: configuration.keepAwakeWhileAttached && state.attachedClients > 0)
        publish()
    }

    private func publish() {
        guard let onSnapshot else { return }
        let snapshot = state
        DispatchQueue.main.async { onSnapshot(snapshot) }
    }
}
