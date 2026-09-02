import SwiftUI
import SwiftTerm

/// SwiftTerm embedded in SwiftUI. Screen frames are fed from `updateUIView`
/// (which SwiftUI calls whenever `pendingScreen` changes) — this is more
/// reliable than observing `@Published` from the parent, which could drop the
/// first frames while the coordinator binding isn't set yet.
struct TerminalHost: UIViewRepresentable {
    @EnvironmentObject private var client: AgentClient
    let pendingScreen: Data?
    @Binding var coordinator: TerminalCoordinator?

    func makeCoordinator() -> TerminalCoordinator {
        TerminalCoordinator(client: client)
    }

    func makeUIView(context: Context) -> TerminalView {
        var options = TerminalOptions()
        options.scrollback = 5000   // drag up to scroll through received history
        let tv = TerminalView(frame: .zero, options: options)
        tv.backgroundColor = UIColor(Theme.bg)
        tv.nativeBackgroundColor = UIColor(Theme.bg)
        tv.nativeForegroundColor = UIColor(Theme.paper)
        tv.caretColor = UIColor(Theme.moegi)
        tv.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.selectedTextBackgroundColor = UIColor(Theme.indigo).withAlphaComponent(0.45)
        tv.optionAsMetaKey = false
        tv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tv.terminalDelegate = context.coordinator
        context.coordinator.terminalView = tv
        coordinator = context.coordinator
        // Swipe-to-scroll inside TUIs (see TerminalCoordinator.scrollDrag).
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(TerminalCoordinator.scrollDrag(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        tv.addGestureRecognizer(pan)
        tv.panGestureRecognizer.require(toFail: pan)
        return tv
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.feed(pendingScreen)
    }
}
