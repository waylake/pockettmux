import XCTest
@testable import PocketTmuxKit

final class PairingPayloadTests: XCTestCase {
    func testRoundTrip() {
        let payload = PairingPayload(host: "100.67.189.40", port: 7682, token: "abcDEF123", name: "Doyeon's MacBook Pro")
        let url = payload.url
        XCTAssertEqual(url.scheme, "pockettmux")
        XCTAssertEqual(url.host, "pair")
        XCTAssertEqual(PairingPayload(url: url), payload)
        XCTAssertEqual(PairingPayload(string: url.absoluteString), payload)
    }

    func testDefaultsAndRejects() {
        XCTAssertEqual(PairingPayload(string: "pockettmux://pair?host=10.0.0.2&token=t")?.port, WireProtocol.defaultPort)
        XCTAssertNil(PairingPayload(string: "pockettmux://pair?host=10.0.0.2"))
        XCTAssertNil(PairingPayload(string: "https://example.com/?host=a&token=b"))
        XCTAssertNil(PairingPayload(string: "pockettmux://other?host=a&token=b"))
        XCTAssertNil(PairingPayload(string: "garbage"))
    }
}
