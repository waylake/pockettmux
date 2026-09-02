import AppKit
import PocketTmuxAgent
import PocketTmuxKit
import SwiftUI

/// The menu-bar panel: agent status + addresses, connected iPhones,
/// tmux sessions, footer actions. ~320pt wide.
struct MenuPanelView: View {
    @ObservedObject var controller: AgentController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(controller: controller)
            Divider()
            ClientsSection(clients: controller.clients, pair: showPairing)
            Divider()
            SessionsSection(controller: controller)
            Divider()
            footer
        }
        .frame(width: 320)
        .onAppear { controller.beginPolling() }
        .onDisappear { controller.endPolling() }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Pair iPhone…", action: showPairing)
            Button("Settings…") {
                openSettings()
                NSApp.activate()
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.link)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func showPairing() {
        openWindow(id: WindowID.pair)
        NSApp.activate()
    }
}

// MARK: - Header

private struct HeaderView: View {
    @ObservedObject var controller: AgentController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                StatusDot(state: dotState)
                Text(title)
                    .font(MacTheme.mono(12, .medium))
                    .foregroundStyle(controller.errorText != nil ? MacTheme.shu : .primary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if controller.errorText != nil {
                    Button("Retry") { controller.start() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
                Toggle("", isOn: Binding(
                    get: { controller.hasServer },
                    set: { $0 ? controller.start() : controller.stop() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            if !controller.addresses.isEmpty {
                Text(controller.addresses.map(\.ip).joined(separator: " · "))
                    .font(MacTheme.mono(10))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var dotState: StatusDot.State {
        if controller.errorText != nil { return .error }
        return controller.isRunning ? .running : .stopped
    }

    private var title: String {
        if let error = controller.errorText { return error }
        if controller.isRunning { return "Agent running · port \(controller.port)" }
        return "Stopped"
    }
}

// MARK: - Connected iPhones

private struct ClientsSection: View {
    let clients: [AgentClientInfo]
    let pair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("CONNECTED IPHONES")
            if clients.isEmpty {
                HStack(spacing: 4) {
                    Text("No iPhone connected —")
                        .foregroundStyle(.secondary)
                    Button("Pair iPhone…", action: pair)
                        .buttonStyle(.link)
                }
                .font(.system(size: 12))
            } else {
                ForEach(clients) { client in
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.gen3")
                            .foregroundStyle(client.attachedSession == nil ? MacTheme.muted : MacTheme.moegi)
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(client.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(detail(client))
                                .font(MacTheme.mono(10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func detail(_ client: AgentClientInfo) -> String {
        let what = client.attachedSession.map { "attached to \($0.name)" } ?? "browsing"
        return "\(what) · \(client.remoteAddress) · \(Format.ago(client.connectedAt))"
    }
}

// MARK: - Sessions

private struct SessionsSection: View {
    @ObservedObject var controller: AgentController
    @State private var pendingKill: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("TMUX SESSIONS")
            if controller.sessions.isEmpty {
                Text(controller.tmuxPath == nil ? "tmux not found" : "No tmux sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.sessions) { session in
                    if pendingKill == session.id {
                        killConfirm(session)
                    } else {
                        SessionRow(session: session,
                                   phoneAttached: controller.attachedSessionIDs.contains(session.id),
                                   open: { controller.openInTerminal(session: session) },
                                   kill: { pendingKill = session.id })
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: controller.sessions) { _, sessions in
            if let pendingKill, !sessions.contains(where: { $0.id == pendingKill }) { self.pendingKill = nil }
        }
    }

    private func killConfirm(_ session: SessionInfo) -> some View {
        HStack(spacing: 10) {
            Text("Kill \(session.name)?")
                .font(MacTheme.mono(12, .medium))
                .foregroundStyle(MacTheme.shu)
                .lineLimit(1)
            Spacer()
            Button("Cancel") { pendingKill = nil }
            Button("Kill") {
                controller.killSession(id: session.id)
                pendingKill = nil
            }
            .tint(MacTheme.shu)
        }
        .buttonStyle(.link)
        .font(.system(size: 12))
        .padding(.vertical, 2)
    }
}

private struct SessionRow: View {
    let session: SessionInfo
    let phoneAttached: Bool
    let open: () -> Void
    let kill: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(MacTheme.mono(12, .semibold))
                        .lineLimit(1)
                    if phoneAttached {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 10))
                            .foregroundStyle(MacTheme.moegi)
                    }
                }
                Text("\(Format.windows(session.windows)) · \(Format.attached(session.attached)) · \(Format.ago(session.activity))")
                    .font(MacTheme.mono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if hovering {
                Button(action: open) {
                    Image(systemName: "terminal")
                }
                .help("Open in Terminal")
                Button(action: kill) {
                    Image(systemName: "xmark")
                }
                .help("Kill session")
                .foregroundStyle(MacTheme.shu)
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: MacTheme.radius)
                .fill(hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .padding(.horizontal, -4)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open in Terminal", action: open)
            Divider()
            Button("Kill Session…", role: .destructive, action: kill)
        }
    }
}
