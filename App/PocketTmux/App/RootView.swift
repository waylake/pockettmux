import SwiftUI

enum Route: Hashable {
    case sessions
    case terminal
}

struct RootView: View {
    @EnvironmentObject private var client: AgentClient
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            ConnectView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .sessions: SessionListView(path: $path)
                    case .terminal: TerminalScreen()
                    }
                }
        }
        .tint(Theme.vermilion)
        .preferredColorScheme(.dark)
    }
}
