import Foundation

/// A Mac advertising `_pockettmux._tcp` on the local network, with its
/// endpoint resolved to something a profile can be built from.
struct DiscoveredHost: Identifiable, Equatable, Hashable {
    /// Bonjour service name (unique on the network).
    let id: String
    /// The name the agent put in its TXT record, else the service name.
    var name: String
    var host: String
    var port: UInt16

    var address: String { "\(host):\(port)" }
}
