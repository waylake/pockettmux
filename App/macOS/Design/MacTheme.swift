import SwiftUI

/// Semantic helpers only. The Mac UI follows the system appearance and accent
/// color; fixed app palettes and custom text scales are intentionally absent.
enum MacTheme {
    static func statusColor(_ state: StatusIndicator.State) -> Color {
        switch state {
        case .running: return .green
        case .connecting: return .orange
        case .stopped: return .secondary
        case .error: return .red
        }
    }

    static func statusSymbol(_ state: StatusIndicator.State) -> String {
        switch state {
        case .running: return "checkmark.circle.fill"
        case .connecting: return "arrow.trianglehead.2.clockwise.rotate.90.circle"
        case .stopped: return "circle"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

/// Status uses both symbol shape and semantic color, with a VoiceOver label.
struct StatusIndicator: View {
    enum State { case running, connecting, stopped, error }

    let state: State
    var title: String?

    var body: some View {
        Image(systemName: MacTheme.statusSymbol(state))
            .foregroundStyle(MacTheme.statusColor(state))
            .accessibilityLabel(title ?? defaultTitle)
    }

    private var defaultTitle: String {
        switch state {
        case .running: return "Running"
        case .connecting: return "Connecting"
        case .stopped: return "Stopped"
        case .error: return "Error"
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
