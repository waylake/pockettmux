import SwiftUI

/// Small semantic helpers for status only. PocketTmux deliberately does not
/// define an app palette, fixed font scale, or forced appearance: app chrome
/// uses SwiftUI's system text styles, semantic colors, and standard controls.
enum NativeStyle {
    static func statusColor(_ state: ConnState, error: Bool = false) -> Color {
        if error { return .red }
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .idle: return .secondary
        }
    }

    static func statusSymbol(_ state: ConnState, error: Bool = false) -> String {
        if error { return "exclamationmark.circle.fill" }
        switch state {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.trianglehead.2.clockwise.rotate.90.circle"
        case .reconnecting: return "arrow.clockwise.circle.fill"
        case .idle: return "circle"
        }
    }

    static func statusDescription(_ state: ConnState, error: Bool = false) -> String {
        if error { return "Connection error" }
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .idle: return "Not connected"
        }
    }
}

/// Status is communicated by both shape and color, with a VoiceOver label.
struct StatusIndicator: View {
    let state: ConnState
    var error = false

    var body: some View {
        Image(systemName: NativeStyle.statusSymbol(state, error: error))
            .foregroundStyle(NativeStyle.statusColor(state, error: error))
            .accessibilityLabel(NativeStyle.statusDescription(state, error: error))
    }
}
