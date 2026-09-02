import SwiftUI

@main
struct PocketTmuxApp: App {
    @StateObject private var client = AgentClient()
    @StateObject private var store = ProfileStore()

    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
                .environmentObject(store)
        }
    }
}
