import SwiftUI

/// Screen 3 — Terminal. Full terminal with a thin status bar; streams the live pane.
/// The accessory keyboard (Esc/Ctrl/arrows/F-keys) ships with SwiftTerm — that
/// is what makes LLM prompts (option menus, mode toggles) usable from the phone.
struct TerminalScreen: View {
    @EnvironmentObject private var client: AgentClient
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: TerminalCoordinator?
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            TerminalHost(pendingScreen: client.pendingScreen, coordinator: $coordinator)
                .background(Theme.bg)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { banner }
        .onAppear(perform: appearOnce)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Button(action: leave) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.paper)
            }
            .buttonStyle(.plain)
            Circle().fill(stateColor).frame(width: 7, height: 7)
            Text(stateText)
                .font(Theme.mono(10))
                .foregroundStyle(stateColor)
                .lineLimit(1)
            Spacer()
            Text(client.terminalTitle.isEmpty ? (client.attachedSession?.name ?? "—") : client.terminalTitle)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.paper)
                .lineLimit(1)
            Spacer()
            Button(action: dismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            Button(action: leave) {
                Text(L.disconnect)
                    .font(Theme.mono(10, .semibold))
                    .foregroundStyle(Theme.vermilion)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface)
    }

    private var stateColor: Color {
        switch client.status {
        case .connected: return Theme.moegi
        case .reconnecting, .connecting: return Theme.yamabuki
        case .idle: return Theme.muted
        }
    }

    private var stateText: String {
        switch client.status {
        case .connected: return L.connected
        case .reconnecting: return L.reconnecting
        case .connecting: return L.connecting
        case .idle: return L.disconnected
        }
    }

    private var banner: some View {
        Group {
            if let msg = client.agentBanner {
                Text(msg)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.yamabuki)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 8)
            }
        }
    }

    private func appearOnce() {
        guard !appeared else { return }
        appeared = true
        // Re-attach on return; idempotent (agent repaints fully on attach).
        if let s = client.attachedSession { client.attach(s) }
    }

    private func leave() {
        client.detach()
        dismiss()   // back to the session list
    }

    private func dismissKeyboard() {
        // sendAction(..., to: nil) relies on the deprecated UIApplication.keyWindow,
        // which is nil in SwiftUI apps — use endEditing on the scene's key window.
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .endEditing(true)
    }
}
