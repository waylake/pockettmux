import Foundation
import Security
import PocketTmuxKit

/// Where the profile blob lives. The app uses the Keychain; tests inject a
/// dictionary so the codec and migration paths run without entitlements.
protocol SecretStore {
    func read(account: String) -> Data?
    func write(_ data: Data, account: String)
    func delete(account: String)
}

/// Generic-password records under one service, one per account.
struct KeychainSecretStore: SecretStore {
    private static let service = "com.waylake.pockettmux"

    func read(account: String) -> Data? {
        var query = Self.query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func write(_ data: Data, account: String) {
        delete(account: account)
        var query = Self.query(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete(account: String) {
        SecItemDelete(Self.query(account) as CFDictionary)
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

/// The persisted document and the pure encode/decode/migrate functions.
enum ProfileCodec {
    struct Document: Codable, Equatable {
        var version = 1
        var profiles: [HostProfile]
        var lastUsedID: UUID?
    }

    static func encode(_ document: Document) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(document)) ?? Data()
    }

    static func decode(_ data: Data) -> Document? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Document.self, from: data)
    }

    /// The pre-1.0 single record (`{"host","port","token","lastSession"}`),
    /// turned into a profile named after the host. Nil when unusable.
    static func legacyProfile(from data: Data) -> HostProfile? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = obj["host"] as? String, !host.isEmpty,
              let token = obj["token"] as? String, !token.isEmpty else { return nil }
        let port = (obj["port"] as? Int).flatMap { UInt16(exactly: $0) } ?? WireProtocol.defaultPort
        return HostProfile(name: host, host: host, port: port, token: token)
    }
}

/// All saved Macs. One JSON blob in the Keychain; every mutation persists.
@MainActor
final class ProfileStore: ObservableObject {
    static let account = "profiles.v1"
    static let legacyAccount = "agent.v1"

    @Published private(set) var profiles: [HostProfile] = []
    @Published private(set) var lastUsedID: UUID?

    private let storage: SecretStore

    init(storage: SecretStore = KeychainSecretStore()) {
        self.storage = storage
        if let data = storage.read(account: Self.account), let doc = ProfileCodec.decode(data) {
            profiles = doc.profiles
            lastUsedID = doc.lastUsedID
        }
        migrateLegacyRecord()
    }

    /// First launch after the update: fold the old single-profile record into
    /// the list (skipped when a profile for that host:port already exists),
    /// then delete it so this runs once.
    private func migrateLegacyRecord() {
        guard let data = storage.read(account: Self.legacyAccount) else { return }
        defer { storage.delete(account: Self.legacyAccount) }
        guard let legacy = ProfileCodec.legacyProfile(from: data),
              !profiles.contains(where: { $0.matches(host: legacy.host, port: legacy.port) }) else { return }
        profiles.append(legacy)
        if lastUsedID == nil { lastUsedID = legacy.id }
        persist()
    }

    func profile(_ id: HostProfile.ID) -> HostProfile? {
        profiles.first { $0.id == id }
    }

    /// The Mac to open on launch: the last one used, else the only one.
    var autoResumeCandidate: HostProfile? {
        if let id = lastUsedID, let p = profile(id) { return p }
        return profiles.count == 1 ? profiles[0] : nil
    }

    func upsert(_ profile: HostProfile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        } else {
            profiles.append(profile)
        }
        persist()
    }

    func remove(_ id: HostProfile.ID) {
        profiles.removeAll { $0.id == id }
        if lastUsedID == id { lastUsedID = nil }
        persist()
    }

    /// A scanned/opened pairing: update the profile for that host:port, or
    /// create one. Returns the profile to connect to.
    @discardableResult
    func pair(_ payload: PairingPayload) -> HostProfile {
        let profile = profiles.first { $0.matches(host: payload.host, port: payload.port) }?.applying(payload)
            ?? HostProfile(pairing: payload)
        upsert(profile)
        return profile
    }

    func markConnected(_ id: HostProfile.ID) {
        guard var p = profile(id) else { return }
        p.lastConnected = Date()
        lastUsedID = id
        upsert(p)
    }

    func setLastSession(_ id: HostProfile.ID, sessionID: String?) {
        guard var p = profile(id), p.lastSessionID != sessionID else { return }
        p.lastSessionID = sessionID
        upsert(p)
    }

    private func persist() {
        storage.write(ProfileCodec.encode(.init(profiles: profiles, lastUsedID: lastUsedID)), account: Self.account)
    }
}
