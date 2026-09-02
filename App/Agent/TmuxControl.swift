import Foundation
import Darwin

/// Spawns `tmux -CC attach` on a real pty and speaks the control-mode wire
/// protocol. Verified against tmux 3.7c:
///   - stdin of the control client parses *commands* (not keys)
///   - keys  → `send-keys -H <hex>` (raw bytes; prefix/vi bindings work)
///   - size  → `refresh-client -C <cols>x<rows>` (triggers a full repaint)
///   - pane output → `%output <pane> <octal-escaped payload>` frames
final class TmuxControl {
    enum State { case idle, spawning, attached }

    private(set) var state: State = .idle
    private(set) var activePane: String?

    /// Events from the tmux stream (already decoded), on `queue`.
    var onEvent: ((TmuxControlEvent) -> Void)?
    /// Raw pane output bytes for the *active* pane only, on `queue`.
    var onActiveOutput: (([UInt8]) -> Void)?
    /// Fired once after the control client has attached to a session.
    var onAttached: ((Bool) -> Void)?

    private let queue: DispatchQueue
    private var mfd: Int32 = -1
    private var childPid: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var readBuffer = Data()
    private let parser = TmuxControlParser()
    private var pendingInput = [UInt8]()
    private var flushTimer: DispatchSourceTimer?
    /// Session the control client is attached to; used to pin/restore
    /// `window-size` so the shared window doesn't bounce between the Mac's and
    /// the phone's size while attached.
    private var sessionID: String?

    private static let tmuxPath: String = TmuxLocator.path

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    // MARK: - Lifecycle

    func attach(sessionID: String) {
        queue.async { [weak self] in
            self?.sessionID = sessionID
            self?.killChild()
            self?.spawn(sessionID: sessionID)
        }
    }

    func detach() {
        queue.async { [weak self] in
            self?.killChild()
            self?.restoreWindowSize()
            self?.sessionID = nil
        }
    }

    private func spawn(sessionID: String) {
        var m: Int32 = 0
        let pid = forkpty(&m, nil, nil, nil)
        guard pid >= 0 else { onEvent?(.error(text: "forkpty failed")); finishExit(); return }
        if pid == 0 {
            setenv("TERM", "xterm-256color", 1)
            // In the child: exec tmux control client.
            let args = ["tmux", "-CC", "attach", "-t", sessionID]
            var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
            execv(Self.tmuxPath, &argv)
            _exit(127)
        }
        mfd = m
        childPid = pid
        state = .attached
        readBuffer.removeAll(keepingCapacity: true)

        let source = DispatchSource.makeReadSource(fileDescriptor: mfd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var buf = [UInt8](repeating: 0, count: 8192)
            let count = buf.count
            let n = buf.withUnsafeMutableBytes { read(self.mfd, $0.baseAddress, count) }
            if n < 0 && errno == EAGAIN { return }
            if n <= 0 { self.finishExit(); return }
            self.ingest(Data(buf.prefix(n)))
        }
        source.setCancelHandler { [weak self] in
            self?.mfd = -1
        }
        readSource = source
        source.resume()

        // Pin the window so the shared size doesn't bounce between the Mac and
        // the phone while attached (iTerm2 does the same). The phone's size is
        // applied via `resize-window` on resize (manual ignores refresh-client).
        _ = TmuxQueries.run(["set-window-option", "-t", sessionID, "window-size", "manual"])
        // No forced sizes here: the control client inherits the window's
        // current size and a plain `refresh-client` forces the full initial
        // paint; the phone's own size arrives as a resize shortly after.
        writeLine("refresh-client")
        primeScreen(sessionID: sessionID)
        // Resolve the active pane now (single text reply expected next).
        writeLine("display-message -p '#{pane_id}'")
    }

    /// tmux control mode relays only *new* pane output — it replays nothing that
    /// predates the control client (verified against tmux 3.7c: attach +
    /// `refresh-client` yields zero `%output` frames, even for a pane running
    /// vim). So the phone's emulator starts blank, with an empty scrollback and,
    /// worse, **no idea** that the pane is on the alternate screen or has mouse
    /// reporting on — the app emitted those escapes before we attached. Every
    /// client-side heuristic built on `isCurrentBufferAlternate` / `mouseMode`
    /// therefore read `false`/`off` forever, which is why swipe-to-scroll in a
    /// TUI never fired.
    ///
    /// tmux tracks all of it per pane, so rebuild the state and hand it to the
    /// phone as the first frame. This is what control-mode clients are expected
    /// to do — the tmux wiki leaves the initial paint to the client, "for
    /// example using capture-pane", and iTerm2 does the same.
    private func primeScreen(sessionID: String) {
        let fmt = "#{alternate_on}|#{mouse_any_flag}|#{mouse_sgr_flag}|#{keypad_cursor_flag}|#{history_size}"
        guard let raw = TmuxQueries.run(["display-message", "-p", "-t", sessionID, fmt]) else { return }
        let f = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        func flag(_ i: Int) -> Bool { i < f.count && f[i] == "1" }
        let alt = flag(0)

        var esc = "\u{1b}[?1049l\u{1b}[H\u{1b}[2J\u{1b}[3J"   // leave any alt buffer, clear screen + scrollback
        if alt { esc += "\u{1b}[?1049h" }
        if flag(1) {
            esc += "\u{1b}[?1000h\u{1b}[?1002h"
            if flag(2) { esc += "\u{1b}[?1006h" }
        }
        if flag(3) { esc += "\u{1b}[?1h" }                      // DECCKM: application cursor keys

        // The alternate screen has no scrollback; the normal one does, and it is
        // the only history the phone can ever drag through.
        let history = min(Int(f.count > 4 ? f[4] : "0") ?? 0, 2000)
        let start = alt ? "0" : "-\(history)"
        if let dump = TmuxQueries.run(["capture-pane", "-p", "-e", "-t", sessionID, "-S", start, "-E", "-"]) {
            // capture-pane separates lines with a bare LF, which keeps the column;
            // the phone needs a CR too. Trailing blank lines would push the cursor
            // off the captured screen, so drop them.
            var lines = dump.components(separatedBy: "\n")
            while let last = lines.last, last.isEmpty { lines.removeLast() }
            esc += "\u{1b}[H" + lines.joined(separator: "\r\n")
        }
        onActiveOutput?(Array(esc.utf8))
    }

