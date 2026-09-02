import AppKit
import PocketTmuxAgent
import PocketTmuxKit
import SwiftUI

/// Settings scene: General / Network / Security / Advanced / About.
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
                Toggle("Launch at login", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                ))
                if let error = controller.launchAtLoginError {
                    Text(error).font(MacTheme.mono(11)).foregroundStyle(MacTheme.shu)
                }
                Toggle("Start agent when the app launches", isOn: $autoStart)
            }
            Section {
                Toggle("Keep Mac awake while an iPhone is attached", isOn: $keepAwake)
                    .onChange(of: keepAwake) { controller.restartIfRunning() }
                Toggle("Advertise on the local network (Bonjour)", isOn: $bonjour)
                    .onChange(of: bonjour) { controller.restartIfRunning() }
            }
            Section {
                TextField("Name shown on iPhone", text: $draftName, prompt: Text(HostInfo.computerName))
                    .font(MacTheme.mono(12))
                    .onSubmit(commitName)
                Text("Leave empty to use this Mac's name.")
                    .font(MacTheme.mono(11))
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
                HStack {
                    TextField("Port", text: $draftPort)
                        .font(MacTheme.mono(12))
                        .onSubmit(applyPort)
                    Button("Apply", action: applyPort)
                        .disabled(Int(draftPort) == port)
                }
                Text(portNote ?? "1024–65535, default \(WireProtocol.defaultPort). Applying restarts the agent.")
                    .font(MacTheme.mono(11))
                    .foregroundStyle(portNote == nil ? Color.secondary : MacTheme.shu)
            }
            Section("Addresses") {
                if controller.addresses.isEmpty {
                    Text("No network interface is up")
                        .font(MacTheme.mono(12))
                        .foregroundStyle(.secondary)
                }
                ForEach(controller.addresses) { address in
                    HStack {
                        Text(address.ip).font(MacTheme.mono(12))
                        Spacer()
                        Text(address.label).font(MacTheme.mono(11)).foregroundStyle(.secondary)
                    }
                }
                Text(verbatim: "ws://<address>:\(port)\(WireProtocol.path)")
                    .font(MacTheme.mono(11))
                    .foregroundStyle(.secondary)
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
                HStack(spacing: 8) {
                    Text(reveal ? controller.token : Format.masked(controller.token))
                        .font(MacTheme.mono(12))
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Spacer()
                    Button(reveal ? "Hide" : "Reveal") { reveal.toggle() }
                    CopyButton(id: "token", text: controller.token, copied: $copied)
                }
                Button("Regenerate token…") { confirmRegenerate = true }
                    .confirmationDialog("Regenerate the pairing token?", isPresented: $confirmRegenerate) {
                        Button("Regenerate", role: .destructive) { controller.regenerateToken() }
                    } message: {
                        Text("Every paired iPhone will have to pair again.")
                    }
            }
            Section {
                Text("Anyone on your network with this token can use your tmux sessions. Keep it private.")
                    .font(MacTheme.mono(11))
                    .foregroundStyle(.secondary)
                Text("Stored in \(TokenStore.fileURL.path) (shared with pockettmuxd).")
                    .font(MacTheme.mono(11))
                    .foregroundStyle(.secondary)
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
                    Text(controller.autoDetectedTmuxPath ?? "not found").font(MacTheme.mono(12))
                }
                LabeledContent("Version") {
                    Text(controller.tmuxVersion).font(MacTheme.mono(12))
                }
                HStack {
                    TextField("Override path", text: $draftPath, prompt: Text("auto-detect"))
                        .font(MacTheme.mono(12))
                        .onSubmit(commitPath)
                    Button("Browse…", action: browse)
                }
                if !draftPath.isEmpty, TmuxLocator.resolve(override: draftPath) == nil {
                    Text("Not an executable file.")
                        .font(MacTheme.mono(11))
                        .foregroundStyle(MacTheme.shu)
                }
            }
            Section("Log") {
                Button("Open log") {
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
                LabeledContent("PocketTmux for Mac") { Text(version).font(MacTheme.mono(12)) }
                LabeledContent("Agent") { Text(AgentInfo.version).font(MacTheme.mono(12)) }
                LabeledContent("Protocol") { Text("v\(WireProtocol.version)").font(MacTheme.mono(12)) }
            }
            Section {
                Link("GitHub — waylake/pockettmux", destination: URL(string: "https://github.com/waylake/pockettmux")!)
                Text("MIT License")
                    .font(MacTheme.mono(11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
