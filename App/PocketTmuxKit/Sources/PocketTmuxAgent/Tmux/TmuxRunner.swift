import Foundation
import PocketTmuxKit

/// Resolves the tmux binary from the usual Homebrew/system locations.
public enum TmuxLocator {
    public static let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]

    public static func resolve(override: String? = nil) -> String? {
        if let override, !override.isEmpty {
            return FileManager.default.isExecutableFile(atPath: override) ? override : nil
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Short-lived `tmux …` subprocesses: list/create/kill/rename, pane state,
/// capture-pane, paste. Everything that is a *query* or a one-shot command
/// goes through here; only the streaming control channel lives in TmuxControl.
public struct TmuxRunner: Sendable {
    public let path: String

    public init(path: String) { self.path = path }

    /// stdout on exit 0, nil otherwise. Never throws; callers decide what a
    /// failure means (tmux server not running, unknown target, …).
    @discardableResult
    public func run(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    public func version() -> String {
        run(["-V"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "tmux (unknown)"
    }

    // MARK: Sessions

    public func sessions() -> [SessionInfo] {
        guard let out = run(["list-sessions", "-F", TmuxFormats.sessionList]) else { return [] }
        return TmuxFormats.parseSessions(out)
    }

    public func session(id: String) -> SessionInfo? {
        sessions().first { $0.id == id }
    }

    public func createSession(name: String) -> Bool {
        run(["new-session", "-d", "-s", name]) != nil
    }

    public func renameSession(id: String, name: String) -> Bool {
        run(["rename-session", "-t", id, name]) != nil
    }

    public func killSession(id: String) -> Bool {
        run(["kill-session", "-t", id]) != nil
    }

    // MARK: Windows

    public func windows(sessionID: String) -> [WindowInfo] {
        guard let out = run(["list-windows", "-t", sessionID, "-F", TmuxFormats.windowList]) else { return [] }
        return TmuxFormats.parseWindows(out)
    }

    public func createWindow(sessionID: String) -> Bool {
        run(["new-window", "-t", sessionID + ":"]) != nil
    }

    public func killWindow(id: String) -> Bool {
        run(["kill-window", "-t", id]) != nil
    }

    public func renameWindow(id: String, name: String) -> Bool {
        run(["rename-window", "-t", id, name]) != nil
    }

    public func selectWindow(id: String) -> Bool {
        run(["select-window", "-t", id]) != nil
    }

    // MARK: Pane state / content

    /// Active pane of `target` (a session or window id) with the flags the
    /// phone's emulator must be primed with.
    public func paneState(target: String) -> TmuxFormats.PaneState? {
        guard let out = run(["display-message", "-p", "-t", target, TmuxFormats.paneState]) else { return nil }
        return TmuxFormats.parsePaneState(out)
    }

    /// `capture-pane -p -e` from `start` to the bottom of the visible screen.
    public func capture(paneID: String, fromLine start: Int) -> String? {
        run(["capture-pane", "-p", "-e", "-t", paneID, "-S", "\(start)", "-E", "-"])
    }

    /// Pin a window's size so the shared window stops bouncing between the
    /// Mac's and the phone's client sizes (TROUBLESHOOTING §2).
    public func pinWindowSize(windowID: String, cols: Int, rows: Int) {
        run(["resize-window", "-t", windowID, "-x", "\(max(2, cols))", "-y", "\(max(1, rows))"])
        run(["set-window-option", "-t", windowID, "window-size", "manual"])
    }

    public func unpinWindowSize(windowID: String) {
        run(["set-window-option", "-u", "-t", windowID, "window-size"])
    }

    /// Bracketed paste: `paste-buffer -p` wraps the text in `ESC[200~ … ESC[201~`
    /// iff the pane has asked for bracketed paste, exactly like a local paste.
    public func paste(_ text: String, paneID: String) -> Bool {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("pockettmux-paste-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil else { return false }
        let buffer = "pockettmux"
        guard run(["load-buffer", "-b", buffer, file.path]) != nil else { return false }
        return run(["paste-buffer", "-p", "-d", "-b", buffer, "-t", paneID]) != nil
    }
}
