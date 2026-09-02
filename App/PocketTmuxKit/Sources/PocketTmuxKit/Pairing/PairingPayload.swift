import Foundation

/// What the Mac shows as a QR / link and the phone scans or opens:
/// `pockettmux://pair?host=<ip>&port=7682&token=<t>&name=<mac name>`
public struct PairingPayload: Equatable, Sendable {
    public static let scheme = "pockettmux"
    public static let host = "pair"

    public var host: String
    public var port: UInt16
    public var token: String
    public var name: String?

    public init(host: String, port: UInt16, token: String, name: String? = nil) {
        self.host = host
        self.port = port
        self.token = token
        self.name = name
    }

    public var url: URL {
        var comps = URLComponents()
        comps.scheme = Self.scheme
        comps.host = Self.host
        var items = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "token", value: token)
        ]
        if let name, !name.isEmpty { items.append(URLQueryItem(name: "name", value: name)) }
        comps.queryItems = items
        // Every component is a valid URL piece by construction.
        return comps.url ?? URL(string: "\(Self.scheme)://\(Self.host)")!
    }

    public init?(url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.scheme == Self.scheme, comps.host == Self.host,
              let items = comps.queryItems else { return nil }
        func value(_ key: String) -> String? {
            items.first { $0.name == key }?.value?.trimmingCharacters(in: .whitespaces)
        }
        guard let host = value("host"), !host.isEmpty,
              let token = value("token"), !token.isEmpty else { return nil }
        self.host = host
        self.port = value("port").flatMap(UInt16.init) ?? WireProtocol.defaultPort
        self.token = token
        self.name = value("name").flatMap { $0.isEmpty ? nil : $0 }
    }

    public init?(string: String) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.init(url: url)
    }
}
