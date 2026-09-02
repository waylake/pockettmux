import XCTest
@testable import PocketTmuxKit

final class TmuxParsingTests: XCTestCase {
    func testUnescapeOctal() {
        // \033 = ESC, \015 = CR, \\ = backslash, plain UTF-8 passes through.
        let raw = Data("\\033[?2004h\\015\\0177\\\\HELLO ✓".utf8)
        let out = TmuxControlParser.unescapeOctal(raw)
        XCTAssertEqual(Array(out.prefix(2)), [0x1b, 0x5b])
        XCTAssertEqual(out.filter { $0 == 0x0d }.count, 1)
        XCTAssertTrue(String(decoding: out, as: UTF8.self).hasSuffix("\\HELLO ✓"))
        // A lone backslash that is not an escape survives.
        XCTAssertEqual(TmuxControlParser.unescapeOctal(Data("a\\b".utf8)), Array("a\\b".utf8))
    }

    func testControlFrames() {
        let p = TmuxControlParser()
        XCTAssertEqual(p.parseLine(Data("%session-changed $12 main\r\n".utf8)), [.sessionChanged(id: "$12", name: "main")])
        XCTAssertEqual(p.parseLine(Data("%window-pane-changed @5 %201".utf8)), [.windowPaneChanged(windowID: "@5", paneID: "%201")])
        XCTAssertEqual(p.parseLine(Data("%session-window-changed $1 @7".utf8)), [.sessionWindowChanged(sessionID: "$1", windowID: "@7")])
        XCTAssertEqual(p.parseLine(Data("%window-renamed @7 build logs".utf8)), [.windowRenamed(windowID: "@7", name: "build logs")])
        XCTAssertEqual(p.parseLine(Data("%window-add @8".utf8)), [.windowAdd(windowID: "@8")])
        XCTAssertEqual(p.parseLine(Data("%window-close @8".utf8)), [.windowClose(windowID: "@8")])
        XCTAssertEqual(p.parseLine(Data("%layout-change @1 b25d,80x24,0,0,1 b25d,80x24,0,0,1 *".utf8)), [.layoutChange(windowID: "@1")])
        XCTAssertEqual(p.parseLine(Data("%sessions-changed".utf8)), [.sessionsChanged])
        XCTAssertEqual(p.parseLine(Data("%output %201 hello\\040world".utf8)),
                       [.output(pane: "%201", bytes: Array("hello world".utf8))])
        XCTAssertEqual(p.parseLine(Data("%begin 1727760000 3 1".utf8)), [])
        XCTAssertEqual(p.parseLine(Data("%3 %201".utf8)), [.commandOutput(num: 3, text: "%201")])
        XCTAssertEqual(p.parseLine(Data("%exit".utf8)), [.exit(reason: nil)])
        XCTAssertEqual(p.parseLine(Data("%exit session closed".utf8)), [.exit(reason: "session closed")])
        XCTAssertEqual(p.parseLine(Data("noise line".utf8)), [])
    }

    func testSessionList() {
        let text = "$1\tmain\t3\t2\t1788098261\t1788267833\n$2\tb c\t2\t1\t3\t4\ngarbage\n"
        let sessions = TmuxFormats.parseSessions(text)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0], SessionInfo(id: "$1", name: "main", windows: 3, attached: 2,
                                                created: 1_788_098_261, activity: 1_788_267_833))
        XCTAssertEqual(sessions[1].name, "b c")
    }

    func testWindowList() {
        let windows = TmuxFormats.parseWindows("@1\t0\tzsh\t1\t1\n@4\t2\tpi agent\t0\t2\n")
        XCTAssertEqual(windows, [
            WindowInfo(id: "@1", index: 0, name: "zsh", active: true, panes: 1),
            WindowInfo(id: "@4", index: 2, name: "pi agent", active: false, panes: 2)
        ])
    }

    func testPaneState() {
        let state = TmuxFormats.parsePaneState("%3\t1\t1\t1\t0\t1234\t80\t24\t5\t12\t@2\n")
        XCTAssertEqual(state, TmuxFormats.PaneState(paneID: "%3", windowID: "@2", alternateScreen: true,
                                                    mouseReporting: true, mouseSGR: true, applicationCursorKeys: false,
                                                    historySize: 1234, width: 80, height: 24, cursorX: 5, cursorY: 12))
        XCTAssertNil(TmuxFormats.parsePaneState("no pane"))
        XCTAssertNil(TmuxFormats.parsePaneState("%3\t1\t1\t1\t0\t1234\t80\t24"))   // old, short format
    }

    func testNames() {
        XCTAssertTrue(TmuxNames.isValidName("work"))
        XCTAssertTrue(TmuxNames.isValidName("pi agent 2"))
        XCTAssertFalse(TmuxNames.isValidName(""))
        XCTAssertFalse(TmuxNames.isValidName("a:b"))
        XCTAssertFalse(TmuxNames.isValidName("a.b"))
        XCTAssertFalse(TmuxNames.isValidName("new\nline"))
        XCTAssertFalse(TmuxNames.isValidName(String(repeating: "x", count: 65)))
        XCTAssertTrue(TmuxNames.isSessionID("$12"))
        XCTAssertFalse(TmuxNames.isValidName("-x"))
        XCTAssertFalse(TmuxNames.isSessionID("$"))
        XCTAssertFalse(TmuxNames.isSessionID("main"))
        XCTAssertTrue(TmuxNames.isWindowID("@0"))
        XCTAssertTrue(TmuxNames.isPaneID("%201"))
        XCTAssertFalse(TmuxNames.isPaneID("%2 ; kill-server"))
    }
}
