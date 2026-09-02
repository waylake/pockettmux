import Foundation
import Network
import PocketTmuxKit

/// Live list of Macs advertising `_pockettmux._tcp`. Bonjour only hands out
/// service names, so each result is resolved by opening a throwaway TCP
/// connection and reading the remote endpoint once it is ready.
@MainActor
final class BonjourBrowser: ObservableObject {
    @Published private(set) var hosts: [DiscoveredHost] = []

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]
    private var found: [String: DiscoveredHost] = [:]

    func start() {
        guard browser == nil else { return }
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: WireProtocol.bonjourType, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.update(results) }
        }
        b.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, case .failed = state else { return }
                // Typically the local-network permission being denied, or the
                // network going away; drop and let the next `start()` retry.
                self.stop()
            }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.cancel() }
        resolvers.removeAll()
        found.removeAll()
        hosts = []
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var seen = Set<String>()
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            seen.insert(name)
            var advertised = name
            if case .bonjour(let txt) = result.metadata, let n = txt.dictionary["name"], !n.isEmpty {
                advertised = n
            }
            if found[name] != nil {
                found[name]?.name = advertised
            } else if resolvers[name] == nil {
                resolve(name: name, advertised: advertised, endpoint: result.endpoint)
            }
        }
        for name in found.keys where !seen.contains(name) { found[name] = nil }
        for name in resolvers.keys where !seen.contains(name) {
            resolvers[name]?.cancel()
            resolvers[name] = nil
        }
        publish()
    }

    private func resolve(name: String, advertised: String, endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        // The agent listens dual-stack; an IPv4 literal makes a cleaner profile
        // than a scoped link-local IPv6 address.
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: endpoint, using: params)
        resolvers[name] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            MainActor.assumeIsolated {
                guard let self, let connection else { return }
                switch state {
                case .ready:
                    if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                        self.found[name] = DiscoveredHost(id: name, name: advertised,
                                                          host: Self.string(host), port: port.rawValue)
                        self.publish()
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    if self.resolvers[name] === connection { self.resolvers[name] = nil }
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func publish() {
        hosts = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func string(_ host: NWEndpoint.Host) -> String {
        let raw: String
        switch host {
        case .ipv4(let address): raw = "\(address)"
        case .ipv6(let address): raw = "\(address)"
        case .name(let name, _): raw = name
        @unknown default: raw = "\(host)"
        }
        // Drop an interface scope (`fe80::1%en0`); it is not part of the address.
        return raw.split(separator: "%", maxSplits: 1).first.map(String.init) ?? raw
    }
}
