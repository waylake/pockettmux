import Foundation
import Darwin
import PocketTmuxKit

/// One `tmux -CC attach` control client on a real pty, speaking the
/// control-mode wire protocol. Verified against tmux 3.7c:
///   - stdin of the control client parses *commands* (not keys)
///   - keys  → `send-keys -H <hex>…` (raw bytes; prefix/vi bindings work)
///   - size  → `refresh-client -C <cols>x<rows>` (+ `resize-window`, see pin)
///   - pane output → `%output <pane> <octal-escaped payload>` frames
///
/// All state is confined to `queue` (the owning connection's serial queue);
/// every public method hops onto it.
final class TmuxControl: @unchecked Sendable {
    enum Event {
        case attached(session: SessionInfo, windows: [WindowInfo])
        case windowsChanged([WindowInfo])
        case panesChanged(sessionID: String, windowID: String, panes: [PaneInfo])
        /// A full repaint (attach / window or pane switch). Stale coalesced
        /// output must be dropped before this is sent.
        case reset([UInt8])
        case output([UInt8])
        case detached(DetachReason)
        case sessionsChanged
        case error(String)
    }

    enum State { case idle, spawning, attached }

    private(set) var state: State = .idle
    private(set) var sessionID: String?
    private(set) var activePane: String?
    private(set) var activeWindow: String?
    /// Last size the phone reported; applied to every window it looks at.
    private(set) var clientSize: (cols: Int, rows: Int)?

    var onEvent: ((Event) -> Void)?

    private let queue: DispatchQueue
    private let tmux: TmuxRunner
    private let log: AgentLog
    private let parser = TmuxControlParser()

    private var ptyFD: Int32 = -1
    private var childPID: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var readBuffer = Data()
    private var pendingInput = [UInt8]()
    private var inputTimer: DispatchSourceTimer?
    private var windowsRefresh: DispatchWorkItem?
    private var panesRefresh: DispatchWorkItem?
    /// Windows whose `window-size` we set to manual; unpinned on detach.
    private var pinnedWindows = Set<String>()
    /// A multi-pane window is zoomed while the phone views one pane. The pane
    /// is restored/unzoomed on window switch or detach; the split itself stays.
    private var phoneZoomedWindowID: String?
    private var phoneZoomedPaneID: String?
    private var detachRequested = false

    init(queue: DispatchQueue, tmux: TmuxRunner, log: AgentLog) {
        self.queue = queue
        self.tmux = tmux
        self.log = log
    }

    deinit { teardown() }

    // MARK: - Lifecycle

    func attach(sessionID: String, cols: Int?, rows: Int?) {
        queue.async { [self] in
            if state != .idle {
                teardown()
                onEvent?(.detached(.replaced))
            }
            if let cols, let rows { clientSize = (cols, rows) }
            self.sessionID = sessionID
            detachRequested = false
            spawn(sessionID: sessionID)
        }
    }

    func detach() {
        queue.async { [self] in
            guard state != .idle else { return }
            detachRequested = true
            teardown()
            onEvent?(.detached(.requested))
        }
    }

    private func spawn(sessionID: String) {
        var pty: Int32 = 0
        let pid = forkpty(&pty, nil, nil, nil)
        guard pid >= 0 else {
            log.error("forkpty failed: errno \(errno)")
            onEvent?(.error("could not start the tmux control client"))
            onEvent?(.detached(.controlExited))
            return
        }
        if pid == 0 {
            // Child: exec the control client. Only async-signal-safe calls here.
            setenv("TERM", "xterm-256color", 1)
            unsetenv("TMUX")
            unsetenv("TMUX_PANE")
            let args = [
                "tmux", "-CC", "attach-session", "-f", "active-pane,ignore-size", "-t", sessionID
            ]
            var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
            execv(tmux.path, &argv)
            _exit(127)
        }
        ptyFD = pty
        childPID = pid
        state = .spawning
        readBuffer.removeAll(keepingCapacity: true)

        let source = DispatchSource.makeReadSource(fileDescriptor: pty, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        readSource = source
        source.resume()
        startInputTimer()
        log.info("control client pid \(pid) → \(sessionID)")
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 16384)
        let n = buf.withUnsafeMutableBytes { read(ptyFD, $0.baseAddress, $0.count) }
        if n < 0 && errno == EAGAIN { return }
        guard n > 0 else { controlExited(); return }
        readBuffer.append(contentsOf: buf[0..<n])
        while let nl = readBuffer.firstIndex(of: 0x0A) {
            let line = readBuffer.subdata(in: readBuffer.startIndex..<nl)
            readBuffer.removeSubrange(readBuffer.startIndex...nl)
            for event in parser.parseLine(line) { route(event) }
        }
    }

