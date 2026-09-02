import SwiftUI
import PocketTmuxKit

/// Screen 2 — Sessions. Live tmux sessions of the connected Mac: attach,
/// create, rename, kill; pull to refresh; connection status under the title.
struct SessionListView: View {
    @EnvironmentObject private var client: AgentClient
    @EnvironmentObject private var store: ProfileStore
    let profileID: HostProfile.ID
    @Binding var path: [Route]

    @State private var showNew = false
    @State private var newName = ""
    @State private var showInvalidName = false
    @State private var pendingKill: SessionInfo?
    @State private var renaming: SessionInfo?
    @State private var renameText = ""
    /// Name passed to `sessionCreate`; attached when the next list push has it.
    @State private var pendingCreateName: String?

    var body: some View {
        VStack(spacing: 0) {
            statusRow
            if client.sessions.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(store.profile(profileID)?.name ?? client.host?.name ?? L.sessions)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { newName = ""; showNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L.newSession)
                Menu {
                    Button(role: .destructive) { client.disconnect(); path = [] } label: {
                        Label(L.disconnect, systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert(L.newSession, isPresented: $showNew) {
            TextField("main", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(L.newSession) { create(name: newName) }
            Button(L.cancel, role: .cancel) {}
        } message: {
            Text(L.sessionName)
        }
        .alert(L.renameSession, isPresented: renameBinding, presenting: renaming) { session in
            TextField(session.name, text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(L.rename) { rename(session, to: renameText) }
            Button(L.cancel, role: .cancel) { renaming = nil }
        } message: { _ in
            Text(L.sessionName)
        }
        .alert(L.invalidName, isPresented: $showInvalidName) {
            Button(L.done, role: .cancel) {}
        }
        .confirmationDialog(L.killSessionTitle(pendingKill?.name ?? ""), isPresented: killBinding, titleVisibility: .visible) {
            Button(L.kill, role: .destructive) {
                if let s = pendingKill { client.killSession(id: s.id) }
                pendingKill = nil
            }
            Button(L.cancel, role: .cancel) { pendingKill = nil }
        } message: {
            Text(L.killSessionBody)
        }
        .onAppear {
            if client.status == .connected { client.listSessions() }
        }
        .onChange(of: client.sessions) { sessions in
            guard let name = pendingCreateName, let s = sessions.first(where: { $0.name == name }) else { return }
            pendingCreateName = nil
            attach(s)
        }
    }

    // MARK: - Status

    private var statusRow: some View {
        let error = client.status != .connected ? client.lastError : nil
        let color = Theme.statusColor(client.status, error: error != nil)
        return HStack(spacing: 8) {
            StatusDot(color: color)
            Text(statusText(error: error))
                .font(Theme.mono(11))
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Theme.surface)
    }

    private func statusText(error: String?) -> String {
        switch client.status {
        case .connected:
            var parts = [L.connected]
            if let tmux = client.host?.tmux, !tmux.isEmpty { parts.append(tmux) }
            if let rtt = client.rtt { parts.append(L.rtt(rtt)) }
            return parts.joined(separator: " · ")
        case .connecting: return L.connecting
        case .reconnecting: return error.map { "\(L.reconnecting) \($0)" } ?? L.reconnecting
        case .idle: return error ?? L.disconnected
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(client.sessions) { s in
                row(s)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.surface2)
                    .contentShape(Rectangle())
                    .onTapGesture { attach(s) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingKill = s } label: {
                            Label(L.kill, systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button { renameText = s.name; renaming = s } label: {
                            Label(L.rename, systemImage: "pencil")
                        }
                        Button(role: .destructive) { pendingKill = s } label: {
                            Label(L.kill, systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { client.listSessions() }
    }

    private func row(_ s: SessionInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(s.name)
                    .font(Theme.mono(17, .semibold))
                    .foregroundStyle(Theme.paper)
                    .lineLimit(1)
                Text("\(L.windows(s.windows)) · \(L.clients(s.attached)) · \(L.ago(s.activity))")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if client.attached?.session.id == s.id {
                Image(systemName: "iphone")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.moegi)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted.opacity(0.6))
        }
        .padding(.vertical, 6)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(L.emptySessions)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.paper)
            Text(L.emptyHint)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.muted)
            Button { newName = ""; showNew = true } label: {
                Text(L.newSession)
                    .font(Theme.mono(12, .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.surface2)
                    .foregroundStyle(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func attach(_ s: SessionInfo) {
        client.attach(sessionID: s.id)
        if path.last != .terminal { path.append(.terminal) }
    }

    private func create(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard TmuxNames.isValidName(trimmed) else { showInvalidName = true; return }
        pendingCreateName = trimmed
        client.createSession(name: trimmed)
    }

    private func rename(_ s: SessionInfo, to name: String) {
        renaming = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard TmuxNames.isValidName(trimmed) else { showInvalidName = true; return }
        client.renameSession(id: s.id, name: trimmed)
    }

    private var killBinding: Binding<Bool> {
        Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } })
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}
