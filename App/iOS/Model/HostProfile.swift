import Foundation
import PocketTmuxKit

/// A paired Mac: where to connect and the token that lets us in.
/// Persisted by `ProfileStore` (Keychain, one JSON blob for all profiles).
struct HostProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: UInt16
    var token: String
    var lastConnected: Date?
    var lastSessionID: String?

    init(id: UUID = UUID(), name: String, host: String, port: UInt16 = WireProtocol.defaultPort,
         token: String, lastConnected: Date? = nil, lastSessionID: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.token = token
        self.lastConnected = lastConnected
        self.lastSessionID = lastSessionID
    }

    /// `host:port` as shown under the name in every list.
    var address: String { "\(host):\(port)" }

    /// `ws://host:port/ws` — nil only for a host string that is not URL-safe.
    var socketURL: URL? {
        // Bracket bare IPv6 literals; hostnames and IPv4 pass through.
        let h = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return URL(string: "ws://\(h):\(port)\(WireProtocol.path)")
    }

    func matches(host: String, port: UInt16) -> Bool {
        self.host.caseInsensitiveCompare(host) == .orderedSame && self.port == port
    }

    /// A pairing scanned or opened for this Mac: take its token (and name,
    /// when the QR carries one); keep the id and history.
    func applying(_ pairing: PairingPayload) -> HostProfile {
        var p = self
        p.host = pairing.host
        p.port = pairing.port
        p.token = pairing.token
        if let name = pairing.name, !name.isEmpty { p.name = name }
        return p
    }

    /// A fresh profile from a pairing; named after the Mac, or its host when
    /// the payload has no name.
    init(pairing: PairingPayload) {
        self.init(name: pairing.name?.isEmpty == false ? pairing.name! : pairing.host,
                  host: pairing.host, port: pairing.port, token: pairing.token)
    }
}