    /// The pty closed or `%exit` arrived without us asking.
    private func controlExited() {
        guard state != .idle else { return }
        let sid = sessionID
        let requested = detachRequested
        teardown()
        guard !requested else { return }
        let stillExists = sid.map { tmux.session(id: $0) != nil } ?? false
        log.info("control client left \(sid ?? "?") (session \(stillExists ? "alive" : "gone"))")
        onEvent?(.detached(stillExists ? .controlExited : .sessionKilled))
    }

    /// Kill the child, close the pty, restore phone-owned pane zoom, and unpin
    /// windows. Emits nothing.
    private func teardown() {
        inputTimer?.cancel()
        inputTimer = nil
        windowsRefresh?.cancel()
        windowsRefresh = nil
        panesRefresh?.cancel()
        panesRefresh = nil
        restorePhoneZoomIfNeeded()
        readSource?.cancel()
        readSource = nil
        if ptyFD >= 0 { close(ptyFD); ptyFD = -1 }
        if childPID > 0 {
            kill(childPID, SIGHUP)
            var status: Int32 = 0
            if waitpid(childPID, &status, WNOHANG) == 0 {
                kill(childPID, SIGKILL)
                waitpid(childPID, &status, 0)
            }
            childPID = 0
        }
        for window in pinnedWindows { tmux.unpinWindowSize(windowID: window) }
        pinnedWindows.removeAll()
        pendingInput.removeAll()
        readBuffer.removeAll()
        activePane = nil
        activeWindow = nil
        sessionID = nil
        state = .idle
    }

    // MARK: - Inbound (tmux → agent)

    private func route(_ event: TmuxControlEvent) {
        switch event {
        case .output(let pane, let bytes):
            if pane == activePane { onEvent?(.output(bytes)) }
        case .sessionChanged(let id, _):
            guard state == .spawning, let sid = sessionID else { return }
            if id != sid { log.warning("attached to \(id), asked for \(sid)") }
            state = .attached
            guard let session = tmux.session(id: id) else {
                onEvent?(.error("session \(id) vanished during attach"))
                detachRequested = true
                teardown()
                onEvent?(.detached(.sessionKilled))
                return
            }
            sessionID = id
            onEvent?(.attached(session: session, windows: tmux.windows(sessionID: id)))
            showPane(target: id)
        case .sessionWindowChanged(_, let windowID):
            guard state == .attached, windowID != activeWindow else { return }
            showPane(target: windowID)
            scheduleWindowsRefresh()
        case .windowPaneChanged(let windowID, _):
            // Track the phone-selected pane, but do not follow the window's
            // global pane selection from the Mac. Moving tmux's zoomed pane is
            // a window-level operation and may still update that global flag.
            guard state == .attached, windowID == activeWindow else { return }
            schedulePaneRefresh()
        case .windowAdd, .windowClose, .windowRenamed:
            scheduleWindowsRefresh()
        case .layoutChange(let windowID):
            scheduleWindowsRefresh()
            guard state == .attached, windowID == activeWindow else { return }
            schedulePaneRefresh()
        case .sessionRenamed:
            onEvent?(.sessionsChanged)
        case .sessionsChanged:
            onEvent?(.sessionsChanged)
        case .exit:
            controlExited()
        case .error(let text):
            log.warning("tmux: \(text)")
            onEvent?(.error(text))
        case .commandOutput:
            break
        }
    }

