import Foundation
import Darwin

/// Facts about this Mac the agent and the pairing UI need.
public enum HostInfo {
    /// "Doyeon's MacBook Pro" — what the phone shows for this Mac.
    public static var computerName: String {
        if let name = Host.current().localizedName, !name.isEmpty { return name }
        return ProcessInfo.processInfo.hostName
    }

    public struct Address: Identifiable, Equatable, Hashable, Sendable {
        public enum Kind: String, Sendable {
            case lan        // en0/en1… private ranges
            case tailscale  // 100.64.0.0/10 on a utun interface
            case other
        }

        public var interface: String
        public var ip: String
        public var kind: Kind
        public var id: String { "\(interface)/\(ip)" }

        public var label: String {
            switch kind {
            case .lan: return "Wi-Fi / LAN (\(interface))"
            case .tailscale: return "Tailscale (\(interface))"
            case .other: return interface
            }
        }
    }

    /// IPv4 addresses a phone could dial, most useful first: Tailscale
    /// (works off the home network) before LAN, loopback/link-local excluded.
    public static func addresses() -> [Address] {
        var result: [Address] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (Int32(entry.pointee.ifa_flags) & IFF_UP) != 0,
                  (Int32(entry.pointee.ifa_flags) & IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let interface = String(cString: entry.pointee.ifa_name)
            guard !ip.hasPrefix("169.254.") else { continue }
            let kind: Address.Kind
            if isTailscale(ip) {
                kind = .tailscale
            } else if interface.hasPrefix("en") || interface.hasPrefix("bridge") {
                kind = .lan
            } else if interface.hasPrefix("utun") || interface.hasPrefix("awdl") || interface.hasPrefix("llw") {
                continue   // VPN tunnels we can't classify, AirDrop links
            } else {
                kind = .other
            }
            result.append(Address(interface: interface, ip: ip, kind: kind))
        }
        let rank: [Address.Kind: Int] = [.tailscale: 0, .lan: 1, .other: 2]
        return result.sorted { (rank[$0.kind] ?? 9, $0.interface) < (rank[$1.kind] ?? 9, $1.interface) }
    }

    /// Tailscale hands out 100.64.0.0/10 (CGNAT range).
    static func isTailscale(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[0] == 100 else { return false }
        return (64...127).contains(parts[1])
    }
}
