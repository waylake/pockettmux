import Foundation
import PocketTmuxKit

public enum AgentInfo {
    public static let version = "1.0.0"
    /// Capabilities announced in `hello.ack`; the phone can gate UI on them.
    public static let capabilities = ["paste", "windows", "attach.size", "bonjour"]
}

/// Everything the agent needs to run. Owned by the Mac app (Settings) or
/// pockettmuxd (flags); the library never reads preferences itself.
public struct AgentConfiguration: Equatable, Sendable {
    public var port: UInt16
    public var token: String
    /// Name shown on the phone and advertised over Bonjour.
    public var hostName: String
    public var advertiseBonjour: Bool
    /// Hold a power assertion while a phone is attached (ARCHITECTURE F1).
    public var keepAwakeWhileAttached: Bool
    /// `nil` → auto-detect (Homebrew, /usr/local, /usr/bin).
    public var tmuxPath: String?

    public init(port: UInt16 = WireProtocol.defaultPort, token: String, hostName: String = HostInfo.computerName,
                advertiseBonjour: Bool = true, keepAwakeWhileAttached: Bool = true, tmuxPath: String? = nil) {
        self.port = port
        self.token = token
        self.hostName = hostName
        self.advertiseBonjour = advertiseBonjour
        self.keepAwakeWhileAttached = keepAwakeWhileAttached
        self.tmuxPath = tmuxPath
    }
}

/// The pairing token lives in `~/.pockettmux/token` (mode 0600) so the Mac
/// app, `pockettmuxd` and `scripts/pair.sh` all agree on it.
public enum TokenStore {
    public static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".pockettmux", isDirectory: true)
    public static let fileURL = directory.appendingPathComponent("token")
    public static let minimumLength = 16

    public static func load() -> String? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.count >= minimumLength ? token : nil
    }

    public static func loadOrCreate() -> String {
        load() ?? regenerate()
    }

    @discardableResult
    public static func regenerate() -> String {
        let token = generate()
        save(token)
        return token
    }

    public static func save(_ token: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? token.write(to: fileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// 32 base62 characters ≈ 190 bits of entropy.
    public static func generate() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<32).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] })
    }
}

/// Constant-time token comparison.
enum TokenCompare {
    static func equal(_ a: String, _ b: String) -> Bool {
        let ba = [UInt8](a.utf8), bb = [UInt8](b.utf8)
        guard ba.count == bb.count else { return false }
        var acc: UInt8 = 0
        for i in ba.indices { acc |= ba[i] ^ bb[i] }
        return acc == 0
    }
}
