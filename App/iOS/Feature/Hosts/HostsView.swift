import SwiftUI

/// Screen 1 — Macs. Saved profiles, Macs found via Bonjour, add/settings.
struct HostsView: View {
    @EnvironmentObject private var client: AgentClient
    @EnvironmentObject private var store: ProfileStore
    @StateObject private var bonjour = BonjourBrowser()
    @Binding var sheet: HostSheet?
    let open: (HostProfile) -> Void

    @State private var pendingForget: HostProfile?
    @State private var renaming: HostProfile?
    @State private var renameText = ""

    var body: some View {
        List {
            tagline
            if store.profiles.isEmpty {
                onboarding
            } else {
                savedSection
            }
            if !bonjour.hosts.isEmpty {
                nearbySection
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(L.appName)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { sheet = .add } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L.addMac)
                Button { sheet = .settings } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(L.settings)
            }
        }
        .sheet(item: $sheet, content: sheetContent)
        .confirmationDialog(L.forgetTitle(pendingForget?.name ?? ""), isPresented: forgetBinding, titleVisibility: .visible) {
            Button(L.forget, role: .destructive) {
                if let p = pendingForget {
                    if client.profileID == p.id { client.disconnect() }
                    store.remove(p.id)
                }
                pendingForget = nil
            }
            Button(L.cancel, role: .cancel) { pendingForget = nil }
        } message: {
            Text(L.forgetBody)
        }
        .alert(L.rename, isPresented: renameBinding, presenting: renaming) { profile in
            TextField(profile.name, text: $renameText)
            Button(L.save) {
                var p = profile
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { p.name = name; store.upsert(p) }
                renaming = nil
            }
            Button(L.cancel, role: .cancel) { renaming = nil }
        } message: { _ in
            Text(L.rename)
        }
        .onAppear(perform: bonjour.start)
        .onDisappear(perform: bonjour.stop)
    }

    // MARK: - Sections

    private var tagline: some View {
        Text(L.tagline)
            .font(Theme.mono(10))
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
            .listRowBackground(Theme.bg)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 16, trailing: 20))
    }

    private var savedSection: some View {
        Section {
            ForEach(store.profiles) { profile in
                Button { open(profile) } label: { profileRow(profile) }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.surface2)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingForget = profile } label: {
                            Label(L.delete, systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button { renameText = profile.name; renaming = profile } label: {
                            Label(L.rename, systemImage: "pencil")
                        }
                        Button { sheet = .edit(profile.id) } label: {
                            Label(L.edit, systemImage: "slider.horizontal.3")
                        }
                        if client.profileID == profile.id, client.status != .idle {
                            Button { client.disconnect() } label: {
                                Label(L.disconnect, systemImage: "xmark.circle")
                            }
                        }
                        Button(role: .destructive) { pendingForget = profile } label: {
                            Label(L.forget, systemImage: "trash")
                        }
                    }
            }
        } header: {
            SectionLabel(L.savedMacs)
        }
    }

    private var nearbySection: some View {
        Section {
            ForEach(bonjour.hosts) { host in
                nearbyRow(host)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.surface2)
            }
        } header: {
            SectionLabel(L.nearbyMacs)
        } footer: {
            Text(L.tailscaleNote)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.muted)
        }
        .listSectionSeparator(.hidden)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.onboardingTitle)
                .font(Theme.mono(15, .semibold))
                .foregroundStyle(Theme.paper)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(L.onboardingSteps, id: \.self) { step in
                    Text(step)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.paper.opacity(0.85))
                }
            }
            Button { sheet = .add } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text(L.scanQR).font(Theme.mono(13, .semibold)).tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.vermilion)
                .foregroundStyle(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .listRowBackground(Theme.bg)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }

    // MARK: - Rows

    private func profileRow(_ profile: HostProfile) -> some View {
        let current = client.profileID == profile.id && client.status != .idle
        let error = client.profileID == profile.id ? client.lastError : nil
        return HStack(spacing: 12) {
            if current {
                StatusDot(color: Theme.statusColor(client.status, error: error != nil))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.name)
                    .font(Theme.mono(17, .semibold))
                    .foregroundStyle(Theme.paper)
                    .lineLimit(1)
                Text("\(profile.address) · \(profile.lastConnected.map(L.ago) ?? L.neverConnected)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if let error, client.status != .connected {
                    Text(error)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.vermilion)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted.opacity(0.6))
        }
        .padding(.vertical, 6)
    }

    private func nearbyRow(_ host: DiscoveredHost) -> some View {
        let saved = store.profiles.first { $0.matches(host: host.host, port: host.port) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(host.name)
                    .font(Theme.mono(15, .semibold))
                    .foregroundStyle(Theme.paper)
                    .lineLimit(1)
                Text(host.address)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button {
                if let saved { open(saved) } else { sheet = .pairNearby(host) }
            } label: {
                Text(saved == nil ? L.pair : L.connect)
                    .font(Theme.mono(11, .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(saved == nil ? Theme.vermilion : Theme.surface2)
                    .foregroundStyle(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Sheets & bindings

    @ViewBuilder
    private func sheetContent(_ sheet: HostSheet) -> some View {
        switch sheet {
        case .add:
            AddHostSheet(mode: .add, onSave: save)
        case .pairNearby(let host):
            AddHostSheet(mode: .nearby(host), onSave: save)
        case .edit(let id):
            if let profile = store.profile(id) {
                AddHostSheet(mode: .edit(profile), onSave: save)
            }
        case .settings:
            SettingsView()
        }
    }

    private func save(_ profile: HostProfile, connect: Bool) {
        store.upsert(profile)
        sheet = nil
        if connect { open(profile) }
    }

    private var forgetBinding: Binding<Bool> {
        Binding(get: { pendingForget != nil }, set: { if !$0 { pendingForget = nil } })
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}
