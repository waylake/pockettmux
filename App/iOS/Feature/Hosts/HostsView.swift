import SwiftUI

/// Macs — saved profiles and Macs found via Bonjour. Uses standard list rows,
/// navigation links, sheets, toolbars, swipe actions, and context menus.
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
        Group {
            if store.profiles.isEmpty, bonjour.hosts.isEmpty {
                onboarding
            } else {
                hostList
            }
        }
        .navigationTitle(L.macs)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { sheet = .add } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L.addMac)
                Button { sheet = .settings } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(L.settings)
            }
        }
        .sheet(item: $sheet, content: sheetContent)
        .confirmationDialog(L.forgetTitle(pendingForget?.name ?? ""), isPresented: forgetBinding,
                            titleVisibility: .visible) {
            Button(L.forget, role: .destructive) {
                if let profile = pendingForget {
                    if client.profileID == profile.id { client.disconnect() }
                    store.remove(profile.id)
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
                var profile = profile
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { profile.name = name; store.upsert(profile) }
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

    private var hostList: some View {
        List {
            if !store.profiles.isEmpty {
                savedSection
            }
            if !bonjour.hosts.isEmpty {
                nearbySection
            }
        }
    }

    private var savedSection: some View {
        Section(L.savedMacs) {
            ForEach(store.profiles) { profile in
                NavigationLink(value: Route.sessions(profile.id)) {
                    profileRow(profile)
                }
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
        }
    }

    private var nearbySection: some View {
        Section {
            ForEach(bonjour.hosts) { host in
                if let saved = store.profiles.first(where: { $0.matches(host: host.host, port: host.port) }) {
                    NavigationLink(value: Route.sessions(saved.id)) {
                        nearbyLabel(host)
                    }
                } else {
                    HStack(spacing: 12) {
                        nearbyLabel(host)
                        Spacer()
                        Button(L.pair, systemImage: "qrcode.viewfinder") {
                            sheet = .pairNearby(host)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        } header: {
            Text(L.nearbyMacs)
        } footer: {
            Text(L.tailscaleNote)
        }
    }

    @ViewBuilder
    private var onboarding: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(L.onboardingTitle, systemImage: "desktopcomputer")
            } description: {
                Text(L.onboardingDescription)
            } actions: {
                Button(L.scanQR, systemImage: "qrcode.viewfinder") { sheet = .add }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(L.onboardingTitle)
                    .font(.headline)
                Text(L.onboardingDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(L.scanQR, systemImage: "qrcode.viewfinder") { sheet = .add }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    // MARK: - Rows

    private func profileRow(_ profile: HostProfile) -> some View {
        let current = client.profileID == profile.id && client.status != .idle
        let error = client.profileID == profile.id ? client.lastError : nil
        return HStack(spacing: 12) {
            if current {
                StatusIndicator(state: client.status, error: error != nil)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(profile.address) · \(profile.lastConnected.map(L.ago) ?? L.neverConnected)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let error, client.status != .connected {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func nearbyLabel(_ host: DiscoveredHost) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(host.name)
                .font(.headline)
                .lineLimit(1)
            Text(host.address)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
