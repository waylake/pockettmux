import Foundation
import PocketTmuxKit

/// Builds the first frame after an attach or window switch.
///
/// `tmux -CC` relays only *new* pane output — it replays nothing that predates
/// the control client (verified against tmux 3.7c). Left alone, the phone's
/// emulator would start blank, with an empty scrollback and no idea that the
/// pane is on the alternate screen or has mouse reporting on. tmux tracks all
/// of that per pane, so we rebuild it and send it as one `reset` frame — the
/// tmux wiki leaves the initial paint to the client ("for example using
/// capture-pane"); iTerm2 does the same. See TROUBLESHOOTING §3.
public enum ScreenPrimer {
    /// Cap on replayed history lines (the normal buffer only; the alternate
    /// screen has no scrollback).
    public static let maxHistoryLines = 2000

    /// Which line `capture-pane -S` should start from for this pane.
    public static func captureStart(for state: TmuxFormats.PaneState) -> Int {
        state.alternateScreen ? 0 : -min(state.historySize, maxHistoryLines)
    }

    public static func frame(state: TmuxFormats.PaneState, capture: String?) -> [UInt8] {
        var esc = "\u{1b}[?1049l\u{1b}[H\u{1b}[2J\u{1b}[3J"   // leave any alt buffer, clear screen + scrollback
        if state.alternateScreen { esc += "\u{1b}[?1049h" }
        if state.mouseReporting {
            esc += "\u{1b}[?1000h\u{1b}[?1002h"
            if state.mouseSGR { esc += "\u{1b}[?1006h" }
        }
        if state.applicationCursorKeys { esc += "\u{1b}[?1h" }   // DECCKM
        esc += "\u{1b}[H"
        guard let capture else { return Array(esc.utf8) }

        // capture-pane separates lines with a bare LF (which keeps the column;
        // the emulator needs CR too) and ends with one. The last `height`
        // lines are the visible screen, blank rows included — they are kept
        // so the final printed line is the pane's bottom row, which makes the
        // cursor restore below independent of the emulator's own height.
        var lines = capture.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        esc += lines.joined(separator: "\r\n")
        // Restore the cursor: up from the bottom row, then the column (CHA).
        let up = max(0, state.height - 1 - state.cursorY)
        if up > 0 { esc += "\u{1b}[\(up)A" }
        esc += "\u{1b}[\(state.cursorX + 1)G"
        return Array(esc.utf8)
    }
}

/// Keys go to tmux as `send-keys -H <hex> <hex> …`: ONE hex number per key,
/// so each byte is its own 2-digit argument (a concatenated hex string is
/// silently dropped — verified). Lines are chunked to stay well under tmux's
/// command-line limits.
public enum SendKeysEncoder {
    public static let bytesPerLine = 128

    public static func lines(for bytes: [UInt8], paneID: String?) -> [String] {
        guard !bytes.isEmpty else { return [] }
        let prefix = paneID.map { "send-keys -H -t \($0)" } ?? "send-keys -H"
        var result: [String] = []
        var index = 0
        while index < bytes.count {
            let chunk = bytes[index..<min(index + bytesPerLine, bytes.count)]
            var line = prefix
            line.reserveCapacity(prefix.count + chunk.count * 3)
            for b in chunk { line += String(format: " %02x", b) }
            result.append(line)
            index += bytesPerLine
        }
        return result
    }
}
