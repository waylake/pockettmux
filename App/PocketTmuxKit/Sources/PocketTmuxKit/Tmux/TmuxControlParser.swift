import Foundation

/// Streaming parser for tmux control-mode (`-CC`) output.
///
/// tmux emits one frame per line (CRLF from the pty; `parseLine` strips it).
/// Frames we care about (verified against tmux 3.7c):
///   %output <pane-id> <octal-escaped payload…>
///   %session-changed <id> <name> · %session-renamed <name>
///   %session-window-changed <sid> <wid> · %window-pane-changed <wid> <pid>
///   %sessions-changed · %window-add / %window-close / %window-renamed · %layout-change
///   %begin <t> <num> <flags> … %end / %error   (command output blocks)
///   %exit [reason]
public enum TmuxControlEvent: Equatable, Sendable {
    case output(pane: String, bytes: [UInt8])
    case sessionChanged(id: String, name: String)
    case sessionRenamed(name: String)
    case sessionWindowChanged(sessionID: String, windowID: String)
    case windowPaneChanged(windowID: String, paneID: String)
    case sessionsChanged
    case windowAdd(windowID: String)
    case windowClose(windowID: String)
    case windowRenamed(windowID: String, name: String)
    case layoutChange(windowID: String)
    case commandOutput(num: Int, text: String)   // a reply line inside a %begin/%end block
    case error(text: String)
    case exit(reason: String?)
}

public struct TmuxControlParser: Sendable {
    public init() {}

    /// Feed one raw line (bytes, without the framing newline). Returns the
    /// events decoded from it — empty for lines that are not control frames.
    public func parseLine(_ raw: Data) -> [TmuxControlEvent] {
        var line = raw
        while line.last == 0x0A || line.last == 0x0D { line.removeLast() }
        guard line.first == 0x25 /* '%' */ else { return [] }

        let text = String(decoding: line, as: UTF8.self)
        let tokens = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard let type = tokens.first else { return [] }

        switch type {
        case "%output":
            guard tokens.count >= 2 else { return [] }
            let pane = tokens[1]
            let headerLen = Data("%output \(pane) ".utf8).count
            return [.output(pane: pane, bytes: Self.unescapeOctal(line.dropFirst(headerLen)))]
        case "%session-changed":
            guard tokens.count >= 3 else { return [] }
            return [.sessionChanged(id: tokens[1], name: tokens[2])]
        case "%session-renamed":
            guard tokens.count >= 2 else { return [] }
            return [.sessionRenamed(name: tokens.dropFirst().joined(separator: " "))]
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
        case "%window-renamed":
            guard tokens.count >= 3 else { return [] }
            return [.windowRenamed(windowID: tokens[1], name: tokens[2])]
        case "%layout-change":
            guard tokens.count >= 2 else { return [] }
            return [.layoutChange(windowID: tokens[1])]
        case "%exit":
            return [.exit(reason: tokens.count >= 2 ? tokens.dropFirst().joined(separator: " ") : nil)]
        case "%error":
            return [.error(text: text)]
        case "%begin", "%end", "%enter", "%unlinked-window-add", "%unlinked-window-close",
             "%client-session-changed", "%client-detached", "%pause", "%continue", "%subscription-changed":
            return []
        default:
            // Command reply lines look like "%<cmdnum> <text>".
            if let sp = text.dropFirst().firstIndex(of: " "),
               let num = Int(text[text.index(after: text.startIndex)..<sp]) {
                return [.commandOutput(num: num, text: String(text[text.index(after: sp)...]))]
            }
            return []
        }
    }

    /// tmux escapes non-printable bytes and backslash as `\ooo` octal.
    public static func unescapeOctal(_ data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x5C /* \ */ {
                if i + 1 < bytes.count && bytes[i + 1] == 0x5C {
                    out.append(0x5C)
                    i += 2
                    continue
                }
                if i + 3 < bytes.count,
                   let a = octal(bytes[i + 1]), let b = octal(bytes[i + 2]), let c = octal(bytes[i + 3]) {
                    out.append((a << 6) | (b << 3) | c)
                    i += 4
                    continue
                }
            }
            out.append(bytes[i])
            i += 1
        }
        return out
    }

    private static func octal(_ c: UInt8) -> UInt8? {
        (0x30...0x37).contains(c) ? c - 0x30 : nil
    }
}
