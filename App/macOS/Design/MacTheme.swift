import SwiftUI

/// Design system for the Mac app. Surfaces follow the system appearance
/// (semantic colors); accent and status colors are the shared palette
/// (traditional Japanese colors on terminal ink) the iPhone app uses.
enum MacTheme {
    static let sumi      = Color(0x0B0D11)   // 墨 — QR modules
    static let washi     = Color(0xE4E0D4)   // 和紙 — QR background
    static let shu       = Color(0xE0584C)   // 朱 — accent / error / destructive
    static let yamabuki  = Color(0xE0A44C)   // 山吹 — connecting / warning
    static let moegi     = Color(0x43A885)   // 萌葱 — running / connected
    static let ai        = Color(0x4A6FA5)   // 藍 — info / link
    static let muted     = Color.secondary   // 鼠 — idle / stopped

    static let radius: CGFloat = 6

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Section label in mono small caps: `SESSIONS`, `CONNECTED IPHONES`.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(MacTheme.mono(10, .medium))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }
}

/// The 8pt status dot — one vocabulary for every screen.
struct StatusDot: View {
    enum State { case running, connecting, stopped, error }

    let state: State

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch state {
        case .running: return MacTheme.moegi
        case .connecting: return MacTheme.yamabuki
        case .stopped: return MacTheme.muted
        case .error: return MacTheme.shu
        }
    }
}

/// English copy and compact formatting shared by the views.
enum Format {
    static func windows(_ n: Int) -> String { n == 1 ? "1 window" : "\(n) windows" }
    static func attached(_ n: Int) -> String { n == 1 ? "1 attached" : "\(n) attached" }

    /// "just now" / "4m ago" / "2h ago" / "3d ago".
    static func ago(_ epoch: TimeInterval) -> String {
        let d = max(0, Date().timeIntervalSince1970 - epoch)
        if d < 60 { return "just now" }
        if d < 3600 { return "\(Int(d / 60))m ago" }
        if d < 86400 { return "\(Int(d / 3600))h ago" }
        return "\(Int(d / 86400))d ago"
    }

    static func ago(_ date: Date) -> String { ago(date.timeIntervalSince1970) }

    /// "abcd••••••••" — enough to tell tokens apart, never the whole secret.
    static func masked(_ token: String) -> String {
        String(token.prefix(4)) + String(repeating: "•", count: max(8, token.count - 4))
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
