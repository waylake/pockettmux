import Foundation

/// Short-lived tmux subprocesses for list/create/destroy/version.
/// (In-flight session browsing does not need a control client.)
enum TmuxQueries {
    private static let path = TmuxLocator.path
    static let listFormat = "#{session_id}|#{session_name}|#{session_windows}|#{session_attached}|#{session_created}|#{session_activity}"

    static func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }

    static func list() -> [TmuxSessionInfo] {
        guard let out = run(["ls", "-F", listFormat]) else { return [] }
        return TmuxLsParser.parse(out)
    }

    static func version() -> String {
        guard let out = run(["-V"]) else { return "?" }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns nil on invalid names; false on tmux failure.
    static func create(name: String) -> Bool? {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\n"),
              name.count <= 64 else { return nil }
        return run(["new-session", "-d", "-s", name]) != nil
    }

    static func destroy(id: String) -> Bool {
        run(["kill-session", "-t", id]) != nil
    }
}
