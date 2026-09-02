import SwiftUI

/// Screen 2 — Sessions. Live tmux sessions from the agent; pull to
/// refresh; swipe to destroy (with confirm); create via the toolbar.
struct SessionListView: View {
    @EnvironmentObject private var client: AgentClient
    @Binding var path: [Route]

    @State private var showNew = false
    @State private var newName = ""
    @State private var pendingKill: SessionInfo?
    @State private var arrived = false

    var body: some View {
        Group {
            if client.sessions.isEmpty {
                empty
            } else {
                list
            }
        }
        .navigationTitle(L.sessions)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: {
                    Label(L.newSession, systemImage: "plus")
                }
                .font(Theme.mono(12, .semibold))
            }
        }
        .alert(L.newSession, isPresented: $showNew) {
            TextField("main", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(L.connect) { create(name: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L.sessionName)
        }
        .confirmationDialog("DELETE \(pendingKill?.name ?? "")", isPresented: killDialogBinding, titleVisibility: .visible) {
            Button(L.delete, role: .destructive) {
                if let s = pendingKill { client.destroy(s) }
                pendingKill = nil
            }
            Button(L.cancel, role: .cancel) { pendingKill = nil }
        } message: {
            Text(L.destroyBody)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            if client.status == .connected { client.listNow() }
        }
    }

    private var killDialogBinding: Binding<Bool> {
        Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } })
    }

    private var list: some View {
        List {
            ForEach(client.sessions) { s in
                row(s)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.surface2)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingKill = s } label: {
                            Label(L.delete, systemImage: "trash")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { client.attach(s); path.append(.terminal) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { client.listNow() }
        .toolbarBackground(Theme.bg, for: .navigationBar)
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
            Text("$ tmux new -s main")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func create(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        client.createSession(name: trimmed)
        // Agent replies with a fresh session.list push; still refresh promptly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { _ = client.listNow() }
    }
}
