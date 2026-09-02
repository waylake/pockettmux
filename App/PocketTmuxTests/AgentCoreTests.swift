import XCTest
@testable import PocketTmux

/// Unit tests for the shared agent core (tmux ls parser, control-frame parser,
/// octal unescaping, hex codec) — verified against captured tmux 3.7c output.
final class AgentCoreTests: XCTestCase {

    func testHexRoundTrip() {
        XCTAssertEqual(Hex.encode(Data([0x1b, 0x5b, 0x41])), "1b5b41")
        XCTAssertEqual(Hex.decode("1b5b41"), Data([0x1b, 0x5b, 0x41]))
        XCTAssertNil(Hex.decode("zz"))
        XCTAssertNil(Hex.decode("abc")) // odd length
    }

    func testUnescapeOctal() {
        // \033 = ESC, \015 = CR, \\ = backslash, plain UTF-8 passes through.
        let raw = Data("\\033[?2004h\\015\\0177\\\\HELLO ✓".utf8)
        let out = TmuxControlParser.unescapeOctal(raw)
        XCTAssertEqual(out.prefix(2), [0x1b, 0x5b])
        XCTAssertEqual(Array(out.filter { $0 == 0x0d }).count, 1)
        XCTAssertTrue(String(decoding: out, as: UTF8.self).hasSuffix("\\HELLO ✓"))
    }

    func testLsParser() {
        let line = "$1|main|3|2|1788098261|1788267833"
        let s = TmuxLsParser.parseLine(line)!
        XCTAssertEqual(s.id, "$1")
        XCTAssertEqual(s.name, "main")
        XCTAssertEqual(s.windows, 3)
        XCTAssertEqual(s.attached, 2)
        let sessions = TmuxLsParser.parse("$1|a|1|0|1|2\n$2|b c|2|1|3|4")
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[1].name, "b c")
        XCTAssertNil(TmuxLsParser.parseLine("garbage"))
    }

    func testControlFrameParsing() {
        let p = TmuxControlParser()
        for ev in p.parseLine(Data("%session-changed $12 main".utf8)) {
            if case .sessionChanged(let id, let name) = ev {
                XCTAssertEqual(id, "$12"); XCTAssertEqual(name, "main")
            } else { XCTFail("wrong event") }
        }
        for ev in p.parseLine(Data("%window-pane-changed @5 %201".utf8)) {
            if case .windowPaneChanged(_, let pane) = ev { XCTAssertEqual(pane, "%201") } else { XCTFail() }
        }
        let outEvs = p.parseLine(Data("%output %201 hello\\040world".utf8))
        if case .output(let pane, let bytes) = outEvs[0] {
            XCTAssertEqual(pane, "%201")
            XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "hello world")
        } else { XCTFail() }
        XCTAssertEqual(p.parseLine(Data("noise line".utf8)), [])
        for ev in p.parseLine(Data("%exit".utf8)) { if case .exit = ev {} else { XCTFail() } }
    }
}

/// App-level protocol decoding (mirror of the wire format).
final class WireCoderTests: XCTestCase {
    func testDecodeScreen() {
        let frame = "{\"type\":\"screen\",\"payload\":{\"mode\":\"reset\",\"data\":\"aGk=\"}}"
        guard case .screen(let mode, let data) = WireCoder.decode(frame)! else { return XCTFail() }
        XCTAssertEqual(mode, "reset")
        XCTAssertEqual(data, Data("hi".utf8))
    }
    func testDecodeSessionList() {
        let frame = "{\"type\":\"session.list\",\"payload\":{\"sessions\":[{\"id\":\"$1\",\"name\":\"m\",\"windows\":2,\"attached\":1,\"created\":1,\"activity\":2}]}}"
        guard case .sessionList(let list) = WireCoder.decode(frame)! else { return XCTFail() }
        XCTAssertEqual(list.first?.name, "m")
        XCTAssertEqual(list.first?.windows, 2)
    }
    func testEnvelope() {
        let s = WireCoder.envelope(type: "ping", payload: [:])
        XCTAssertTrue(s.contains("\"type\":\"ping\""))
    }
}
