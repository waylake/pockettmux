import Foundation
import Security

/// Tiny Keychain wrapper for the agent credentials (host/port/token) and the
/// last-used session name. One generic-password record, ~60 lines, no deps.
enum Keychain {
    private static let service = "com.waylake.pockettmux"
    private static let account = "agent.v1"

    static func load() -> CachedProfile? {
        var query = base()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return CachedProfile(
            host: obj["host"] as? String ?? "",
            port: obj["port"] as? Int ?? 7682,
            token: obj["token"] as? String ?? "",
            lastSession: obj["lastSession"] as? String ?? "")
    }

    static func save(_ p: CachedProfile) {
        delete()
        guard let obj = try? JSONSerialization.data(withJSONObject: [
            "host": p.host, "port": p.port, "token": p.token, "lastSession": p.lastSession]) else { return }
        var query = base()
        query[kSecValueData as String] = obj
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(base() as CFDictionary)
    }

    private static func base() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

struct CachedProfile: Equatable {
    var host: String
    var port: Int
    var token: String
    var lastSession: String?
}
