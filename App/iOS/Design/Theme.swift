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
    static let vermilion = Color(0xE0584C)  // 朱 — active/attach/destructive
    static let yamabuki  = Color(0xE0A44C)  // 山吹 — warn/connecting
    static let moegi     = Color(0x43A885)  // 萌葱 — connected/success
    static let indigo    = Color(0x4A6FA5)  // 藍 — info/link

    static let radius: CGFloat = 6

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Status dot vocabulary: moegi = connected, yamabuki = connecting or
    /// reconnecting, muted = idle, shu = error.
    static func statusColor(_ state: ConnState, error: Bool = false) -> Color {
        if error { return vermilion }
        switch state {
        case .connected: return moegi
        case .connecting, .reconnecting: return yamabuki
        case .idle: return muted
        }
    }
}

/// `SESSIONS`-style section label: mono, small, tracked, muted.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.mono(10, .semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.muted)
            .textCase(.uppercase)
    }
}

/// 7pt status dot.
struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
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
