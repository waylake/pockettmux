import XCTest
import PocketTmuxKit
@testable import PocketTmux

final class HostProfileTests: XCTestCase {
    func testApplyingPairingKeepsIdentityAndHistory() {
        let date = Date()
        let profile = HostProfile(name: "Studio", host: "10.0.0.2", port: 7682, token: "old",
                                  lastConnected: date, lastSessionID: "$2")
        let updated = profile.applying(PairingPayload(host: "10.0.0.9", port: 7690, token: "new"))
        XCTAssertEqual(updated.id, profile.id)
        XCTAssertEqual(updated.host, "10.0.0.9")
        XCTAssertEqual(updated.port, 7690)
        XCTAssertEqual(updated.token, "new")
        XCTAssertEqual(updated.name, "Studio", "no name in the payload keeps the user's name")
        XCTAssertEqual(updated.lastConnected, date)
        XCTAssertEqual(updated.lastSessionID, "$2")

        let renamed = profile.applying(PairingPayload(host: "10.0.0.2", port: 7682, token: "x", name: "Mac mini"))
        XCTAssertEqual(renamed.name, "Mac mini")
    }

    func testProfileFromPairingUsesNameOrHost() {
        let url = URL(string: "pockettmux://pair?host=100.67.189.40&port=7699&token=abc&name=TestMac")!
        let named = HostProfile(pairing: PairingPayload(url: url)!)
        XCTAssertEqual(named.name, "TestMac")
        XCTAssertEqual(named.address, "100.67.189.40:7699")
        XCTAssertEqual(named.token, "abc")

        let anonymous = HostProfile(pairing: PairingPayload(host: "mac.local", port: 7682, token: "t"))
        XCTAssertEqual(anonymous.name, "mac.local")
        XCTAssertNil(anonymous.lastConnected)
    }

    func testSocketURLAndMatching() {
        let v4 = HostProfile(name: "a", host: "192.168.0.64", port: 7682, token: "t")
        XCTAssertEqual(v4.socketURL?.absoluteString, "ws://192.168.0.64:7682/ws")
        let v6 = HostProfile(name: "b", host: "fd7a:115c::1", port: 7682, token: "t")
        XCTAssertEqual(v6.socketURL?.absoluteString, "ws://[fd7a:115c::1]:7682/ws")
        XCTAssertTrue(v4.matches(host: "192.168.0.64", port: 7682))
        XCTAssertFalse(v4.matches(host: "192.168.0.64", port: 7683))
        XCTAssertTrue(HostProfile(name: "c", host: "Mac.local", token: "t").matches(host: "mac.local", port: 7682))
    }
}
