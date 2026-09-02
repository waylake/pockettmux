import Foundation

/// `-F` format strings the agent passes to tmux, and the parsers for what
/// comes back. Field separator is a tab — session and window names may
/// contain spaces (and, in principle, `|`).
public enum TmuxFormats {
    public static let separator: Character = "\t"

    public static let sessionList = [
        "#{session_id}", "#{session_name}", "#{session_windows}", "#{session_attached}",
        "#{session_created}", "#{session_activity}"
    ].joined(separator: String(separator))

    public static let windowList = [
        "#{window_id}", "#{window_index}", "#{window_name}", "#{window_active}", "#{window_panes}"
    ].joined(separator: String(separator))

    /// Per-pane state the phone's emulator must be primed with on attach.
    public static let paneState = [
        "#{pane_id}", "#{alternate_on}", "#{mouse_any_flag}", "#{mouse_sgr_flag}",
        "#{keypad_cursor_flag}", "#{history_size}", "#{pane_width}", "#{pane_height}",
        "#{cursor_x}", "#{cursor_y}", "#{window_id}"
    ].joined(separator: String(separator))

    public static func parseSessions(_ text: String) -> [SessionInfo] {
        text.split(separator: "\n").compactMap { parseSession(String($0)) }
    }

    public static func parseSession(_ line: String) -> SessionInfo? {
        let f = fields(line)
        guard f.count >= 6, let windows = Int(f[2]), let attached = Int(f[3]),
              let created = TimeInterval(f[4]), let activity = TimeInterval(f[5]) else { return nil }
        return SessionInfo(id: f[0], name: f[1], windows: windows, attached: attached,
                           created: created, activity: activity)
    }

    public static func parseWindows(_ text: String) -> [WindowInfo] {
        text.split(separator: "\n").compactMap { parseWindow(String($0)) }
    }

    public static func parseWindow(_ line: String) -> WindowInfo? {
        let f = fields(line)
        guard f.count >= 5, let index = Int(f[1]), let panes = Int(f[4]) else { return nil }
        return WindowInfo(id: f[0], index: index, name: f[2], active: f[3] == "1", panes: panes)
    }

    public struct PaneState: Equatable, Sendable {
        public var paneID: String
        public var windowID: String
        public var alternateScreen: Bool
        public var mouseReporting: Bool
        public var mouseSGR: Bool
        public var applicationCursorKeys: Bool
        public var historySize: Int
        public var width: Int
        public var height: Int
        /// 0-based, relative to the visible screen.
        public var cursorX: Int
        public var cursorY: Int

        public init(paneID: String, windowID: String, alternateScreen: Bool, mouseReporting: Bool, mouseSGR: Bool,
                    applicationCursorKeys: Bool, historySize: Int, width: Int, height: Int,
                    cursorX: Int, cursorY: Int) {
            self.paneID = paneID
            self.windowID = windowID
            self.alternateScreen = alternateScreen
            self.mouseReporting = mouseReporting
            self.mouseSGR = mouseSGR
            self.applicationCursorKeys = applicationCursorKeys
            self.historySize = historySize
            self.width = width
            self.height = height
            self.cursorX = cursorX
            self.cursorY = cursorY
        }
    }

    public static func parsePaneState(_ line: String) -> PaneState? {
        let f = fields(line.trimmingCharacters(in: .whitespacesAndNewlines))
        guard f.count >= 11, f[0].hasPrefix("%"), f[10].hasPrefix("@") else { return nil }
        return PaneState(paneID: f[0], windowID: f[10], alternateScreen: f[1] == "1", mouseReporting: f[2] == "1",
                         mouseSGR: f[3] == "1", applicationCursorKeys: f[4] == "1",
                         historySize: Int(f[5]) ?? 0, width: Int(f[6]) ?? 0, height: Int(f[7]) ?? 0,
                         cursorX: Int(f[8]) ?? 0, cursorY: Int(f[9]) ?? 0)
    }

    private static func fields(_ line: String) -> [String] {
        line.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
    }
}

/// tmux target/name validation shared by both ends so the phone can reject
/// early and the agent can reject authoritatively.
public enum TmuxNames {
    /// A session or window name the user may type. tmux itself rejects `.`
    /// and `:` in session names (they are target syntax); a leading `-` would
    /// read as an option on the tmux command line.
    public static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 64, trimmed.first != "-" else { return false }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && !":.".unicodeScalars.contains(scalar)
        }
    }

    /// Only tmux's own ids (`$1`, `@2`, `%3`) are accepted as targets; the
    /// agent never passes user text to `-t`.
    public static func isSessionID(_ id: String) -> Bool { isID(id, prefix: "$") }
    public static func isWindowID(_ id: String) -> Bool { isID(id, prefix: "@") }
    public static func isPaneID(_ id: String) -> Bool { isID(id, prefix: "%") }

    private static func isID(_ id: String, prefix: Character) -> Bool {
        guard id.first == prefix, id.count >= 2 else { return false }
        return id.dropFirst().allSatisfy(\.isNumber)
    }
}