    /// Resolve a pane, make it fill a multi-pane window, pin that window to the
    /// phone's size, and send a full repaint built from tmux's own pane state.
    private func showPane(target: String, keepPhoneZoom: Bool = false) {
        guard let sid = sessionID else { return }
        if !keepPhoneZoom { restorePhoneZoomIfNeeded() }
        guard var paneState = tmux.paneState(target: target) else { return }

        var panes = tmux.panes(windowID: paneState.windowID)
        ensurePhoneZoom(windowID: paneState.windowID, paneID: paneState.paneID, panes: panes)

        if let size = clientSize {
            tmux.pinWindowSize(windowID: paneState.windowID, cols: size.cols, rows: size.rows)
            pinnedWindows.insert(paneState.windowID)
            // Re-read after the resize so the capture matches the new geometry.
            paneState = tmux.paneState(target: paneState.paneID) ?? paneState
            panes = tmux.panes(windowID: paneState.windowID)
        }

        activePane = paneState.paneID
        activeWindow = paneState.windowID
        publishPanes(sessionID: sid, windowID: paneState.windowID, panes: panes)
        let capture = tmux.capture(paneID: paneState.paneID, fromLine: ScreenPrimer.captureStart(for: paneState))
        onEvent?(.reset(ScreenPrimer.frame(state: paneState, capture: capture)))
        if let size = clientSize { writeLine("refresh-client -C \(size.cols)x\(size.rows)") }
    }

    /// A phone-sized window with two horizontal panes would leave each pane at
    /// half width. tmux's own zoom operation gives the selected pane the full
    /// phone grid while preserving the split; it is undone on switch/detach.
    private func ensurePhoneZoom(windowID: String, paneID: String, panes: [PaneInfo]) {
        guard panes.count > 1 else {
            if phoneZoomedWindowID == windowID { restorePhoneZoomIfNeeded() }
            return
        }
        let ownsWindow = phoneZoomedWindowID == windowID
        guard phoneZoomedWindowID == nil || ownsWindow, !tmux.windowIsZoomed(windowID: windowID) else { return }
        guard tmux.togglePaneZoom(paneID: paneID) else {
            log.warning("could not zoom pane \(paneID) in \(windowID)")
            return
        }
        phoneZoomedWindowID = windowID
        phoneZoomedPaneID = paneID
    }

    private func restorePhoneZoomIfNeeded() {
        guard let windowID = phoneZoomedWindowID else { return }
        if tmux.windowIsZoomed(windowID: windowID) {
            let panes = tmux.panes(windowID: windowID)
            let trackedPane = phoneZoomedPaneID.flatMap { id in panes.contains(where: { $0.id == id }) ? id : nil }
            let paneID = trackedPane ?? panes.first(where: { $0.id == activePane })?.id ?? panes.first?.id
            if let paneID { _ = tmux.togglePaneZoom(paneID: paneID) }
        }
        phoneZoomedWindowID = nil
        phoneZoomedPaneID = nil
    }

    private func publishPanes(sessionID: String, windowID: String, panes: [PaneInfo]) {
        let scoped = panes.map { pane in
            var pane = pane
            pane.active = pane.id == activePane
            return pane
        }
        onEvent?(.panesChanged(sessionID: sessionID, windowID: windowID, panes: scoped))
    }

