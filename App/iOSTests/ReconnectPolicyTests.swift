import XCTest
@testable import PocketTmux

final class ReconnectPolicyTests: XCTestCase {
    func testDoublesFromOneSecondAndCapsAtThirty() {
        let p = ReconnectPolicy()
        XCTAssertEqual(p.baseDelay(attempt: 0), 1)
        XCTAssertEqual(p.baseDelay(attempt: 1), 2)
        XCTAssertEqual(p.baseDelay(attempt: 4), 16)
        XCTAssertEqual(p.baseDelay(attempt: 5), 30, "32 s is capped")
        XCTAssertEqual(p.baseDelay(attempt: 40), 30)
    }

    func testJitterStaysWithinTwentyPercent() {
        var p = ReconnectPolicy()
        for attempt in 0..<12 {
            let bounds = p.bounds(attempt: attempt)
            let d = p.nextDelay()
            XCTAssert(bounds.contains(d), "attempt \(attempt): \(d) outside \(bounds)")
        }
        XCTAssertEqual(p.attempt, 12)
    }

    func testInjectedRandomPinsTheExtremes() {
        var p = ReconnectPolicy()
        XCTAssertEqual(p.nextDelay { $0.lowerBound }, 0.8, accuracy: 1e-9)   // attempt 0: 1 s − 20 %
        XCTAssertEqual(p.nextDelay { $0.upperBound }, 2.4, accuracy: 1e-9)   // attempt 1: 2 s + 20 %
        XCTAssertEqual(p.nextDelay { _ in 0 }, 4, accuracy: 1e-9)            // attempt 2, no jitter
        XCTAssertEqual(p.nextDelay { _ in 5 }, 8 * 1.2, accuracy: 1e-9, "a misbehaving generator is clamped")
    }

    func testResetStartsOver() {
        var p = ReconnectPolicy()
        _ = p.nextDelay()
        _ = p.nextDelay()
        p.reset()
        XCTAssertEqual(p.attempt, 0)
        XCTAssertEqual(p.nextDelay { _ in 0 }, 1)
    }
}
