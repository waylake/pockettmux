import SwiftUI

/// Design system — 日本の開発ツールの感性 (a Japanese dev-tool sensibility):
/// ink-dark surfaces, washi paper text, a single vermilion accent, mono labels,
/// restrained hierarchy. The *language* is English; the aesthetic stays Japanese.
///
/// Palette (traditional Japanese colors on a terminal-ink base):
///   墨 sumi ink · 藍墨 aizumi surface · 和紙 washi paper
///   朱 shu accent · 山吹 yamabuki warn · 萌葱 moegi success · 藍 ai info
enum Theme {
    static let bg       = Color(0x0B0D11)   // 墨
    static let surface  = Color(0x12161D)   // 藍墨
    static let surface2 = Color(0x181E28)
    static let paper    = Color(0xE4E0D4)   // 和紙
    static let muted    = Color(0x8A8B8D)   // 鼠色
    static let vermilion = Color(0xE0584C)  // 朱 — active/attach
    static let yamabuki  = Color(0xE0A44C)  // 山吹 — warn
    static let moegi     = Color(0x43A885)  // 萌葱 — connected/talk
    static let indigo    = Color(0x4A6FA5)  // 藍 — info/link

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// UI strings. English copy, mono-cased where the aesthetic calls for it.
enum L {
    static let connect       = "Connect"
    static let disconnect    = "Disconnect"
    static let connected     = "Connected"
    static let disconnected  = "Disconnected"
    static let reconnecting  = "Reconnecting…"
    static let connecting    = "Connecting…"
    static let retrying      = "RETRYING…"
    static let refresh       = "Refresh"
    static let sessions      = "Sessions"
    static let newSession    = "New"
    static let delete        = "Delete"
    static let cancel        = "Cancel"
    static let terminal      = "Terminal"
    static let sessionEnd    = "Session ended"
    static let invalidToken  = "Auth failed — check the token"
    static let cantReach     = "Unreachable — check host/port"
    static let emptySessions = "No tmux sessions"
    static let sessionName   = "Name of the new tmux session"
    static let destroyTitle  = "Delete session"
    static let destroyBody   = "The session and its panes will be killed. This cannot be undone."

    static func windows(_ n: Int) -> String { n == 1 ? "1 window" : "\(n) windows" }
    static func clients(_ n: Int) -> String { n == 1 ? "1 attached" : "\(n) attached" }
    static func ago(_ s: TimeInterval) -> String {  // compact relative time
        let now = Date().timeIntervalSince1970
        let d = max(0, now - s)
        if d < 60 { return "just now" }
        if d < 3600 { return "\(Int(d / 60))m ago" }
        if d < 86400 { return "\(Int(d / 3600))h ago" }
        return "\(Int(d / 86400))d ago"
    }
}

extension Color {
    init(_ hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}