    private func scheduleWindowsRefresh() {
        windowsRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let sid = self.sessionID, self.state == .attached else { return }
            self.onEvent?(.windowsChanged(self.tmux.windows(sessionID: sid)))
        }
        windowsRefresh = item
        queue.asyncAfter(deadline: .now() + .milliseconds(60), execute: item)
    }

    private func schedulePaneRefresh() {
        panesRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let windowID = self.activeWindow, self.state == .attached else { return }
            let panes = self.tmux.panes(windowID: windowID)
            let selectedPane = panes.first { $0.id == self.activePane }
            let splitNeedsZoom = panes.count > 1 && !self.tmux.windowIsZoomed(windowID: windowID)
            let sizeMismatch = self.clientSize.map { size in
                selectedPane?.width != size.cols || selectedPane?.height != size.rows
            } ?? false
            if selectedPane == nil || splitNeedsZoom || sizeMismatch {
                let target = selectedPane == nil ? windowID : self.activePane ?? windowID
                self.showPane(target: target, keepPhoneZoom: self.phoneZoomedWindowID == windowID)
            } else if let sid = self.sessionID {
                self.publishPanes(sessionID: sid, windowID: windowID, panes: panes)
            }
        }
        panesRefresh = item
        queue.asyncAfter(deadline: .now() + .milliseconds(60), execute: item)
    }

    // MARK: - Outbound (agent → tmux)

    func sendInput(_ bytes: [UInt8]) {
        queue.async { [self] in pendingInput.append(contentsOf: bytes) }
    }

    func paste(_ text: String) {
        queue.async { [self] in
            guard let pane = activePane else { return }
            flushInput()   // keep ordering: keys typed before the paste land first
            if !tmux.paste(text, paneID: pane) { onEvent?(.error("paste failed")) }
        }
    }

    func resize(cols: Int, rows: Int) {
        queue.async { [self] in
            clientSize = (cols, rows)
            guard state == .attached, let windowID = activeWindow, let paneID = activePane else { return }
            let panes = tmux.panes(windowID: windowID)
            ensurePhoneZoom(windowID: windowID, paneID: paneID, panes: panes)
            tmux.pinWindowSize(windowID: windowID, cols: cols, rows: rows)
            pinnedWindows.insert(windowID)
            writeLine("refresh-client -C \(cols)x\(rows)")
        }
    }

    func selectWindow(id: String) {
        queue.async { [self] in
            guard state == .attached, let sid = sessionID else { return }
            guard tmux.windows(sessionID: sid).contains(where: { $0.id == id }) else {
                onEvent?(.error("no such window \(id)"))
                return
            }
            // Switch this client rather than the window's global active state.
            // %session-window-changed follows and re-primes the selected pane.
            writeLine("switch-client -t \(id)")
        }
    }

    func selectPane(id: String) {
        queue.async { [self] in
            guard state == .attached, let windowID = activeWindow,
                  tmux.panes(windowID: windowID).contains(where: { $0.id == id }) else {
                onEvent?(.error("no such pane \(id)"))
                return
            }
            guard id != activePane else { return }
            activePane = id
            if phoneZoomedWindowID == windowID { phoneZoomedPaneID = id }
            // `-Z` moves an already-zoomed window to this client pane instead
            // of unzooming it. showPane then guarantees full phone width.
            writeLine("switch-client -Z -t \(id)")
            showPane(target: id, keepPhoneZoom: phoneZoomedWindowID == windowID)
        }
    }

    func createWindow() {
        queue.async { [self] in
            guard state == .attached, let sid = sessionID else { return }
            if !tmux.createWindow(sessionID: sid) { onEvent?(.error("could not create a window")) }
        }
    }

    func killWindow(id: String) {
        queue.async { [self] in
            guard state == .attached else { return }
            if !tmux.killWindow(id: id) { onEvent?(.error("could not kill window \(id)")) }
        }
    }

    func renameWindow(id: String, name: String) {
        queue.async { [self] in
            guard state == .attached else { return }
            if !tmux.renameWindow(id: id, name: name) { onEvent?(.error("could not rename window \(id)")) }
        }
    }

    private func writeLine(_ command: String) {
        guard ptyFD >= 0 else { return }
        let data = Array((command + "\n").utf8)
        data.withUnsafeBytes { _ = write(ptyFD, $0.baseAddress, $0.count) }
    }

    /// Coalesce keystrokes into one `send-keys` line every ~16 ms.
    private func startInputTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in self?.flushInput() }
        inputTimer = timer
        timer.resume()
    }

    private func flushInput() {
        guard !pendingInput.isEmpty, ptyFD >= 0, state == .attached else { return }
        let bytes = pendingInput
        pendingInput.removeAll(keepingCapacity: true)
        for line in SendKeysEncoder.lines(for: bytes, paneID: activePane) { writeLine(line) }
    }
}
