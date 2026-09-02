import SwiftUI

@main
struct PocketTmuxApp: App {
    @StateObject private var client = AgentClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
        }
    }
}
