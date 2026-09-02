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
    /// Windows whose `window-size` we set to manual; unpinned on detach.
    private var pinnedWindows = Set<String>()
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
            let args = ["tmux", "-CC", "attach-session", "-t", sessionID]
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

    /// Kill the child, close the pty, unpin windows. Emits nothing.
    private func teardown() {
        inputTimer?.cancel()
        inputTimer = nil
        windowsRefresh?.cancel()
        windowsRefresh = nil
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
            showActivePane()
        case .sessionWindowChanged(_, let windowID):
            guard state == .attached, windowID != activeWindow else { return }
            showActivePane()
            scheduleWindowsRefresh()
        case .windowPaneChanged(let windowID, let paneID):
            guard state == .attached, windowID == activeWindow, paneID != activePane else { return }
            showActivePane()
        case .windowAdd, .windowClose, .windowRenamed, .layoutChange:
            scheduleWindowsRefresh()
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

    /// Resolve the session's active pane, pin its window to the phone's
    /// size, and send a full repaint built from tmux's own pane state.
    private func showActivePane() {
        guard let sid = sessionID, var paneState = tmux.paneState(target: sid) else { return }
        if let size = clientSize {
            tmux.pinWindowSize(windowID: paneState.windowID, cols: size.cols, rows: size.rows)
            pinnedWindows.insert(paneState.windowID)
            // Re-read after the resize so the capture matches the new geometry.
            paneState = tmux.paneState(target: sid) ?? paneState
        }
        activePane = paneState.paneID
        activeWindow = paneState.windowID
        let capture = tmux.capture(paneID: paneState.paneID, fromLine: ScreenPrimer.captureStart(for: paneState))
        onEvent?(.reset(ScreenPrimer.frame(state: paneState, capture: capture)))
        if let size = clientSize { writeLine("refresh-client -C \(size.cols)x\(size.rows)") }
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
            guard state == .attached, let window = activeWindow else { return }
            tmux.pinWindowSize(windowID: window, cols: cols, rows: rows)
            pinnedWindows.insert(window)
            writeLine("refresh-client -C \(cols)x\(rows)")
        }
    }

    func selectWindow(id: String) {
        queue.async { [self] in
            guard state == .attached else { return }
            if !tmux.selectWindow(id: id) { onEvent?(.error("no such window \(id)")) }
            // %session-window-changed follows and repaints.
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
