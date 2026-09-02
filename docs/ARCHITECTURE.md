# Architecture — PocketTmux

*Status: v1.0 as built. Decisions are marked **[D#]** and cross-referenced with [TECH_STACK.md](TECH_STACK.md); the wire format is specified in [PROTOCOL.md](PROTOCOL.md); real failures and their fixes are in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).*

## 1. Purpose

Let an iPhone display and drive `tmux` sessions that live on the user's Mac, over the local network or Tailscale. The phone must feel like "another terminal of the Mac", not a remote shell: the same pane the Mac's terminals see is what the phone renders, with tmux's own history/scrollback semantics preserved.

## 2. Goals / non-goals

**Goals (v1):**
- Attach to existing tmux sessions; create/rename/kill sessions and windows from the phone
- Full ANSI rendering (256/TrueColor, cursor, resize, alternate screen, mouse reporting) with low perceived latency
- Survive Wi-Fi drops, app background/foreground, Mac sleep/wake, tmux server restart — and re-attach without a blank screen
- A Mac app anyone can install: menu bar, pairing by QR, launch at login; plus the same agent as a CLI
- Zero system-level installs beyond `tmux`

**Non-goals (v1):** iPad layout, multiple Macs at once, per-pane view in multi-pane windows (the active pane wins), file transfer, TLS (see D7).

## 3. System overview

```
 iPhone — PocketTmux.app                                  Mac
┌──────────────────────────────────┐                     ┌──────────────────────────────────────────────┐
│ SwiftUI                          │                     │ PocketTmux.app (menu bar)  ·  pockettmuxd    │
│  Macs · Sessions · Terminal      │   Wi-Fi / Tailscale │   ┌────────── PocketTmuxAgent ──────────┐    │
│ TerminalView (SwiftTerm)         │ ◀───── ws v2 ─────▶ │   │ AgentServer  NWListener + Bonjour    │    │
│ AgentClient (URLSessionWebSocket)│                     │   │ AgentConnection  auth · dispatch     │    │
│ BonjourBrowser · ProfileStore    │                     │   │ TmuxControl  tmux -CC on a pty       │    │
└──────────────────────────────────┘                     │   │ TmuxRunner   short tmux subprocesses │    │
             ▲                                           │   └───────────────┬──────────────────────┘    │
             │  PocketTmuxKit: WireCodec · TmuxControlParser · TmuxFormats · PairingPayload             │
             └────────────────────────── shared Swift package ──────────────┼──────────────────────────┘
                                                                            ▼
                                                        ┌──────────────────────────────────────┐
                                                        │ tmux server — source of truth        │
                                                        │ sessions → windows → panes → PTY     │
                                                        │ (the Mac's own terminals attach too) │
                                                        └──────────────────────────────────────┘
```

| Component | Where | Responsibility |
|---|---|---|
| `PocketTmuxKit` | `App/PocketTmuxKit/Sources/PocketTmuxKit` | Protocol v2 codec, control-mode line parser, `-F` format parsers, name validation, pairing URL |
| `PocketTmuxAgent` | `…/Sources/PocketTmuxAgent` | `AgentServer` (WebSocket listener, Bonjour, snapshot for UIs, sleep assertion), `AgentConnection` (per phone: auth, command dispatch, 16 ms output coalescing), `TmuxControl` (one `tmux -CC` per attached phone), `TmuxRunner` (list/create/kill/rename, pane state, capture, paste), `ScreenPrimer`, `TokenStore`, `AgentLog`, `HostInfo` |
| PocketTmux for Mac | `App/macOS` | Hosts an `AgentServer`; menu-bar panel, pairing window, settings, log; launch at login |
| `pockettmuxd` | `App/Daemon` | Same `AgentServer` behind flags; for headless Macs, scripts and CI |
| PocketTmux for iPhone | `App/iOS` | Profiles (Keychain), Bonjour browsing, QR/deep-link pairing, sessions, windows, terminal (SwiftTerm), reconnect |

**One agent process, one control client per attached phone.** Each `AgentConnection` owns its own `TmuxControl`; two phones on the same Mac are two tmux clients, which is exactly tmux's multi-attach model.

## 4. Request flow

Terminology: **frame** = one JSON message over the WebSocket (PROTOCOL §1). **Screen state** = the visible grid of the active pane (plus scrollback), owned by tmux.

### 4.1 Pairing (once per Mac)

```
Mac app: Pair iPhone…  →  QR = pockettmux://pair?host=100.67.189.40&port=7682&token=…&name=MacBook
Phone: Macs → + → Scan   →  ProfileStore.save(profile)  →  connect
   (same Wi-Fi: the Mac also appears under NEARBY MACS via Bonjour; tap Pair to prefill host/port)
```

### 4.2 Attach (tap a session → visible pane)

```
Phone                                   Agent                                   tmux
 │ ws connect ws://host:7682/ws ──────▶ │                                        │
 │ hello{v:2,auth,client} ────────────▶ │ token ok → hello.ack{host,caps}        │
 │ session.list ──────────────────────▶ │ tmux list-sessions -F … ──────────────▶│
 │ ◀── session.list{sessions}           │                                        │
 │ session.attach{id:$1,cols:45,rows:27}▶│ forkpty: tmux -CC attach -t $1 ──────▶│
 │                                      │ ◀── %session-changed $1 work           │
 │                                      │ resize-window -x45 -y27 + window-size manual (pin)
 │                                      │ display-message -p '#{pane_id}…cursor…' · capture-pane -p -e
 │ ◀── session.attached{session,windows}│                                        │
 │ ◀── screen{reset, primed frame}      │  (ScreenPrimer: alt/mouse/DECCKM escapes + content + cursor)
 │ ◀── screen{update,…} ◀── … ◀──────── │ ◀── %output %7 …  (only the active pane's output is forwarded)
```

### 4.3 Keypress

```
SwiftTerm.send(bytes) → AgentClient.sendInput → input{data:base64}
   → AgentConnection → TmuxControl.pendingInput (flushed every 16 ms)
   → "send-keys -H -t %7 1b 5b 41" on the control client's stdin (one hex per key, 128 keys per line)
   → the program in the pane sees exactly what a local keyboard would send
```

Paste is separate (`paste{text}` → `load-buffer` + `paste-buffer -p`) so tmux applies bracketed paste iff the pane asked for it.

### 4.4 Windows

```
window.select{@2} → select-window -t @2 → %session-window-changed $1 @2
   → TmuxControl.showActivePane(): pin @2 to the phone size, re-read pane state, capture, screen{reset}
   → (60 ms later) windows{sessionID,windows} from list-windows
```
The same path runs when the *Mac user* switches windows or panes (`%window-pane-changed`), so both clients always look at the same pane.

### 4.5 Resize

Phone `sizeChanged` → `resize{cols,rows}` (agent debounces 250 ms) → `resize-window -t @w -x -y` + `refresh-client -C WxH`. The window stays pinned (`window-size manual`) for the duration of the attach and is unpinned on detach so the Mac client re-asserts its size (TROUBLESHOOTING §2).

### 4.6 Reconnect

```
socket error / no pong for 15 s → status Reconnecting… (the last frame stays on screen)
backoff 1s·2s·4s… ≤30s ±20% jitter → ws connect → hello → hello.ack
→ AgentClient re-sends session.attach{id, cols, rows} → screen{reset} full repaint → live again
tmux server died meanwhile → session.detached{sessionKilled} → "Session ended on the Mac" → Sessions
```

### 4.7 Session lifecycle

`session.create/rename/kill` are short `tmux` subprocesses; every change (from the phone, the Mac app, or a terminal on the Mac via `%sessions-changed`) results in a `session.list` push to each connected phone and an `onSessionsChanged` callback to the Mac app. Detaching leaves the session running for the Mac's own clients.

## 5. Transport protocol

Specified in [PROTOCOL.md](PROTOCOL.md). Design notes:

- **tmux owns the screen, not the client.** The phone re-parses ANSI that represents the pane; it does not model the "real" terminal. On-phone scrollback is a view cache; tmux history is the truth.
- **Control mode over `capture-pane` polling [D4].** Event-driven `%output` + lifecycle events, stable ids, no torn frames. The one thing control mode does *not* do — the initial paint — the agent does with `capture-pane`, as the tmux wiki suggests and iTerm2 does.
- **Coalescing & backpressure.** Pane output is batched into ~16 ms `screen{update}` frames; above 512 KiB the buffer is flushed immediately. A `reset` frame drops anything still buffered (it would predate the repaint).
- **Auth.** One random 32-char token per Mac in `~/.pockettmux/token` (0600), compared in constant time, presented in the first frame; wrong → `error{auth}` and close. Trust = same network + token (D7).
- **Forward compatibility.** Unknown frame types are ignored; `hello.v` is strict.

## 6. Key technical decisions & alternatives

| # | Decision | Choice | Why | Alternative considered | Revisit when |
|---|---|---|---|---|---|
| D1 | Terminal engine (phone) | **SwiftTerm** 1.x (MIT) | Native VT100/xterm engine with a UIKit `TerminalView`, accessory keyboard, mouse reporting, alt screen; shipping in several SSH clients | xterm.js in a WKWebView | The app becomes "mostly a webview" |
| D2 | Transport | **WebSocket**, JSON text frames (phone: `URLSessionWebSocketTask`; agent: `NWListener` + `NWProtocolWebSocket`) | Zero-config on LAN/Tailscale; debuggable with a 100-line Python client (`scripts/check-attach-prime.py`); stdlib on both ends | SSH (libssh2 / swift-nio-ssh) | Encryption without the LAN trust assumption (v1.2 TLS is the planned path) |
| D3 | tmux | **tmux 3.7c** | The user's multiplexer; sessions/windows/panes/history are the truth; stable ids | GNU screen; a bespoke multiplexer | Never |
| D4 | tmux bridge | **Control mode (`tmux -CC`)** on a pty + `capture-pane` priming | Event-driven; exact bytes; sizing via `refresh-client -C` | `send-keys` + `capture-pane` polling | tmux too old for the control features |
| D5 | Agent implementation | **Swift + Network.framework**, one library (`PocketTmuxAgent`) hosted by a menu-bar app *and* a CLI | Zero third-party deps; one language across the repo; `NWListener` gives WebSocket + Bonjour for free; the same binary logic for GUI and headless | SwiftNIO (planned in v0.1) — more moving parts for one socket; Go/C agent — second language | The agent needs TLS termination or thousands of clients |
| D6 | Repo layout | One repo, XcodeGen project, **local SPM package** for shared code | Protocol/parsers cannot drift between the two apps; `swift test` runs the package tests in seconds without a simulator | Copying sources into each target (v0.1 did this) | Never |
| D7 | Agent auth | **Random token, no TLS in v1** | Simplest secure-enough for a single-user home network / Tailscale (which is already encrypted); token in `~/.pockettmux/token` and the phone's Keychain | TLS with a pinned self-signed cert | v1.2 (planned): pairing payload carries the cert fingerprint |
| D8 | Discovery | **Bonjour** (`_pockettmux._tcp`) + QR/deep link | Same-Wi-Fi Macs appear by themselves; the QR covers Tailscale and first-time token transfer | Manual IP only (v0.1) | Never |
| D9 | Mac app form | **Menu-bar app** (`MenuBarExtra`, `LSUIElement`), not sandboxed | The agent must exec the user's `tmux` and open a pty — impossible in the App Sandbox; a menu-bar app is the natural home for an always-on agent | Sandboxed App Store app with an XPC helper | App Store distribution becomes a goal (v2) |

## 7. Failure modes & edge cases

| # | Failure / edge case | v1 behaviour | Mitigation / design response |
|---|---|---|---|
| F1 | **Mac sleeps** | Agent stops answering; phone shows Reconnecting… | The agent holds a `PreventUserIdleSystemSleep` assertion while a phone is attached (Setting: Keep Mac awake); on wake the phone reconnects and re-attaches |
| F2 | **AP / client isolation** | Mac and phone can't see each other on the same SSID | Bonjour finds nothing → the Macs screen says so; Tailscale bypasses it entirely |
| F3 | **mDNS doesn't cross networks / Tailscale** | Nearby Macs list is empty | QR/link pairing carries the address; `HostInfo.addresses()` lists Tailscale first |
| F4 | **App backgrounded** | iOS tears the socket down | On foreground: reconnect immediately, `session.attach` again, full repaint |
| F5 | **tmux server restart / session killed on the Mac** | `%exit` from the control client | Agent checks `list-sessions`: gone → `session.detached{sessionKilled}` → phone shows "Session ended on the Mac" and returns to Sessions; otherwise `controlExited` → phone retries once |
| F6 | **Two clients drive one pane** | Both see the same output; input interleaves | tmux multi-attach is the feature; no per-client lock in v1 (ARCHITECTURE §8 Q3) |
| F7 | **Control-mode output isn't valid UTF-8** | Garbled screen if treated as text | Octal escapes decoded to bytes; `screen.data` is base64 |
| F8 | **Output floods** (`yes`, `cat big`) | Phone lags | 16 ms coalescing, 512 KiB immediate flush, `reset` on re-attach re-converges |
| F9 | **Token leaks on the network** | Another device could impersonate the phone | 32-char random token; Regenerate in Settings; TLS + per-device tokens planned (v1.2) |
| F10 | **Protocol drift** | Old app vs new agent | `hello.v` strict → clear "update the app" error; unknown frame types ignored |
| F11 | **Port in use / tmux missing** | Agent can't start | Surfaced in the Mac app header with Retry; tmux path overridable in Settings › Advanced |
| F12 | **Multi-pane window** | Only the active pane is shown; other panes' output is dropped | Documented simplification; pane picker planned (v1.1). Pane switches on the Mac re-prime the phone |
| F13 | **Duplicate attach** (row tap + screen appear) | Would respawn the control client → `%exit` → "session ended" | Deduped on both ends (TROUBLESHOOTING §1) |

## 8. Open questions

1. **Sixel / graphics** — SwiftTerm can render Sixel/imgcat; pass-through vs render is undecided.
2. **Binary protocol** — JSON v2 is debuggable; a compact binary `screen` frame is plausible for very chatty panes. Keep the envelope.
3. **Per-client input locks** — if two clients typing into one pane ever bites, add a "typing" lease.
4. **Notifications** — bell/activity → local notification while backgrounded (v1.1): agent-side `monitor-activity` vs client-side detection.

## 9. References

- tmux Control Mode — <https://github.com/tmux/tmux/wiki/Control-Mode>
- tmux 3.7c — <https://github.com/tmux/tmux/releases>
- SwiftTerm — <https://github.com/migueldeicaza/SwiftTerm>
- Network.framework `NWListener` / `NWProtocolWebSocket` — Apple Developer documentation
- iTerm2 tmux integration (priming with `capture-pane`, `window-size manual`) — <https://iterm2.com/documentation-tmux-integration.html>
