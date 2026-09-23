import SwiftUI
import PocketTmuxKit

/// Native toolbar menu for the tmux hierarchy. Windows and panes are separate
/// submenus: a pane is a full-screen phone view, not another window tab.
struct TmuxMenu: View {
    let windows: [WindowInfo]
    let panes: [PaneInfo]
    let onSelectWindow: (WindowInfo) -> Void
    let onSelectPane: (PaneInfo) -> Void
    let onCreateWindow: () -> Void

    private var activeWindow: WindowInfo? { windows.first(where: \.active) }
    private var activePane: PaneInfo? { panes.first(where: \.active) }
    private var hasSplit: Bool { panes.count > 1 }

    var body: some View {
        Menu {
            Menu {
                if windows.isEmpty {
                    Text(L.noWindows)
                } else {
                    ForEach(windows) { window in
                        Button { onSelectWindow(window) } label: {
                            if window.active {
                                Label(windowLabel(window), systemImage: "checkmark")
                            } else {
                                Text(windowLabel(window))
                            }
                        }
                    }
                }
                Divider()
                Button(L.newWindow, systemImage: "plus", action: onCreateWindow)
            } label: {
                Label(L.windowsMenu, systemImage: "macwindow")
            }

            if hasSplit {
                Menu {
                    ForEach(panes) { pane in
                        Button { onSelectPane(pane) } label: {
                            if pane.active {
                                Label(paneLabel(pane), systemImage: "checkmark")
                            } else {
                                Text(paneLabel(pane))
                            }
                        }
                    }
                } label: {
                    Label(L.panesMenu, systemImage: "rectangle.split.2x1")
                }
            }
        } label: {
            Image(systemName: hasSplit ? "rectangle.split.2x1" : "macwindow")
        }
        .disabled(windows.isEmpty)
        .accessibilityLabel(L.sessionLayout)
        .accessibilityValue(accessibilityValue)
    }

    private func windowLabel(_ window: WindowInfo) -> String {
        "\(window.index): \(window.name)"
    }

    private func paneLabel(_ pane: PaneInfo) -> String {
        let title = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "\(L.pane) \(pane.index)" : "\(L.pane) \(pane.index) — \(title)"
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if let activeWindow {
            values.append("\(L.window) \(activeWindow.index), \(activeWindow.name)")
        } else {
            values.append(L.noWindows)
        }
        if let activePane { values.append("\(L.pane) \(activePane.index)") }
        return values.joined(separator: ", ")
    }
}
