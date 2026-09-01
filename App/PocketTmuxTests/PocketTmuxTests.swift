import XCTest
@testable import PocketTmux

final class PocketTmuxTests: XCTestCase {
    /// Smoke test: the app module compiles, links, and the SwiftUI app type
    /// is constructable. P1 protocol-codec tests (transport encode/decode,
    /// reconnect state machine, tmux control-mode frame parsing) land
    /// here as the transport layer is added.
    func testAppSceneIsConstructable() {
        _ = PocketTmuxApp()
    }
}
