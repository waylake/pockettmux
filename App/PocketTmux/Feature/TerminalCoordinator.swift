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
    /// Vertical drag tracking for translating swipe → SGR wheel events.
    private var dragAccum: CGFloat = 0

    init(client: AgentClient) { self.client = client }

    // MARK: - Swipe-to-scroll in TUIs

    /// A vertical drag over the terminal is translated into SGR mouse-wheel
    /// events (`ESC[<64/65;y;xM`) and sent to the pane — this is how TUIs
    /// (pi, Claude Code) scroll their own content, since they render into the
    /// alternate screen where the terminal scrollback is empty. Gated to the
    /// alternate screen by `gestureRecognizerShouldBegin`.
    @MainActor @objc func scrollDrag(_ g: UIPanGestureRecognizer) {
        guard let tv = terminalView else { return }
        switch g.state {
        case .began:
            dragAccum = 0
        case .changed:
            let dy = g.translation(in: g.view).y
            dragAccum += dy
            g.setTranslation(.zero, in: g.view)
            let step: CGFloat = 18
            let notches = Int(dragAccum / step)
            if notches != 0 {
                dragAccum -= CGFloat(notches) * step
                sendWheel(notches: notches, at: g.location(in: tv))
            }
        default:
            dragAccum = 0
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let tv = terminalView, g !== tv.panGestureRecognizer else { return false }
        return tv.getTerminal().isCurrentBufferAlternate
    }

    @MainActor private func sendWheel(notches: Int, at point: CGPoint) {
        guard let tv = terminalView else { return }
        let count = abs(notches)
        let btn = notches < 0 ? 64 : 65   // 64 = wheel up, 65 = wheel down
        let rows = max(tv.getTerminal().rows, 1)
        let row = min(max(1, Int(point.y / max(tv.bounds.height, 1) * CGFloat(rows))), rows)
        var bytes: [UInt8] = [0x1b, 0x5b, 0x3c]
        bytes += Array(String(btn).utf8)
        bytes += [0x3b, 0x32, 0x30, 0x3b]                  // ;20;
        bytes += Array(String(row).utf8)
        bytes += [0x4d]                                     // SGR press (wheel has no release)
        for _ in 0..<count { client.sendInput(bytes) }
    }

    @MainActor
    func feed(_ data: Data?) {
        guard let data, !data.isEmpty, data != lastFed, let tv = terminalView else { return }
        lastFed = data
        print("CLIENT: feed \(data.count)B")
        tv.getTerminal().feed(byteArray: [UInt8](data))
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
    func bell(source: TerminalView) { UIDevice.current.playInputClick() }
    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.string = String(data: content, encoding: .utf8)
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
