import XCTest
@testable import PocketTmuxKit

final class WireCodecTests: XCTestCase {
    func testClientRoundTrip() throws {
        let client = ClientIdentity(name: "iPhone", model: "iPhone15,2", app: "PocketTmux iOS 1.0.0")
        let cases: [ClientMessage] = [
            .hello(auth: "t0ken", client: client),
            .sessionList,
            .sessionCreate(name: "work"),
            .sessionRename(id: "$1", name: "renamed"),
            .sessionAttach(id: "$1", cols: 45, rows: 27),
            .sessionAttach(id: "$1", cols: nil, rows: nil),
            .sessionDetach,
            .sessionKill(id: "$2"),
            .windowSelect(id: "@3"),
            .windowCreate,
            .windowKill(id: "@4"),
            .windowRename(id: "@4", name: "logs"),
            .input(Data([0x1b, 0x5b, 0x41, 0x00, 0xff])),
            .paste("multi\nline\ttext ✓"),
            .resize(cols: 45, rows: 27),
            .ping(sentAt: 1_727_760_000.125)
        ]
        for message in cases {
            let data = WireCodec.encode(message)
            XCTAssertEqual(try WireCodec.decodeClient(data), message, String(decoding: data, as: UTF8.self))
        }
    }

    func testServerRoundTrip() throws {
        let session = SessionInfo(id: "$1", name: "work", windows: 2, attached: 1, created: 1, activity: 2)
        let window = WindowInfo(id: "@1", index: 0, name: "zsh", active: true, panes: 1)
        let cases: [ServerMessage] = [
            .helloAck(host: HostIdentity(name: "Mac", agent: "1.0.0", tmux: "tmux 3.7c"), capabilities: ["paste"]),
            .sessionList([session]),
            .sessionAttached(session: session, windows: [window]),
            .sessionDetached(reason: .sessionKilled),
            .windows(sessionID: "$1", windows: [window]),
            .screen(mode: .reset, data: Data("\u{1b}[?1049h".utf8)),
            .pong(sentAt: 3.5),
            .error(code: .auth, message: "invalid token")
        ]
        for message in cases {
            let data = WireCodec.encode(message)
            XCTAssertEqual(try WireCodec.decodeServer(data), message, String(decoding: data, as: UTF8.self))
        }
    }

    func testWireShapeIsStable() throws {
        // Other clients (scripts, future apps) rely on these exact names.
        let data = WireCodec.encode(ClientMessage.sessionAttach(id: "$7", cols: nil, rows: nil))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["type"] as? String, "session.attach")
        XCTAssertEqual((obj["payload"] as? [String: Any])?["id"] as? String, "$7")

        let hello = WireCodec.encode(ClientMessage.hello(auth: "a", client: ClientIdentity(name: "n", model: "m", app: "a")))
        let helloObj = try XCTUnwrap(JSONSerialization.jsonObject(with: hello) as? [String: Any])
        XCTAssertEqual((helloObj["payload"] as? [String: Any])?["v"] as? Int, WireProtocol.version)

        let screen = WireCodec.encode(ServerMessage.screen(mode: .update, data: Data("hi".utf8)))
        let screenObj = try XCTUnwrap(JSONSerialization.jsonObject(with: screen) as? [String: Any])
        XCTAssertEqual((screenObj["payload"] as? [String: Any])?["data"] as? String, "aGk=")
    }

    func testUnknownTypeIsDistinguishedFromMalformed() {
        XCTAssertThrowsError(try WireCodec.decodeServer(Data(#"{"type":"future.thing","payload":{}}"#.utf8))) { error in
            XCTAssertEqual(error as? WireError, .unknownType("future.thing"))
        }
        XCTAssertThrowsError(try WireCodec.decodeServer(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? WireError, .malformed)
        }
        XCTAssertThrowsError(try WireCodec.decodeClient(Data(#"{"type":"resize","payload":{"cols":"x"}}"#.utf8))) { error in
            XCTAssertEqual(error as? WireError, .malformed)
        }
    }

    func testOldProtocolHelloIsRejected() {
        let v1 = Data(#"{"type":"hello","payload":{"v":1,"auth":"t","client":{"name":"","model":"","app":""}}}"#.utf8)
        XCTAssertThrowsError(try WireCodec.decodeClient(v1)) { error in
            XCTAssertEqual(error as? WireError, .unknownType("hello v1"))
        }
    }
}
