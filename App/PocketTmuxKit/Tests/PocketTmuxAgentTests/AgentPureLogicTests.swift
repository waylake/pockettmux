import XCTest
import PocketTmuxKit
@testable import PocketTmuxAgent

final class ScreenPrimerTests: XCTestCase {
    private func state(alt: Bool, mouse: Bool = false, sgr: Bool = false, appCursor: Bool = false,
                       history: Int = 0, height: Int = 3, cursorX: Int = 0, cursorY: Int = 0) -> TmuxFormats.PaneState {
        TmuxFormats.PaneState(paneID: "%1", windowID: "@1", alternateScreen: alt, mouseReporting: mouse, mouseSGR: sgr,
                              applicationCursorKeys: appCursor, historySize: history, width: 80, height: height,
                              cursorX: cursorX, cursorY: cursorY)
    }

    func testAlternateScreenWithMouseAndCursorKeys() {
        let frame = ScreenPrimer.frame(state: state(alt: true, mouse: true, sgr: true, appCursor: true), capture: nil)
        let text = String(decoding: frame, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("\u{1b}[?1049l\u{1b}[H\u{1b}[2J\u{1b}[3J\u{1b}[?1049h"))
        XCTAssertTrue(text.contains("\u{1b}[?1000h\u{1b}[?1002h\u{1b}[?1006h"))
        XCTAssertTrue(text.contains("\u{1b}[?1h"))
    }

    func testNormalScreenReplaysHistoryAndRestoresCursor() {
        // 2 history lines + 3 screen rows; the prompt is on row 1 (0-based), column 2.
        let capture = "old 1\nold 2\n$ ls\n$ \n\n"
        let frame = ScreenPrimer.frame(state: state(alt: false, history: 2, height: 3, cursorX: 2, cursorY: 1),
                                       capture: capture)
        let text = String(decoding: frame, as: UTF8.self)
        XCTAssertFalse(text.contains("?1049h"))
        XCTAssertTrue(text.contains("old 1\r\nold 2\r\n$ ls\r\n$ \r\n"))           // CRLF joins, blank bottom row kept
        XCTAssertTrue(text.hasSuffix("\u{1b}[1A\u{1b}[3G"))                        // up 1 from the bottom row, column 3
    }

    func testCursorOnBottomRowNeedsNoUpMove() {
        let frame = ScreenPrimer.frame(state: state(alt: false, height: 2, cursorX: 0, cursorY: 1), capture: "a\nb\n")
        XCTAssertTrue(String(decoding: frame, as: UTF8.self).hasSuffix("a\r\nb\u{1b}[1G"))
    }

    func testCaptureStart() {
        XCTAssertEqual(ScreenPrimer.captureStart(for: state(alt: true, history: 500)), 0)
        XCTAssertEqual(ScreenPrimer.captureStart(for: state(alt: false, history: 500)), -500)
        XCTAssertEqual(ScreenPrimer.captureStart(for: state(alt: false, history: 99_999)), -ScreenPrimer.maxHistoryLines)
    }
}

final class SendKeysEncoderTests: XCTestCase {
    func testOneHexArgumentPerByte() {
        XCTAssertEqual(SendKeysEncoder.lines(for: [0x1b, 0x5b, 0x41], paneID: "%7"), ["send-keys -H -t %7 1b 5b 41"])
        XCTAssertEqual(SendKeysEncoder.lines(for: [0x61], paneID: nil), ["send-keys -H 61"])
        XCTAssertEqual(SendKeysEncoder.lines(for: [], paneID: "%7"), [])
    }

    func testChunksLongInput() {
        let lines = SendKeysEncoder.lines(for: [UInt8](repeating: 0x41, count: 300), paneID: "%1")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].split(separator: " ").count - 4, 128)
        XCTAssertEqual(lines[2].split(separator: " ").count - 4, 44)
    }
}

final class TokenTests: XCTestCase {
    func testGeneratedTokensAreLongAndUnique() {
        let a = TokenStore.generate(), b = TokenStore.generate()
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.allSatisfy(\.isLetter) || a.contains { $0.isNumber })
    }

    func testConstantTimeCompare() {
        XCTAssertTrue(TokenCompare.equal("abc", "abc"))
        XCTAssertFalse(TokenCompare.equal("abc", "abd"))
        XCTAssertFalse(TokenCompare.equal("abc", "abcd"))
    }
}

final class HostInfoTests: XCTestCase {
    func testTailscaleRange() {
        XCTAssertTrue(HostInfo.isTailscale("100.64.0.1"))
        XCTAssertTrue(HostInfo.isTailscale("100.127.255.254"))
        XCTAssertFalse(HostInfo.isTailscale("100.128.0.1"))
        XCTAssertFalse(HostInfo.isTailscale("192.168.1.2"))
    }

    func testAddressesExcludeLoopback() {
        XCTAssertFalse(HostInfo.addresses().contains { $0.ip.hasPrefix("127.") })
    }
}
