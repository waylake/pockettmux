import SwiftUI
import PocketTmuxKit

/// Sheets presented over Macs. Owned here so a deep link can dismiss them.
enum HostSheet: Identifiable, Hashable {
    case add
    case pairNearby(DiscoveredHost)
    case edit(HostProfile.ID)
    case settings

    var id: String {
        switch self {
        case .add: return "add"
        case .pairNearby(let h): return "pair:\(h.id)"
        case .edit(let id): return "edit:\(id)"
        case .settings: return "settings"
        }
    }
}

/// Navigation root: Macs → Sessions → Terminal. Owns the connect → push flow
/// so a row tap, a deep link and auto-resume all land on Sessions the same way.
struct RootView: View {
    @EnvironmentObject private var client: AgentClient
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []
    @State private var sheet: HostSheet?
    /// Profile we are connecting to on behalf of the user; when it reports
    /// `.connected`, push Sessions. Cleared on `.idle` so a failed connect
    /// never pushes later.
    @State private var pendingProfileID: HostProfile.ID?
    @State private var didAutoResume = false
    #if DEBUG
    /// `-pt.autoAttach <session name>` launch argument: after the first
    /// session list arrives, attach to that session and push the Terminal.
    /// Lets a headless simulator run screenshot the Terminal screen; Debug only.
    private static let autoAttachName = UserDefaults.standard.string(forKey: "pt.autoAttach")
    @State private var didAutoAttach = false
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            HostsView(sheet: $sheet, open: open)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .sessions(let id): SessionListView(profileID: id, path: $path)
                    case .terminal: TerminalScreen()
                    }
                }
        }
        .tint(Theme.vermilion)
        .preferredColorScheme(.dark)
        .onAppear(perform: autoResume)
        .onOpenURL(perform: pair)
        .onChange(of: client.status) { status in
            switch status {
            case .connected:
                guard let id = client.profileID else { return }
                store.markConnected(id)
                if pendingProfileID == id {
                    pendingProfileID = nil
                    if path.isEmpty { path = [.sessions(id)] }
                }
            case .idle:
                pendingProfileID = nil
            case .connecting, .reconnecting:
                break
            }
        }
        .onChange(of: client.attached?.session.id) { sessionID in
            if let sessionID, let id = client.profileID { store.setLastSession(id, sessionID: sessionID) }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { client.resumeIfNeeded() }
        }
        #if DEBUG
        .onChange(of: client.sessions, perform: autoAttach)
        #endif
    }

    /// Connect and push Sessions once the agent answers. Already connected to
    /// this Mac → push right away.
    private func open(_ profile: HostProfile) {
        client.connect(profile: profile)
        if client.status == .connected, client.profileID == profile.id {
            if path.isEmpty { path = [.sessions(profile.id)] }
        } else {
            pendingProfileID = profile.id
        }
    }

    /// Mirror of the old `didAutoConnect`: one Mac (or a last-used one) opens
    /// by itself, but Macs stays one back-swipe away.
    private func autoResume() {
        guard !didAutoResume else { return }
        didAutoResume = true
        if let profile = store.autoResumeCandidate { open(profile) }
    }

    /// `pockettmux://pair?...` from the QR, a link, or the Mac app.
    private func pair(_ url: URL) {
        guard let payload = PairingPayload(url: url) else { return }
        sheet = nil
        path = []
        open(store.pair(payload))
    }

    #if DEBUG
    private func autoAttach(_ sessions: [SessionInfo]) {
        guard let name = Self.autoAttachName, !didAutoAttach, path.count == 1,
              let session = sessions.first(where: { $0.name == name }) else { return }
        didAutoAttach = true
        client.attach(sessionID: session.id)
        path.append(.terminal)
    }
    #endif
}
