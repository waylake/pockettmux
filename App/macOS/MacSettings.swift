import Foundation
import PocketTmuxAgent
import PocketTmuxKit

/// Preferences in `UserDefaults` (`com.waylake.pockettmux.mac`). Views bind
/// with `@AppStorage(MacSettings.Key…)`; `AgentController` reads the same
/// keys to build an `AgentConfiguration`.
enum MacSettings {
    enum Key {
        static let port = "agent.port"
        static let autoStart = "agent.autoStart"
        static let keepAwake = "agent.keepAwake"
        static let bonjour = "agent.bonjour"
        static let hostName = "agent.hostName"
        static let tmuxPath = "agent.tmuxPath"
    }

    static let portRange: ClosedRange<Int> = 1024...65535
    static var defaults: UserDefaults { .standard }

    /// Register once at launch so `@AppStorage` and `UserDefaults` agree.
    static func registerDefaults() {
        defaults.register(defaults: [
            Key.port: Int(WireProtocol.defaultPort),
            Key.autoStart: true,
            Key.keepAwake: true,
            Key.bonjour: true,
            Key.hostName: "",
            Key.tmuxPath: ""
        ])
    }

    static var port: UInt16 {
        let stored = defaults.integer(forKey: Key.port)
        return portRange.contains(stored) ? UInt16(stored) : WireProtocol.defaultPort
    }

    static var autoStart: Bool { defaults.bool(forKey: Key.autoStart) }
    static var keepAwake: Bool { defaults.bool(forKey: Key.keepAwake) }
    static var bonjour: Bool { defaults.bool(forKey: Key.bonjour) }

    /// Empty string means "use the computer name".
    static var hostName: String {
        let stored = defaults.string(forKey: Key.hostName)?.trimmingCharacters(in: .whitespaces) ?? ""
        return stored.isEmpty ? HostInfo.computerName : stored
    }

    /// Empty string means auto-detect.
    static var tmuxPath: String? {
        let stored = defaults.string(forKey: Key.tmuxPath)?.trimmingCharacters(in: .whitespaces) ?? ""
        return stored.isEmpty ? nil : stored
    }

    static func configuration(token: String) -> AgentConfiguration {
        AgentConfiguration(port: port, token: token, hostName: hostName, advertiseBonjour: bonjour,
                           keepAwakeWhileAttached: keepAwake, tmuxPath: tmuxPath)
    }
}
