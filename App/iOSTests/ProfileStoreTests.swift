import XCTest
import PocketTmuxKit
@testable import PocketTmux

/// In-memory stand-in for the Keychain.
final class MemorySecretStore: SecretStore {
    var records: [String: Data] = [:]

    func read(account: String) -> Data? { records[account] }
    func write(_ data: Data, account: String) { records[account] = data }
    func delete(account: String) { records[account] = nil }
}

final class ProfileCodecTests: XCTestCase {
    func testDocumentRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_788_000_000)
        let profile = HostProfile(name: "Studio", host: "100.67.189.40", port: 7682, token: "t0k",
                                  lastConnected: date, lastSessionID: "$3")
        let doc = ProfileCodec.Document(profiles: [profile], lastUsedID: profile.id)
        let decoded = ProfileCodec.decode(ProfileCodec.encode(doc))
        XCTAssertEqual(decoded, doc)
        XCTAssertEqual(decoded?.profiles.first?.lastConnected, date)
    }

    func testDecodeRejectsGarbage() {
        XCTAssertNil(ProfileCodec.decode(Data("not json".utf8)))
        XCTAssertNil(ProfileCodec.decode(Data("{\"profiles\":\"nope\"}".utf8)))
    }

    func testLegacyRecordBecomesProfileNamedAfterHost() {
        let legacy = Data("{\"host\":\"192.168.0.64\",\"port\":7690,\"token\":\"abc\",\"lastSession\":\"main\"}".utf8)
        let p = ProfileCodec.legacyProfile(from: legacy)
        XCTAssertEqual(p?.name, "192.168.0.64")
        XCTAssertEqual(p?.host, "192.168.0.64")
        XCTAssertEqual(p?.port, 7690)
        XCTAssertEqual(p?.token, "abc")
        XCTAssertNil(p?.lastConnected)
    }

    func testLegacyRecordDefaultsPortAndRejectsIncomplete() {
        let noPort = Data("{\"host\":\"mac.local\",\"token\":\"abc\"}".utf8)
        XCTAssertEqual(ProfileCodec.legacyProfile(from: noPort)?.port, WireProtocol.defaultPort)
        XCTAssertNil(ProfileCodec.legacyProfile(from: Data("{\"host\":\"\",\"token\":\"abc\"}".utf8)))
        XCTAssertNil(ProfileCodec.legacyProfile(from: Data("{\"host\":\"mac\",\"port\":7682}".utf8)))
        let badPort = Data("{\"host\":\"mac\",\"port\":70000,\"token\":\"x\"}".utf8)
        XCTAssertEqual(ProfileCodec.legacyProfile(from: badPort)?.port, WireProtocol.defaultPort)
    }
}

@MainActor
final class ProfileStoreTests: XCTestCase {
    func testMigratesLegacyRecordOnceAndDeletesIt() {
        let storage = MemorySecretStore()
        storage.records[ProfileStore.legacyAccount] =
            Data("{\"host\":\"10.0.0.2\",\"port\":7682,\"token\":\"old\",\"lastSession\":\"\"}".utf8)

        let store = ProfileStore(storage: storage)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.host, "10.0.0.2")
        XCTAssertEqual(store.lastUsedID, store.profiles.first?.id)
        XCTAssertNil(storage.records[ProfileStore.legacyAccount], "legacy record is deleted after migration")
        XCTAssertNotNil(storage.records[ProfileStore.account], "migrated list is persisted")

        // A second launch reads the new blob and does not duplicate anything.
        let again = ProfileStore(storage: storage)
        XCTAssertEqual(again.profiles, store.profiles)
        XCTAssertEqual(again.lastUsedID, store.lastUsedID)
    }

    func testLegacyRecordSkippedWhenHostAlreadySaved() {
        let storage = MemorySecretStore()
        let existing = HostProfile(name: "Studio", host: "10.0.0.2", port: 7682, token: "new")
        storage.records[ProfileStore.account] = ProfileCodec.encode(.init(profiles: [existing], lastUsedID: nil))
        storage.records[ProfileStore.legacyAccount] = Data("{\"host\":\"10.0.0.2\",\"port\":7682,\"token\":\"old\"}".utf8)

        let store = ProfileStore(storage: storage)
        XCTAssertEqual(store.profiles, [existing])
        XCTAssertNil(storage.records[ProfileStore.legacyAccount])
    }

    func testUpsertRemoveAndAutoResume() {
        let storage = MemorySecretStore()
        let store = ProfileStore(storage: storage)
        XCTAssertNil(store.autoResumeCandidate)

        let a = HostProfile(name: "A", host: "a.local", token: "1")
        store.upsert(a)
        XCTAssertEqual(store.autoResumeCandidate, a, "a single profile resumes by itself")

        let b = HostProfile(name: "B", host: "b.local", token: "2")
        store.upsert(b)
        XCTAssertNil(store.autoResumeCandidate, "two profiles, none used yet → ask")

        store.markConnected(b.id)
        XCTAssertEqual(store.lastUsedID, b.id)
        XCTAssertEqual(store.autoResumeCandidate?.id, b.id)
        XCTAssertNotNil(store.profile(b.id)?.lastConnected)

        store.setLastSession(b.id, sessionID: "$7")
        XCTAssertEqual(store.profile(b.id)?.lastSessionID, "$7")

        store.remove(b.id)
        XCTAssertNil(store.lastUsedID)
        XCTAssertEqual(store.profiles, [a])

        let reloaded = ProfileStore(storage: storage)
        XCTAssertEqual(reloaded.profiles, [a])
    }

    func testPairUpdatesMatchingProfileOrCreatesOne() {
        let store = ProfileStore(storage: MemorySecretStore())
        let existing = HostProfile(name: "Old name", host: "192.168.0.64", port: 7682, token: "old",
                                   lastConnected: Date(), lastSessionID: "$1")
        store.upsert(existing)

        let same = store.pair(PairingPayload(host: "192.168.0.64", port: 7682, token: "fresh", name: "Studio"))
        XCTAssertEqual(same.id, existing.id, "same host:port keeps the profile identity")
        XCTAssertEqual(same.token, "fresh")
        XCTAssertEqual(same.name, "Studio")
        XCTAssertEqual(same.lastSessionID, "$1")
        XCTAssertEqual(store.profiles.count, 1)

        let other = store.pair(PairingPayload(host: "192.168.0.64", port: 7699, token: "t"))
        XCTAssertNotEqual(other.id, existing.id)
        XCTAssertEqual(other.name, "192.168.0.64", "no name in the payload → named after the host")
        XCTAssertEqual(store.profiles.count, 2)
    }
}
