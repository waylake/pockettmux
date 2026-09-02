# PocketTmux — Product Plan (v1.0)

> One line: **your Mac's tmux sessions on your iPhone, as the same shell.** Not a
> remote shell — "another terminal of the Mac". Quality bar: production.
> Design: a Japanese dev-tool sensibility — quiet, mono-spaced, restrained
> (the interface language is English; see §2.3). Architecture baseline:
> docs/ARCHITECTURE.md.

## 1. What this build delivers

| | v0.1 (was) | **v1.0 (this build)** |
|---|---|---|
| iPhone app | connection-screen skeleton | real terminal (SwiftTerm) + session management |
| Mac side | — | native agent `pockettmuxd` (pure Swift, zero deps) |
| Transport | — | WebSocket + token auth |
| Sessions | — | list / create / attach / detach / delete (confirmed) |
| Input | — | raw bytes → `tmux send-keys -H`, ~16 ms coalescing |
| Screen | — | tmux control-mode (`-CC`) streaming, resize, reconnect (exponential backoff) |

**Verified facts that shaped the design** (tested against tmux 3.7c):
`tmux -CC` stdin is a *command stream*, not keys. Keys go via
`send-keys -H <hex-per-byte>` (raw bytes; prefix/vi bindings work), resize via
`refresh-client -C <w>x<h>`, pane output arrives as `%output <pane> <octal-escaped>`
frames, and tmux only repaints when the control client's size *changes*
(attach forces `2x2 → 80x24` to get an initial full paint).

## 2. Product direction

### 2.1 A terminal for the LLM era (pi, Claude Code, cursor, …)
The user runs a coding agent in tmux. The agent asks questions, offers
choices, and waits for input — that interaction must work from the phone.
v1 is therefore a *two-way input terminal*, not a read-only monitor:

- Accessory keyboard: Esc / Tab / Ctrl / Alt / arrows / PgUp·PgDn / Home·End /
  F1–F12 (SwiftTerm built-in) → driving LLM prompts (menu movement, mode
  escape) works.
- Swipe-to-scroll reads the agent's conversation history from the phone: the
  drag becomes SGR mouse-wheel events, which pi (in `fullscreen` TUI mode) and
  Claude Code parse internally to scroll their transcript (see
  TROUBLESHOOTING §3).
- Input echoes immediately; latency is minimized by agent-side coalescing.
- A dismiss-keyboard key lives on the accessory bar.

### 2.2 Screens (3-step navigation)

```
1. Connect — host/port/token, Keychain-persisted, one-tap resume
2. Sessions — tmux session list / create / delete(confirm) / attach
3. Terminal — SwiftTerm full-screen + status bar + accessory keyboard
```

### 2.3 Design language — Japanese dev-tool sensibility, English copy

- **Name**: PocketTmux. Mono small-caps section labels (e.g. `SESSION LIST`),
  no decorative noise: no gradients, no big shadows, no emoji, no inflated
  corner radius. Quiet hierarchy, standard forms.
- Palette (traditional Japanese colors on terminal ink):
  - 墨 sumi background `#0B0D11` · 藍墨 aizumi surface `#12161D`
  - 和紙 washi text `#E4E0D4` · 鼠色 nezumi mute `#8A8B8D`
  - 朱 shu accent (active/attach) `#E0584C` · 山吹 yamabuki warn `#E0A44C`
  - 萌葱 moegi success/connected `#43A885` · 藍 ai info `#4A6FA5`
- Type: data/status in monospace (SF Mono), body in SF. All copy English.

## 3. Protocol (v1, matches ARCHITECTURE §5)

Text WS frames, JSON; `data` fields are **base64** (byte-safe, F7).

- C→S: `hello{auth}` `session.list` `session.create{name}` `session.attach{id}`
  `session.detach` `session.destroy{id}` `input{data}` `resize{cols,rows}` `ping`
- S→C: `hello.ack{agent,tmux,caps}` `session.list{sessions}` `session.attached`
  `screen{mode:reset|update,data}` `exit{code,message}` `error{code,message}` `pong`

Auth: token in the first `hello`; failure → `error` + close. Session-list
pushes on `%sessions-changed` keep the phone list live.

## 4. Agent `pockettmuxd` (macOS; deps: Foundation + Network only)

```
NWListener (WebSocket upgrade, 0.0.0.0:7682) + mandatory token
  └─ per-connection: auth → command dispatch
       └─ TmuxControl (forkpty → "tmux -CC attach -t <id>")
            ├─ reader: %-frame parser (octal unescape) → active-pane screen frames
            ├─ writer: send-keys -H hex (16 ms coalescing) / refresh-client -C
            └─ events: %session-changed → attach confirmed, %window-pane-changed → activePane
```

- List/create/destroy: short `tmux ls -F` / `new-session -d` / `kill-session`
  subprocesses.
- Token: `~/.pockettmux/token`, generated once, reused (phone stores a copy).
- Port 7682 (7681 stays reserved for the P0 ttyd path). 0.0.0.0 + token covers
  LAN and Tailscale identically.

## 5. iOS app (SwiftUI + SwiftTerm, iOS 16+)

- `AgentClient`: URLSessionWebSocketTask, async receive loop, exponential
  reconnect (1 s → 30 s), auto-re-attach after reconnect, live session list.
- `TerminalHost`: SwiftTerm `TerminalView` (UIViewRepresentable); resize →
  agent; keys → base64 input frames; theme applied.
- State machine: Connect → list → attach → (drop) → Reconnecting… →
  re-attach (reset, full repaint).
- Credentials in Keychain; last session remembered.

## 6. Run

```sh
cd App && xcodegen generate && open PocketTmux.xcodeproj   # build both targets
# agent
./scripts/start-agent.sh    # builds pockettmuxd if needed, runs it, logs to ~/.pockettmux/agent.log
# phone: Connect → host=<mac ip>, port=7682, token=`cat ~/.pockettmux/token`
```

## 7. Non-goals for v1
- Bidirectional scrollback upload (phone is a *view*; tmux history is the truth).
- File transfer; bracketed-paste channel (v1 handles large text as input).
- iPad multitasking, multiple Macs, menu-bar agent UI (launchd: see README).
- TLS (LAN + token; documented simplification, ARCHITECTURE F9).
- v1.1+ : notifications, launch-at-login, Sixel decision, pane picker for
  multi-pane windows (known simplification — the active pane wins while the
  window is live; interleave only during switch, see TmuxControl route()).

## 8. Test strategy — what was run
- Unit tests: ls parser, octal unescape, hex codec, control-frame parser,
  wire codec — all in PocketTmuxTests (shared AgentCore).
- Headless E2E: URLSession WebSocket client → hello → list → attach → resize →
  input → marker echo in screen frames → detach (exit 0).
- Final probe against the running agent on a real user session: attach to
  session `12`, type `echo POCKET_OK`, marker observed, clean detach.
- On-device: manual 3-screen flow (Connect → Sessions → Terminal).