import AppKit
import PocketTmuxAgent
import PocketTmuxKit
import SwiftUI

/// Native menu-bar utility panel. Lists, sections, controls, status symbols,
/// menus, and destructive confirmation are supplied by the system.
struct MenuPanelView: View {
    @ObservedObject var controller: AgentController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            List {
                AgentSection(controller: controller)
                ClientsSection(clients: controller.clients, pair: showPairing)
                SessionsSection(controller: controller)
            }
            .listStyle(.inset)

            Divider()
            footer
        }
        .frame(width: 340, height: 420)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func showPairing() {
        openWindow(id: WindowID.pair)
        NSApp.activate()
    }
}

// MARK: - Agent

private struct AgentSection: View {
    @ObservedObject var controller: AgentController

    var body: some View {
        Section("Agent") {
            HStack(spacing: 8) {
                StatusIndicator(state: dotState, title: title)
                Text(title)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Toggle("Agent", isOn: Binding(
                    get: { controller.hasServer },
                    set: { $0 ? controller.start() : controller.stop() }
                ))
                .labelsHidden()
            }

            if !controller.addresses.isEmpty {
                Text(controller.addresses.map(\.ip).joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if controller.errorText != nil {
                Button("Retry") { controller.start() }
            }
        }
    }

    private var dotState: StatusIndicator.State {
        if controller.errorText != nil { return .error }
        return controller.isRunning ? .running : .stopped
    }

    private var title: String {
        if let error = controller.errorText { return error }
        if controller.isRunning { return "Running on Port \(controller.port)" }
        return "Stopped"
    }
}

// MARK: - Connected iPhones

private struct ClientsSection: View {
    let clients: [AgentClientInfo]
    let pair: () -> Void

    var body: some View {
        Section("Connected iPhones") {
            if clients.isEmpty {
                HStack {
                    Text("No iPhone connected")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Pair…", action: pair)
                }
            } else {
                ForEach(clients) { client in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "iphone.gen3")
                            .foregroundStyle(client.attachedSession == nil ? Color.secondary : Color.green)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(client.displayName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(detail(client))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func detail(_ client: AgentClientInfo) -> String {
        let activity = client.attachedSession.map { "attached to \($0.name)" } ?? "browsing"
        return "\(activity) · \(client.remoteAddress) · \(Format.ago(client.connectedAt))"
    }
}

// MARK: - Sessions

private struct SessionsSection: View {
    @ObservedObject var controller: AgentController
    @State private var pendingKill: SessionInfo?

    var body: some View {
        Section("tmux Sessions") {
            if controller.sessions.isEmpty {
                Label(controller.tmuxPath == nil ? "tmux Not Found" : "No tmux Sessions",
                      systemImage: "terminal")
                    .foregroundStyle(controller.tmuxPath == nil ? Color.red : Color.secondary)
            } else {
                ForEach(controller.sessions) { session in
                    HStack(spacing: 8) {
                        Button { controller.openInTerminal(session: session) } label: {
                            sessionLabel(session)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("Open in Terminal", systemImage: "terminal") {
                                controller.openInTerminal(session: session)
                            }
                            Divider()
                            Button("Kill Session…", systemImage: "trash", role: .destructive) {
                                pendingKill = session
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("Actions for \(session.name)")
                    }
                }
            }
        }
        .confirmationDialog(L10n.killSessionTitle(pendingKill?.name ?? ""),
                            isPresented: killBinding, titleVisibility: .visible) {
            Button("Kill", role: .destructive) {
                if let session = pendingKill { controller.killSession(id: session.id) }
                pendingKill = nil
            }
            Button("Cancel", role: .cancel) { pendingKill = nil }
        } message: {
            Text("The session and all of its windows will be killed.")
        }
        .onChange(of: controller.sessions) { _, sessions in
            if let pendingKill, !sessions.contains(where: { $0.id == pendingKill.id }) {
                self.pendingKill = nil
            }
        }
    }

    private func sessionLabel(_ session: SessionInfo) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.headline)
                        .lineLimit(1)
                    if controller.attachedSessionIDs.contains(session.id) {
                        Image(systemName: "iphone.gen3")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Attached on iPhone")
                    }
                }
                Text("\(Format.windows(session.windows)) · \(Format.attached(session.attached)) · \(Format.ago(session.activity))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var killBinding: Binding<Bool> {
        Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } })
    }
}

private enum L10n {
    static func killSessionTitle(_ name: String) -> String { "Kill \(name)?" }
}
