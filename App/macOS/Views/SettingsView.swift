import AppKit
import PocketTmuxAgent
import PocketTmuxKit
import SwiftUI

/// Standard macOS Settings scene. Categories use the system tab style and all
/// values use native Form controls.
struct SettingsView: View {
    @ObservedObject var controller: AgentController

    var body: some View {
        TabView {
            GeneralTab(controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
            NetworkTab(controller: controller)
                .tabItem { Label("Network", systemImage: "network") }
            SecurityTab(controller: controller)
                .tabItem { Label("Security", systemImage: "key") }
            AdvancedTab(controller: controller)
                .tabItem { Label("Advanced", systemImage: "terminal") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var controller: AgentController
    @AppStorage(MacSettings.Key.autoStart) private var autoStart = true
    @AppStorage(MacSettings.Key.keepAwake) private var keepAwake = true
    @AppStorage(MacSettings.Key.bonjour) private var bonjour = true
    @AppStorage(MacSettings.Key.hostName) private var hostName = ""
    @State private var draftName = ""

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                ))
                if let error = controller.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                Toggle("Start Agent When the App Launches", isOn: $autoStart)
            }

            Section {
                Toggle("Keep Mac Awake While an iPhone Is Attached", isOn: $keepAwake)
                    .onChange(of: keepAwake) { controller.restartIfRunning() }
                Toggle("Advertise on the Local Network (Bonjour)", isOn: $bonjour)
                    .onChange(of: bonjour) { controller.restartIfRunning() }
            }

            Section {
                TextField("Name Shown on iPhone", text: $draftName, prompt: Text(HostInfo.computerName))
                    .onSubmit(commitName)
                Text("Leave empty to use this Mac's name.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { draftName = hostName }
        .onDisappear(perform: commitName)
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard trimmed != hostName else { return }
        hostName = trimmed
        controller.restartIfRunning()
    }
}

// MARK: - Network

private struct NetworkTab: View {
    @ObservedObject var controller: AgentController
    @AppStorage(MacSettings.Key.port) private var port = Int(WireProtocol.defaultPort)
    @State private var draftPort = ""
    @State private var portNote: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Port") {
                    HStack {
                        TextField("Port", text: $draftPort)
                            .onSubmit(applyPort)
                        Button("Apply", action: applyPort)
                            .disabled(Int(draftPort) == port)
                    }
                }
                Text(portNote ?? "1024–65535, default \(WireProtocol.defaultPort). Applying restarts the agent.")
                    .foregroundStyle(portNote == nil ? Color.secondary : Color.red)
            }

            Section("Addresses") {
                if controller.addresses.isEmpty {
                    Label("No Network Interface Is Up", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.addresses) { address in
                        LabeledContent(address.label) {
                            Text(address.ip)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                Text(verbatim: "ws://<address>:\(port)\(WireProtocol.path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            draftPort = String(port)
            controller.refreshAddresses()
        }
    }

    private func applyPort() {
        guard let value = Int(draftPort.trimmingCharacters(in: .whitespaces)),
              MacSettings.portRange.contains(value) else {
            portNote = "Enter a port between 1024 and 65535."
            return
        }
        portNote = nil
        guard value != port else { return }
        port = value
        controller.restartIfRunning()
    }
}

// MARK: - Security

private struct SecurityTab: View {
    @ObservedObject var controller: AgentController
    @State private var reveal = false
    @State private var copied: String?
    @State private var confirmRegenerate = false

    var body: some View {
        Form {
            Section("Token") {
                LabeledContent("Pairing Token") {
                    HStack(spacing: 8) {
                        Text(reveal ? controller.token : Format.masked(controller.token))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                        Button(reveal ? "Hide" : "Reveal") { reveal.toggle() }
                        CopyButton(id: "token", text: controller.token, copied: $copied)
                    }
                }
                Button("Regenerate Token…", role: .destructive) { confirmRegenerate = true }
                    .confirmationDialog("Regenerate the pairing token?", isPresented: $confirmRegenerate) {
                        Button("Regenerate", role: .destructive) { controller.regenerateToken() }
                    } message: {
                        Text("Every paired iPhone will have to pair again.")
                    }
            }

            Section {
                Label("Anyone on your network with this token can use your tmux sessions. Keep it private.",
                      systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                Text("Stored in \(TokenStore.fileURL.path) (shared with pockettmuxd).")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {
    @ObservedObject var controller: AgentController
    @AppStorage(MacSettings.Key.tmuxPath) private var tmuxPath = ""
    @Environment(\.openWindow) private var openWindow
    @State private var draftPath = ""

    var body: some View {
        Form {
            Section("tmux") {
                LabeledContent("Detected") {
                    Text(controller.autoDetectedTmuxPath ?? "Not Found")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Version") {
                    Text(controller.tmuxVersion)
                        .font(.body.monospaced())
                }
                LabeledContent("Override Path") {
                    HStack {
                        TextField("Override path", text: $draftPath, prompt: Text("Auto-detect"))
                            .onSubmit(commitPath)
                        Button("Browse…", action: browse)
                    }
                }
                if !draftPath.isEmpty, TmuxLocator.resolve(override: draftPath) == nil {
                    Label("Not an executable file.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section("Log") {
                Button("Open Agent Log", systemImage: "doc.text.magnifyingglass") {
                    openWindow(id: WindowID.log)
                    NSApp.activate()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { draftPath = tmuxPath }
        .onDisappear(perform: commitPath)
    }

    private func commitPath() {
        let trimmed = draftPath.trimmingCharacters(in: .whitespaces)
        guard trimmed != tmuxPath else { return }
        tmuxPath = trimmed
        controller.restartIfRunning()
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        panel.message = "Choose the tmux binary"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draftPath = url.path
        commitPath()
    }
}

// MARK: - About

private struct AboutTab: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AgentInfo.version
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("PocketTmux for Mac", value: version)
                LabeledContent("Agent", value: AgentInfo.version)
                LabeledContent("Protocol", value: "v\(WireProtocol.version)")
            }
            Section {
                Link("GitHub — waylake/pockettmux",
                     destination: URL(string: "https://github.com/waylake/pockettmux")!)
                Label("MIT License", systemImage: "doc.text")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
