import Foundation
import Network

enum AgentInfo { static let version = "1.0.0" }

/// WebSocket server (Network.framework — no third-party deps).
/// Binds 0.0.0.0 so both LAN and Tailscale reach it; auth is a mandatory token.
final class AgentServer: @unchecked Sendable {
    private let port: UInt16
    private let token: String
    private var listener: NWListener?
    private var connections: [UUID: Connection] = [:]

    init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }

    func start() throws {
        let params = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.maximumMessageSize = 4 * 1024 * 1024
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("pockettmuxd \(AgentInfo.version) — ws://0.0.0.0:\(self.port) (token: \(self.tokenPrefix()))")
            case .failed(let e):
                print("listener failed: \(e)")
                exit(1)
            default:
                break
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    private func tokenPrefix() -> String {
        token.count > 4 ? "\(token.prefix(4))…" : "…"
    }

    private func accept(_ conn: NWConnection) {
        let c = Connection(conn: conn, token: token)
        connections[c.id] = c
        c.onClose = { [weak self, weak c] in
            guard let self, let c else { return }
            self.connections.removeValue(forKey: c.id)
        }
        c.start()
    }
}
