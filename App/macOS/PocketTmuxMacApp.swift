import AppKit
import PocketTmuxAgent
import SwiftUI

@main
struct PocketTmuxMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var controller = AgentController.shared

    init() {
        MacSettings.registerDefaults()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(controller: controller)
        } label: {
            MenuBarLabel(isRunning: controller.isRunning, attached: controller.attachedClients > 0,
                         hasError: controller.errorText != nil)
        }
        .menuBarExtraStyle(.window)

        Window("Pair iPhone", id: WindowID.pair) {
            PairingView(controller: controller)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Log", id: WindowID.log) {
            LogView(controller: controller)
        }
        .defaultSize(width: 640, height: 420)
        .defaultPosition(.center)

        Settings {
            SettingsView(controller: controller)
        }
    }
}

enum WindowID {
    static let pair = "pair"
    static let log = "log"
}

/// `terminal` stopped · `terminal.fill` running · plus a phone while attached.
private struct MenuBarLabel: View {
    let isRunning: Bool
    let attached: Bool
    let hasError: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isRunning ? "terminal.fill" : "terminal")
            if attached {
                Image(systemName: "iphone.gen3")
            } else if hasError {
                Image(systemName: "exclamationmark")
            }
        }
    }
}

/// Launch (auto-start), URL opens (ignored on the Mac) and a clean stop on quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if MacSettings.autoStart {
            AgentController.shared.start()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // pockettmux://pair?… is for the iPhone; the Mac is the host.
        for url in urls {
            AgentController.shared.log.info("ignored \(url.scheme ?? "")://\(url.host ?? "") link — open it on the iPhone")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AgentController.shared.stop()
        return .terminateNow
    }
}
