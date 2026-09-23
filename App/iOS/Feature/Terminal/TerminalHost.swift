import SwiftUI
import SwiftTerm

/// SwiftTerm embedded in SwiftUI. The terminal surface follows the system
/// appearance; ANSI colors emitted by the program still render normally.
struct TerminalHost: UIViewRepresentable {
    @EnvironmentObject private var client: AgentClient
    let pendingScreen: Data?
    let fontSize: Int
    @Binding var coordinator: TerminalCoordinator?

    func makeCoordinator() -> TerminalCoordinator {
        TerminalCoordinator(client: client)
    }

    func makeUIView(context: Context) -> TerminalView {
        var options = TerminalOptions()
        options.scrollback = 5000
        let terminal = TerminalView(frame: .zero, options: options)
        terminal.backgroundColor = .systemBackground
        terminal.nativeBackgroundColor = .systemBackground
        terminal.nativeForegroundColor = .label
        terminal.caretColor = .systemGreen
        terminal.font = .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        terminal.selectedTextBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.35)
        terminal.optionAsMetaKey = false
        terminal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        terminal.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminal
        coordinator = context.coordinator

        // Swipe-to-scroll inside TUIs (see TerminalCoordinator.scrollDrag).
        // The coordinator's delegate methods gate it to the alternate screen and
        // make every other pan on the view (scrollback, SwiftTerm's mouse drag)
        // wait for it to fail.
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(TerminalCoordinator.scrollDrag(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        terminal.addGestureRecognizer(pan)
        return terminal
    }

    func updateUIView(_ terminal: TerminalView, context: Context) {
        if terminal.font.pointSize != CGFloat(fontSize) {
            terminal.font = .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        }
        context.coordinator.feed(pendingScreen)
    }
}
