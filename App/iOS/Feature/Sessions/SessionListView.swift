import SwiftUI
import PocketTmuxKit

/// Live tmux sessions for the connected Mac. Rows are native navigation links;
/// destructive and secondary actions use swipe actions and context menus.
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
    @State private var pendingCreateName: String?

    var body: some View {
        List {
            Section {
                statusLabel
            }

            if client.sessions.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(client.sessions) { session in
                        NavigationLink(value: Route.terminal(sessionID: session.id)) {
                            row(session)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { pendingKill = session } label: {
                                Label(L.kill, systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button { renameText = session.name; renaming = session } label: {
                                Label(L.rename, systemImage: "pencil")
                            }
                            Button(role: .destructive) { pendingKill = session } label: {
                                Label(L.kill, systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .refreshable { client.listSessions() }
        .navigationTitle(store.profile(profileID)?.name ?? client.host?.name ?? L.sessions)
        .navigationBarTitleDisplayMode(.inline)
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
                .accessibilityLabel(L.more)
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
        .confirmationDialog(L.killSessionTitle(pendingKill?.name ?? ""), isPresented: killBinding,
                            titleVisibility: .visible) {
            Button(L.kill, role: .destructive) {
                if let session = pendingKill { client.killSession(id: session.id) }
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
            guard let name = pendingCreateName,
                  let session = sessions.first(where: { $0.name == name }) else { return }
            pendingCreateName = nil
            path.append(.terminal(sessionID: session.id))
        }
    }

    private var statusLabel: some View {
        let error = client.status != .connected ? client.lastError : nil
        return HStack(spacing: 8) {
            StatusIndicator(state: client.status, error: error != nil)
            Text(statusText(error: error))
                .font(.caption)
                .foregroundStyle(NativeStyle.statusColor(client.status, error: error != nil))
                .lineLimit(1)
            Spacer()
        }
        .accessibilityElement(children: .combine)
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

    private func row(_ session: SessionInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(L.windows(session.windows)) · \(L.clients(session.attached)) · \(L.ago(session.activity))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if client.attached?.session.id == session.id {
                Image(systemName: "iphone.gen3")
                    .foregroundStyle(.green)
                    .accessibilityLabel(L.attachedOnIPhone)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(L.emptySessions, systemImage: "terminal")
            } description: {
                Text(L.emptyDescription)
            } actions: {
                Button(L.newSession, systemImage: "plus") { newName = ""; showNew = true }
                    .buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(L.emptySessions)
                    .font(.headline)
                Text(L.emptyDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(L.newSession, systemImage: "plus") { newName = ""; showNew = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func create(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard TmuxNames.isValidName(trimmed) else { showInvalidName = true; return }
        pendingCreateName = trimmed
        client.createSession(name: trimmed)
    }

    private func rename(_ session: SessionInfo, to name: String) {
        renaming = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard TmuxNames.isValidName(trimmed) else { showInvalidName = true; return }
        client.renameSession(id: session.id, name: trimmed)
    }

    private var killBinding: Binding<Bool> {
        Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } })
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}
