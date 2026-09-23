import SwiftUI
import PocketTmuxKit

/// Terminal. Navigation, status, window/pane selection, and actions use the
/// standard navigation bar and toolbar; SwiftTerm remains the intentionally
/// custom terminal content surface.
struct TerminalScreen: View {
    @EnvironmentObject private var client: AgentClient
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.fontSize) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.keepAwake) private var keepAwake = true

    private let sessionID: String?
    @State private var coordinator: TerminalCoordinator?
    @State private var appeared = false
    @State private var renamingWindow: WindowInfo?
    @State private var renameText = ""
    @State private var pendingKill: WindowInfo?
    @State private var showInvalidName = false
    @State private var leaving = false

    init(sessionID: String? = nil) {
        self.sessionID = sessionID
    }

    var body: some View {
        TerminalHost(pendingScreen: client.pendingScreen,
                     fontSize: fontSize,
                     coordinator: $coordinator)
            .navigationTitle(client.attached?.session.name ?? L.sessions)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        StatusIndicator(state: client.status)
                        Text(client.attached?.session.name ?? L.sessions)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    TmuxMenu(windows: client.attached?.windows ?? [],
                             panes: client.attached?.activePanes ?? [],
                             onSelectWindow: { client.selectWindow(id: $0.id) },
                             onSelectPane: { client.selectPane(id: $0.id) },
                             onCreateWindow: client.createWindow)

                    Button(action: pasteClipboard) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .accessibilityLabel(L.paste)

                    Menu {
                        if let window = client.attached?.activeWindow {
                            Button { renameText = window.name; renamingWindow = window } label: {
                                Label(L.renameWindow, systemImage: "pencil")
                            }
                            Button(role: .destructive) { pendingKill = window } label: {
                                Label(L.killWindow, systemImage: "xmark.rectangle")
                            }
                        }
                        Divider()
                        Button(action: dismissKeyboard) {
                            Label(L.hideKeyboard, systemImage: "keyboard.chevron.compact.down")
                        }
                        Button { fontSize = max(AppSettings.fontRange.lowerBound, fontSize - 1) } label: {
                            Label(L.fontSmaller, systemImage: "textformat.size.smaller")
                        }
                        Button { fontSize = min(AppSettings.fontRange.upperBound, fontSize + 1) } label: {
                            Label(L.fontLarger, systemImage: "textformat.size.larger")
                        }
                        Divider()
                        Button(role: .destructive, action: leave) {
                            Label(L.detach, systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(L.more)
                }
            }
            .overlay(alignment: .top) { banner }
            .onAppear(perform: appearOnce)
            .onDisappear {
                // Every way off this screen ends the attach, so the next visit
                // always gets a fresh `screen(.reset)` from the agent.
                UIApplication.shared.isIdleTimerDisabled = false
                client.detach()
            }
            .onChange(of: keepAwake) { UIApplication.shared.isIdleTimerDisabled = $0 }
            .onChange(of: client.detachEvent) { event in
                guard let event, !event.retrying, event.reason != .requested else { return }
                popSoon()
            }
            .alert(L.renameWindow, isPresented: renameBinding, presenting: renamingWindow) { window in
                TextField(window.name, text: $renameText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(L.rename) { rename(window, to: renameText) }
                Button(L.cancel, role: .cancel) { renamingWindow = nil }
            } message: { _ in
                Text(L.renameWindow)
            }
            .alert(L.invalidName, isPresented: $showInvalidName) {
                Button(L.done, role: .cancel) {}
            }
            .confirmationDialog(L.killWindowTitle(pendingKill.map { "\($0.index):\($0.name)" } ?? ""),
                                isPresented: killBinding, titleVisibility: .visible) {
                Button(L.killWindow, role: .destructive) {
                    if let window = pendingKill { client.killWindow(id: window.id) }
                    pendingKill = nil
                }
                Button(L.cancel, role: .cancel) { pendingKill = nil }
            } message: {
                Text(L.killWindowBody)
            }
    }

    @ViewBuilder
    private var banner: some View {
        if let message = client.banner {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 8)
                .transition(.opacity)
        }
    }

    private func appearOnce() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake
        guard !appeared else { return }
        appeared = true
        if let sessionID {
            client.attach(sessionID: sessionID)
        } else if let id = client.attached?.session.id {
            client.attach(sessionID: id)
        }
    }

    private func leave() {
        guard !leaving else { return }
        leaving = true
        dismiss()
    }

    private func popSoon() {
        guard !leaving else { return }
        leaving = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        }
    }

    private func pasteClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        client.paste(text)
    }

    private func rename(_ window: WindowInfo, to name: String) {
        renamingWindow = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard TmuxNames.isValidName(trimmed) else { showInvalidName = true; return }
        client.renameWindow(id: window.id, name: trimmed)
    }

    private func dismissKeyboard() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .endEditing(true)
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renamingWindow != nil }, set: { if !$0 { renamingWindow = nil } })
    }

    private var killBinding: Binding<Bool> {
        Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } })
    }
}
