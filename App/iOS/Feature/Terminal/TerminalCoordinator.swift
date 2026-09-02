import SwiftUI
import SwiftTerm

/// Bridges the SwiftTerm engine to `AgentClient`.
@MainActor
final class TerminalCoordinator: NSObject, @MainActor TerminalViewDelegate, UIGestureRecognizerDelegate {
    let client: AgentClient
    weak var terminalView: TerminalView?
    /// Last frame fed; `updateUIView` can re-fire with the same bytes on any
    /// parent re-render, so dedupe to avoid double-rendering.
    private var lastFed: Data?
    /// Vertical drag tracking for translating swipe → scroll events.
    private var dragAccum: CGFloat = 0
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    init(client: AgentClient) { self.client = client }

    // MARK: - Swipe-to-scroll in TUIs

    /// A vertical drag over the terminal is translated into scroll events for
    /// the *app* — full-screen TUIs (pi, Claude Code, less, vim) render into the
    /// alternate screen, where the emulator's scrollback is empty by definition,
    /// so their history can only be reached by asking them to scroll. Direction
    /// follows iOS: dragging **down** pulls older content into view (wheel up).
    /// Gated to the alternate screen by `gestureRecognizerShouldBegin`; on the
    /// normal screen this pan fails and SwiftTerm's own scrollback pan runs.
    @MainActor @objc func scrollDrag(_ g: UIPanGestureRecognizer) {
        guard let tv = terminalView else { return }
        switch g.state {
        case .began:
            dragAccum = 0
        case .changed:
            let dy = g.translation(in: g.view).y
            dragAccum += dy
            // Read the drag as an incremental delta so the accumulator below
            // carries the sub-notch remainder — the same accumulator pattern as
            // MacTerminalView.scrollWheel. (The old code subtracted notches from
            // the *total* translation, double-counting and inflating wheel events.)
            g.setTranslation(.zero, in: g.view)
            let step: CGFloat = 18
            let notches = Int(dragAccum / step)
            if notches != 0 {
                dragAccum -= CGFloat(notches) * step
                sendScroll(notches: notches, at: g.location(in: tv))
            }
        default:
            dragAccum = 0
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    /// Only the alternate screen (full-screen TUI) has no native scrollback to
    /// scroll, so that's the only case this gesture should steal the drag — the
    /// iOS mirror of MacTerminalView.scrollWheel, which forwards the wheel to
    /// the app on the alternate screen and scrolls the buffer otherwise. This
    /// is consulted before recognition, so on the normal screen this pan fails
    /// immediately and the UIScrollView's native scrollback pan proceeds.
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let tv = terminalView, g !== tv.panGestureRecognizer else { return false }
        let term = tv.getTerminal()
        print("CLIENT: swipe shouldBegin alt=\(term.isCurrentBufferAlternate) mouse=\(term.mouseMode)")
        return term.isCurrentBufferAlternate
    }

    /// Every other pan on the terminal view waits for this one to fail. That
    /// covers the UIScrollView's scrollback pan *and* the mouse-drag pan that
    /// SwiftTerm adds as soon as the app enables mouse reporting — without this
    /// the two pans race in undefined order, and when SwiftTerm's wins the TUI
    /// receives a click-drag (press/motion/release) instead of wheel events:
    /// the finger "drags" but nothing scrolls. On the normal screen this pan
    /// fails in `gestureRecognizerShouldBegin`, so the others proceed untouched.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer
    }

    /// One "notch" of scroll. Positive = toward older content (wheel up).
    ///
    /// Two wire formats, picked the way xterm does it:
    ///  - the app reads the mouse → SGR wheel (`ESC[<64/65;col;rowM`). pi
    ///    (`tuiMode: "fullscreen"`) and Claude Code parse these and scroll their
    ///    own transcript.
    ///  - the app does *not* read the mouse (less, man, htop, vim) → cursor
    ///    up/down keys, which is xterm's `alternateScroll` (DECSET 1007)
    ///    behaviour and the only thing those apps respond to.
    ///
    /// `mouseMode` is trustworthy now: the agent primes the emulator with the
    /// pane's real mouse/alt-screen/cursor-key state on attach, because tmux
    /// control mode never replays the escapes that predate the control client.
    @MainActor private func sendScroll(notches: Int, at point: CGPoint) {
        guard let tv = terminalView else { return }
        let term = tv.getTerminal()
        let up = notches > 0
        var one: [UInt8]
        if term.mouseMode != .off {
            let cols = max(term.cols, 1), rows = max(term.rows, 1)
            let col = min(max(1, Int(point.x / max(tv.bounds.width, 1) * CGFloat(cols)) + 1), cols)
            let row = min(max(1, Int(point.y / max(tv.bounds.height, 1) * CGFloat(rows)) + 1), rows)
            one = Array("\u{1b}[<\(up ? 64 : 65);\(col);\(row)M".utf8)   // wheel: press only, no release
        } else {
            one = Array((term.applicationCursor
                         ? (up ? "\u{1b}OA" : "\u{1b}OB")
                         : (up ? "\u{1b}[A" : "\u{1b}[B")).utf8)
        }
        var bytes = [UInt8]()
        for _ in 0..<abs(notches) { bytes += one }
        print("CLIENT: swipe \(up ? "up" : "down") x\(abs(notches)) \(term.mouseMode == .off ? "keys" : "wheel")")
        client.sendInput(bytes)
    }

    @MainActor
    func feed(_ data: Data?) {
        guard let data, !data.isEmpty, data != lastFed, let tv = terminalView else { return }
        lastFed = data
        print("CLIENT: feed \(data.count)B")
        // Go through the view, not `getTerminal().feed`: SwiftTerm 1.20 only
        // queues a display update in `TerminalView.feed` (feedPrepare/Finish),
        // so bytes fed straight into the engine sit invisible until the next
        // unrelated redraw (a scroll, a rotation).
        tv.feed(byteArray: ArraySlice(data))
    }

    // MARK: - TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        let client = self.client
        Task { @MainActor in client.resize(cols: newCols, rows: newRows) }
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let client = self.client
        let bytes = Array(data)
        Task { @MainActor in client.sendInput(bytes) }
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        let client = self.client
        Task { @MainActor in client.terminalTitle = title }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {
        if UserDefaults.standard.bool(forKey: AppSettings.haptics) { haptic.impactOccurred() }
    }
    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.string = String(data: content, encoding: .utf8)
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