    private func killChild() {
        if childPid > 0 {
            kill(childPid, SIGHUP)
            kill(childPid, SIGTERM)
            // Collect so we don't zombie.
            var st: Int32 = 0
            waitpid(childPid, &st, WNOHANG)
        }
        if childPid > 0 {
            kill(childPid, SIGKILL)
            var st: Int32 = 0
            waitpid(childPid, &st, 0)
        }
        childPid = 0
        readSource?.cancel()
        readSource = nil
        if mfd >= 0 { close(mfd); mfd = -1 }
        pendingInput.removeAll()
        activePane = nil
        state = .idle
    }

    private func finishExit() {
        print("diag: tmux control client exited (pid \(childPid))")
        killChild()
        restoreWindowSize()
        sessionID = nil
        state = .idle
        onEvent?(.exit(reason: nil))
    }

    /// Put the session's windows back to the default `latest` sizing so the
    /// Mac client re-asserts its own size once the phone detaches.
    private func restoreWindowSize() {
        guard let sid = sessionID else { return }
        _ = TmuxQueries.run(["set-window-option", "-u", "-t", sid, "window-size"])
    }

    deinit { killChild() }

    // MARK: - Inbound (tmux → agent)

    private func ingest(_ data: Data) {
        readBuffer.append(data)
        while let nl = readBuffer.firstIndex(of: 0x0A) {
            let line = readBuffer.prefix(upTo: nl)
            readBuffer.removeSubrange(0...nl)
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        for ev in parser.parseLine(line) {
            route(ev)
        }
    }

    private func route(_ ev: TmuxControlEvent) {
        switch ev {
        case .output(let pane, let bytes):
            // When the active pane is unknown (e.g. mid window-switch) feed
            // everything so the new window always appears; otherwise filter.
            // ponytail: multi-pane windows can interleave while unknown — v1 keeps the
            // active window visible, a pane-picker is a v2 feature.
            if activePane == nil || pane == activePane {
                onActiveOutput?(bytes)
            }
        case .sessionChanged:
            onEvent?(ev); onAttached?(true)
        case .windowPaneChanged(_, let paneID):
            activePane = paneID
            onEvent?(ev)
        case .commandOutput(_, let text):
            // Result of our `display-message -p '#{pane_id}'` (first text block
            // after attach; nothing else in flight then).
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("%") && activePane != t { activePane = t }
            onEvent?(ev)
        case .sessionWindowChanged:
            // New window: pane id unknown until %window-pane-changed lands.
            activePane = nil
            onEvent?(ev)
        default:
            onEvent?(ev)
        }
    }

    // MARK: - Outbound (agent → tmux)

    func sendInput(_ bytes: [UInt8]) {
        queue.async { [weak self] in
            self?.pendingInput.append(contentsOf: bytes)
        }
    }

    func resize(cols: Int, rows: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            // window-size is manual while attached, so resize the window to the
            // phone's size explicitly (refresh-client -C alone is ignored) and
            // then point the client's viewport at it.
            if let sid = self.sessionID {
                _ = TmuxQueries.run(["resize-window", "-t", sid, "-x", "\(max(2, cols))", "-y", "\(max(1, rows))"])
            }
            self.writeLine("refresh-client -C \(max(2, cols))x\(max(1, rows))")
        }
    }

    private func writeLine(_ s: String) {
        guard mfd >= 0 else { return }
        let data = (s + "\n").data(using: .utf8)!
        data.withUnsafeBytes { _ = write(mfd, $0.baseAddress!, data.count) }
    }

    /// Flush coalesced keystrokes as one send-keys line every ~16 ms.
    private func startFlushTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(4))
        t.setEventHandler { [weak self] in self?.flushInput() }
        flushTimer = t
        t.resume()
    }

    private func flushInput() {
        guard !pendingInput.isEmpty, mfd >= 0 else { return }
        let bytes = pendingInput
        pendingInput.removeAll()
        // send-keys -H expects ONE hex number per key, so each byte is its own
        // 2-hex-digit arg (verified: multi-byte hex args are silently dropped).
        // Chunk at 128 bytes/line to stay well under stdin line limits.
        let target = activePane.map { "-t \($0) " } ?? ""
        var line = "send-keys -H \(target)"
        var n = 0
        for b in bytes {
            line += String(format: " %02x", b)
            n += 1
            if n == 128 {
                writeLine(line)
                line = "send-keys -H \(target)"
                n = 0
            }
        }
        if n > 0 { writeLine(line) }
    }

    func ensureFlusher() {
        queue.async { [weak self] in if self?.flushTimer == nil { self?.startFlushTimer() } }
    }
}

/// Resolve the tmux binary once, from the usual brew/system locations.
enum TmuxLocator {
    static let path: String = {
        for p in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "/opt/homebrew/bin/tmux"
    }()
}
