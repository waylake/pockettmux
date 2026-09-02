import SwiftUI
import PocketTmuxKit

/// Screen 3 — Terminal. Thin status bar, window strip, then the live pane.
/// The accessory keyboard (Esc/Ctrl/arrows/F-keys) ships with SwiftTerm — that
/// is what makes LLM prompts (option menus, mode toggles) usable from the phone.
struct TerminalScreen: View {
    @EnvironmentObject private var client: AgentClient
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.fontSize) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.keepAwake) private var keepAwake = true
    @State private var coordinator: TerminalCoordinator?
    @State private var appeared = false
    @State private var renamingWindow: WindowInfo?
    @State private var renameText = ""
    @State private var pendingKill: WindowInfo?
    @State private var showInvalidName = false
    @State private var leaving = false

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            WindowStrip(windows: client.attached?.windows ?? [],
                        onSelect: { client.selectWindow(id: $0.id) },
                        onCreate: client.createWindow,
                        onRename: { renameText = $0.name; renamingWindow = $0 },
                        onKill: { pendingKill = $0 })
            TerminalHost(pendingScreen: client.pendingScreen, fontSize: fontSize, coordinator: $coordinator)
                .background(Theme.bg)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { banner }
        .onAppear(perform: appearOnce)
        .onDisappear {
            // Every way off this screen (chevron, menu, session killed, a deep
            // link resetting the stack) ends the attach, so the next visit
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
                if let w = pendingKill { client.killWindow(id: w.id) }
                pendingKill = nil
            }
            Button(L.cancel, role: .cancel) { pendingKill = nil }
        } message: {
            Text(L.killWindowBody)
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            Button(action: leave) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.paper)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            StatusDot(color: Theme.statusColor(client.status))
            Text(client.attached?.session.name ?? "—")
                .font(Theme.mono(12, .semibold))
                .foregroundStyle(Theme.paper)
                .lineLimit(1)
            if let window = client.attached?.activeWindow {
                Text(window.name)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: dismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            Button(action: pasteClipboard) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.paste)
            Menu {
                Button(action: client.createWindow) { Label(L.newWindow, systemImage: "plus.rectangle") }
                if let window = client.attached?.activeWindow {
                    Button { renameText = window.name; renamingWindow = window } label: {
                        Label(L.renameWindow, systemImage: "pencil")
                    }
                    Button(role: .destructive) { pendingKill = window } label: {
                        Label(L.killWindow, systemImage: "xmark.rectangle")
                    }
                }
                Divider()
                Button { fontSize = max(AppSettings.fontRange.lowerBound, fontSize - 1) } label: {
                    Label(L.fontSmaller, systemImage: "textformat.size.smaller")
                }
                Button { fontSize = min(AppSettings.fontRange.upperBound, fontSize + 1) } label: {
                    Label(L.fontLarger, systemImage: "textformat.size.larger")
                }
                Divider()
                Button(role: .destructive, action: leave) { Label(L.detach, systemImage: "rectangle.portrait.and.arrow.right") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 24)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.surface)
    }

    private var banner: some View {
        Group {
            if let msg = client.banner {
                Text(msg)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.yamabuki)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                    .padding(.top, 72)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: client.banner)
    }

    // MARK: - Actions

    private func appearOnce() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake
        guard !appeared else { return }
        appeared = true
        // Re-attach on return; the client dedupes (agent repaints fully on attach).
        if let id = client.attached?.session.id { client.attach(sessionID: id) }
    }

    private func leave() {
        guard !leaving else { return }
        leaving = true
        dismiss()   // back to the session list; onDisappear detaches
    }

    /// The session is gone (killed on the Mac, or the control client died
    /// and a retry did not help): show the banner, then drop back to Sessions.
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
        // sendAction(..., to: nil) relies on the deprecated UIApplication.keyWindow,
        // which is nil in SwiftUI apps — use endEditing on the scene's key window.
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .endEditing(true)
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renamingWindow != nil }, set: { if !$0 { renamingWindow = nil } })
    }

    private var killBinding: Binding<Bool> {
        Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } })
    }
}
