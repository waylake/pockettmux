import Foundation

/// Pure, dependency-free logic shared by the agent and the unit-test target.
/// Nothing in here touches the network or processes.

/// A tmux session as surfaced by `tmux ls -F`.
public struct TmuxSessionInfo: Codable, Equatable, Sendable {
    public let id: String          // "$1"
    public let name: String
    public let windows: Int
    public let attached: Int
    public let created: TimeInterval   // epoch seconds
    public let activity: TimeInterval  // epoch seconds

    public init(id: String, name: String, windows: Int, attached: Int,
                created: TimeInterval, activity: TimeInterval) {
        self.id = id
        self.name = name
        self.windows = windows
        self.attached = attached
        self.created = created
        self.activity = activity
    }
}

public enum TmuxLsParser {
    /// Parses one line of `tmux ls -F "…|…#{session_id}…"` output.
    /// Field separator is "|"; a malformed line returns nil.
    public static func parseLine(_ line: String) -> TmuxSessionInfo? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6,
              let windows = Int(parts[2]),
              let attached = Int(parts[3]),
              let created = TimeInterval(parts[4]),
              let activity = TimeInterval(parts[5]) else { return nil }
        return TmuxSessionInfo(id: parts[0], name: parts[1], windows: windows,
                               attached: attached, created: created, activity: activity)
    }

    public static func parse(_ text: String) -> [TmuxSessionInfo] {
        text.split(separator: "\n").compactMap { parseLine(String($0)) }
    }
}

public enum Hex {
    public static func encode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
    public static func decode(_ s: String) -> Data? {
        guard s.count.isMultiple(of: 2) else { return nil }
        var out = Data(); out.reserveCapacity(s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let n = s.index(i, offsetBy: 2)
            guard let v = UInt8(s[i..<n], radix: 16) else { return nil }
            out.append(v)
            i = n
        }
        return out
    }
}

/// Streaming parser for tmux control-mode (`-CC`) output.
///
/// tmux emits one frame per line (we observe CRLF from the pty; `feed` strips it).
/// Frames we care about (verified against tmux 3.7c):
///   %output <pane-id> <octal-escaped payload…>
///   %session-changed <id> <name> · %session-renamed <name>
///   %session-window-changed <sid> <wid> · %window-pane-changed <wid> <pid>
///   %sessions-changed · %window-add / %window-close · %layout-change
///   %begin <t> <num> <flags> … %end / %error   (command output blocks)
///   %exit [reason]
public enum TmuxControlEvent: Equatable {
    case output(pane: String, bytes: [UInt8])
    case sessionChanged(id: String, name: String)
    case sessionRenamed(name: String)
    case sessionWindowChanged(sessionID: String, windowID: String)
    case windowPaneChanged(windowID: String, paneID: String)
    case sessionsChanged
    case windowAdd(windowID: String)
    case windowClose(windowID: String)
    case layoutChange
    case commandOutput(num: Int, text: String)   // a reply line inside a %begin/%end block
    case error(text: String)
    case exit(reason: String?)
}

public final class TmuxControlParser {
    public init() {}

    /// Feed one raw line (bytes). Returns events decoded from it.
    public func parseLine(_ raw: Data) -> [TmuxControlEvent] {
        var line = raw
        // Strip trailing CR and LF (pty ONLCR produces CRLF).
        while line.last == 0x0A || line.last == 0x0D { line.removeLast() }
        guard line.first == 0x25 /* '%' */ else { return [] }

        let s = String(decoding: line, as: UTF8.self)
        let tokens = s.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard let type = tokens.first else { return [] }

        switch type {
        case "%output":
            guard tokens.count >= 2 else { return [] }
            let pane = tokens[1]
            // Payload = everything after "<pane> " as raw bytes (octal-escaped).
            let headerLen = Data("%output \(pane) ".utf8).count
            let payload = line.dropFirst(headerLen)
            return [.output(pane: pane, bytes: Self.unescapeOctal(payload))]
        case "%session-changed":
            guard tokens.count >= 3 else { return [] }
            return [.sessionChanged(id: tokens[1], name: tokens[2])]
        case "%session-renamed":
            guard tokens.count >= 2 else { return [] }
            return [.sessionRenamed(name: tokens[1])]
        case "%session-window-changed":
            guard tokens.count >= 3 else { return [] }
            return [.sessionWindowChanged(sessionID: tokens[1], windowID: tokens[2])]
        case "%window-pane-changed":
            guard tokens.count >= 3 else { return [] }
            return [.windowPaneChanged(windowID: tokens[1], paneID: tokens[2])]
        case "%sessions-changed":
            return [.sessionsChanged]
        case "%window-add":
            guard tokens.count >= 2 else { return [] }
            return [.windowAdd(windowID: tokens[1])]
        case "%window-close":
            guard tokens.count >= 2 else { return [] }
            return [.windowClose(windowID: tokens[1])]
        case "%layout-change":
            return [.layoutChange]
        case "%enter":            // command block open — ignore (we parse replies by %<num> prefix)
            return []
        case "%exit":
            return [.exit(reason: tokens.count >= 2 ? tokens[1] : nil)]
        case "%error":
            return [.error(text: s)]
        default:
            // Command reply lines look like "%<cmdnum> <text>".
            if s.hasPrefix("%"), let sp = s.dropFirst().firstIndex(of: " "),
               let num = Int(s[s.index(s.startIndex, offsetBy: 1)..<sp]) {
                return [.commandOutput(num: num, text: String(s[s.index(after: sp)...]))]
            }
            return []
        }
    }

    /// tmux escapes non-printable bytes and backslash as \ooo octal.
    public static func unescapeOctal(_ data: Data) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(data.count)
        var i = 0
        let b = [UInt8](data)
        while i < b.count {
            if b[i] == 0x5C /* \ */ {
                if i + 1 < b.count && b[i + 1] == 0x5C {
                    out.append(0x5C); i += 2; continue
                }
                if i + 3 < b.count,
                   let v = Self.octal(b[i + 1]), let w = Self.octal(b[i + 2]), let z = Self.octal(b[i + 3]) {
                    out.append((v << 6) | (w << 3) | z); i += 4; continue
                }
            }
            out.append(b[i]); i += 1
        }
        return out
    }

    private static func octal(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x37: return c - 0x30
        default: return nil
        }
    }
}
