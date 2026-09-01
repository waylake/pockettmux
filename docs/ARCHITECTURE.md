# Architecture — PocketTmux

*Status: design baseline for v1. Decisions are marked **[D#]** and cross-referenced with [TECH_STACK.md](TECH_STACK.md).*

## 1. Purpose

Let an iPhone display and drive `tmux` sessions that live on the user's Mac, using only the local Wi-Fi. The phone must feel like "another terminal of the Mac", not a remote shell: the same pane the Mac's terminals see is what the phone renders, with full tmux history/scrollback semantics preserved.

## 2. Goals / non-goals

**Goals (v1):**
- Attach to existing tmux sessions; create/detach/destroy from the phone
- Full ANSI rendering (colors, 256/TrueColor, cursor, resize) with low perceived latency on LAN
- Survive: Wi-Fi drop + app background/foreground, Mac sleep/wake, tmux server restart
- One small, self-contained Mac agent; zero system-level installs beyond `tmux`

**Non-goals (v1):**
- Working outside the LAN (VPN/Tailscale) — the protocol is LAN-friendly but not its job in v1
- iPad layout, multitasking, multiple Macs, per-client tmux panes (phone sees sessions, like an attach)
- File transfer, SFTP, shell-on-phone

## 3. System overview

```
  iPhone — PocketTmux.app (Swift, SwiftUI)            Mac
┌──────────────────────────────────────┐               ┌──────────────────────────────────────────────┐
│ UI layer (SwiftUI)                       │               │ Agent (macOS daemon, Swift)                   │
│   Connection screen · Session list         │               │   ws://<mac>:7681  (WebSocket server)            │
│ Terminal layer                                   │   Wi-Fi LAN    │   ├─ Protocol: parse/emit JSON frames         │
│   TerminalView — SwiftTerm (VT100/xterm)     │  ◀────────────▶  │   ├─ tmux bridge: control mode (tmux -CC)     │
│ Transport layer                                  │   ws (v1)      │   │    sessions/windows/panes → frames      │
│   WebSocket client (URLSessionWebSocketTask) │  (SSH v2)    │   └─ Auth: token · Config: port/token          │
└──────────────────────────────────────┘               └───────────────┬──────────────────────────────┘
                                                                                  │ control-mode channel
                                                                                  ▼
                                                              ┌──────────────────────────────────────┐
                                                              │ tmux server — source of truth            │
                                                              │  sessions → windows → panes → PTY → shell │
                                                              │  (Mac's own terminals attach here too)    │
                                                              └────────────────────────────────────────┘
```

**Component table**

| Component | Side | Technology (see TECH_STACK) | Responsibility |
|---|---|---|---|
| PocketTmux app | iPhone | SwiftUI, Swift | UX, settings, session list, input capture |
| TerminalView | iPhone | SwiftTerm (native terminal engine) | Parse ANSI/VT sequences → screen grid → draw |
| Transport (client) | iPhone | URLSessionWebSocketTask (stdlib) | Frame encode/decode, send/recv, reconnect backoff |
| Agent | Mac | Swift + SwiftNIO (WebSocket server) | LAN endpoint; protocol; owns the tmux channel; auth |
| tmux bridge | Mac | `tmux -CC` control mode | Map session/window/pane events + pane output → frames |
| tmux server | Mac | tmux 3.7+ | Sessions/windows/panes, history, local client attach |

## 4. Request flow

Terminology: **frame** = one JSON message over the WebSocket (envelope in §5). **Screen state** = the visible grid of the focused pane (plus scrollback), owned by tmux.

### 4.1 First attach (app launch → visible pane)

```
Phone                              Agent                            tmux
  │ 1. app launch: read stored host:port + token (Keychain)    │
  │ 2. ws connect ws://host:7681 ─────────────▶                 │
  │ 3. hello {v, caps, auth:token} ────────────▶                │
  │ 4. ◀────────────────── hello.ack {agent:"0.1", tmux:"3.7c", caps} │
  │ 5. session.list {} ─────────────────────────────────▶  list-sessions
  │ 6. ◀──────────── session.list {sessions:[{id:"$1",name:"work",attached:2}]} │
  │ 7. user taps "work" → session.attach {id:"$1"} ──────────▶  attach (control client)
  │ 8. ◀────────── screen {mode:"reset", data:"<full pane, ANSI>"}  (first full paint)
  │ 9. TerminalView writes the reset buffer → renders; status "Connected"
  │    (tmux events: sessions-changed/window-… → session.changed frames keep the list fresh)
```

### 4.2 Keypress (phone input → shell in the Mac pane)

```
 1.  User taps a key (virtual keyboard) or uses a hardware keyboard.
 2.  SwiftUI/UIView key event → Transport.onKey → build frame:
       {"v":1,"id":42,"type":"input","payload":{"data":"h"}}        // printable
       {"v":1,"id":43,"type":"input","payload":{"data":"\r"}}         // enter
       {"v":1,"id":44,"type":"input","payload":{"data":"\u001b[A"}}       // up arrow
 3.  URLSessionWebSocketTask.send(.string(frame)) → Wi-Fi → agent.
 4.  Agent decodes; the tmux bridge sends the key to the *active pane*:
       tmux send-keys -t %7 h            // or, in a persistent control channel, the equivalent write
 5.  The shell/program in the pane receives the key (tmux behaves exactly as for a local client).
 6.  Paste: "paste" {data, bracketed:true} → tmux bracketed-paste semantics (no per-key storms).
```

### 4.3 Screen update (pane output → phone render)

```
 1.  The program in the pane prints (or the cursor moves, or vim redraws).
 2.  tmux (control mode) streams the change to the control client:
       %output %7 <new/changed lines, with octal-escaped control chars>
     (event-driven — no polling; this is why control mode is chosen over capture-pane polling [D4])
 3.  Agent wraps: screen {session:"$1", pane:"%7", mode:"update", data:"<ANSI delta>"} → WebSocket.
 4.  Phone Transport receives → decodes → hands ANSI bytes to TerminalView.
 5.  SwiftTerm parses (SGR colors, cursor moves, scroll, alt-screen…) and updates its grid.
 6.  SwiftUI/UIKit renders the changed rows; user sees the output (typical LAN latency ≈ single-digit ms).
```

### 4.4 Resize (phone rotation / split view → pane size)

```
 1.  UI size changes (rotation, iPad multitasking, app resize).
 2.  Terminal layer computes new cols/rows from view size ÷ cell metrics.
 3.  App sends resize {cols,rows}; agent runs tmux resize-pane -t %7 -x Cols -y Rows
     (and, per the control-mode docs, keeps the control client's own size in sync via refresh-client -C so future frames are coherent).
 4.  tmux reflows the pane (SIGWINCH to the shell); the next screen frames reflect the new size.
```

### 4.5 Reconnect (Wi-Fi drop → back online → seamless resume)

```
 1.  Wi-Fi drops / Mac sleeps; ws ping fails or socket errors → Transport marks "Reconnecting…".
 2.  Exponential backoff with jitter (e.g. 1s → 2s → 4s → … cap 30s); the TerminalView keeps the last frame (no blank screen).
 3.  Network returns: ws reconnect + hello (token from Keychain) → hello.ack.
 4.  Agent re-attaches the control client to the session (tmux was still running; the pane state is in tmux, not in the phone).
 5.  Agent sends screen {mode:"reset", data:"<full current pane>"} → phone does a full repaint → resumes live updates.
 6.  (If the *tmux server* died: session.changed {destroyed} frames; app shows "Session ended"; user re-creates/attaches.)
```

### 4.6 Session lifecycle (multi-client note)

- `session.create {name, cwd?, cmd?}` → agent runs `tmux new-session -d -n main [cmd]` → `session.created`; user can then attach.
- `session.detach` → control client leaves; the session keeps running (other clients — including the Mac's own `tmux attach` — are unaffected).
- `session.destroy {id}` → `tmux kill-session` → `session.destroyed`.
- **Multiple clients are a tmux native feature**: the Mac terminal and the phone can attach to the *same session simultaneously* (like tmux's own multi-attach). v1 assumes one phone client + however many local Mac clients; contention rules (e.g. two phones driving one pane) are documented as a known simplification, not a bug.

## 5. Transport protocol (v1)

**Framing.** WebSocket **text** frames, one JSON object per frame. (Binary frames are reserved for a future compact protocol; v1 is JSON-first for debuggability on the LAN.)

**Envelope.**

```json
{"v": 1, "id": 42, "type": "input", "ts": 1727760000.123, "payload": {"data": "h"}}
```

- `v` — protocol version (1).
- `id` — monotonically increasing per sender; the receiver echoes it in responses so requests/correlate (e.g. `session.list` → its response shares the id).
- `type` — message name (tables below).
- `ts` — sender timestamp (seconds); used for latency stats, not for correctness.
- `payload` — type-specific object.

**Client (phone) → server (agent)**

| type | payload | Meaning |
|---|---|---|
| `hello` | `{v, caps:[...], auth:"<token>"}` | First frame after ws connect; starts auth + capability negotiation |
| `session.list` | `{}` | Ask for current sessions |
| `session.create` | `{name, cwd?, cmd?}` | Detached new session |
| `session.attach` | `{id}` | Attach the control client (→ first `screen` reset) |
| `session.detach` | `{id}` | Detach |
| `session.destroy` | `{id}` | Kill |
| `input` | `{data:"<string>"}` | Keystroke(s): printable char, or escape (`\r`, `\u001b[A`, `\u0001`…) |
| `paste` | `{data:"<text>", bracketed:true}` | Paste with tmux bracketed-paste semantics |
| `resize` | `{cols, rows}` | Set pane size |
| `ping` | `{}` | Keepalive / latency probe |

**Server (agent) → client (phone)**

| type | payload | Meaning |
|---|---|---|
| `hello.ack` | `{agent:"0.1.0", tmux:"3.7c", caps:[...]}` | Auth OK + versions |
| `session.list` | `{sessions:[{id,name,attached,created}]}` | Response to list |
| `session.created` / `session.changed` / `session.destroyed` | `{session:{id,name,...}}` | tmux events (new session, renamed/resized, killed) → keep the phone's list live |
| `screen` | `{session, pane, mode:"reset"|"update", data:"<ANSI>"}` | Full pane reset (attach, reconnect, major redraw) or incremental update (live output) |
| `exit` | `{code, signal?}` | The program in the pane exited (shell quit) |
| `pong` | `{}` | Response to ping |
| `error` | `{code, message}` | Protocol/auth/tmux error (e.g. bad token, unknown session) |

**Design notes.**

- **tmux owns the screen, not the client.** The phone re-parses ANSI that represents the pane; it does not independently model the "real" terminal. Scrollback/scroll on the phone is a *view* (a cache of what tmux showed); the tmux history is the truth. This keeps one source of screen truth and makes "two clients, same pane" sane.
- **Why control mode (`-CC`) over `capture-pane` polling.** Control mode is tmux's own programmatic-client interface: it streams pane output (`%output`), session/window/pane lifecycle events, and handles the control client's sizing (`refresh-client -C`). It is event-driven (no 10–20 Hz screen scraping), preserves exactly what the pane produced (with octal-escaped control characters), and is what IDE/integration clients use. `send-keys` + `capture-pane` polling is the simpler fallback (and remains the reference for tmux < 3.7 or minimal agents), but it wastes CPU and can tear mid-frame.
- **Backpressure & coalescing.** A fast `yes`/`cat` can out-pace the phone. The agent coalesces consecutive `screen` updates into one frame per flush interval (target ≈ one display frame, ~16 ms) and applies a bounded outbound queue that drops the *oldest* coalesced frame when over budget (the next frame still converges, since updates are diffs toward the same tmux state). The phone side applies frames in order; a `reset` always wins.
- **Auth (v1).** The agent generates/holds a random **token** (shown in its log/config on first run; stored in the Mac keychain). The phone's first-run flow is *paste the token once* → Keychain. Subsequent `hello` carry it. This is deliberately LAN-simple: trust = same Wi-Fi + token. (Documented simplification: no TLS in v1 — see failure modes.)

## 6. Key technical decisions & alternatives

| # | Decision | Choice | Why (2026-09 baseline) | Alternative considered | Revisit when |
|---|---|---|---|---|---|
| D1 | Terminal engine (phone) | **SwiftTerm** (v1.19.0, MIT, Swift) | Native VT100/xterm engine with a UIKit `TerminalView`; battle-tested in shipping SSH clients (Secure Shellfish, La Terminal, CodeEdit); active (release 2026-08-18; push 2026-08-31); SPM; optional Metal GPU renderer for scale | xterm.js in a WKWebView (@xterm/xterm 6.0.0, MIT) | Ship a PWA / web shell instead of native; or the app becomes "mostly a webview" |
| D2 | Transport | **WebSocket** (phone: URLSessionWebSocketTask; agent: SwiftNIO + NIOWebSocket) | Zero-config over LAN; trivially debuggable (curl/wscat/browser); same stack lets the P0 PWA and the native app share the agent; stdlib client on iOS | SSH (libssh2 1.11.1 / BSD; or swift-nio-ssh) | Need encryption without a LAN trust assumption; want to reuse an existing sshd; agent becomes "just another sshd target" |
| D3 | tmux on the Mac | **tmux 3.7c** (MIT) | The user's existing multiplexer; sessions/windows/panes + history are the source of truth; huge ecosystem; brew-managed; 3.7 is the current stable line (released 2026-08) | GNU screen; a plain shell per session | tmux falls short of a needed feature (rare) |
| D4 | tmux bridge | **Control mode (`tmux -CC`)** | Event-driven `%output` + lifecycle events; designed for programmatic/IDE clients; avoids `capture-pane` polling and torn frames; stable IDs (`$session`, `@window`, `%pane`); sizing via `refresh-client -C` | `send-keys` + `capture-pane` polling loop | tmux too old for the control features used; a minimal agent that only needs input + periodic snapshots |
| D5 | Agent implementation | **Swift + SwiftNIO** (macOS daemon; menu-bar app later) | One language across agent + app; NIO is Apple's production networking stack (NIOWebSocket included; swift-nio 2.102.0, 2026-09); strong concurrency model for a long-lived socket; can grow (TLS, multiple clients) without a rewrite | C single-binary (gotty/ttyd-style) or Go agent | The agent gets big enough that a dedicated runtime is worth it; or we want a zero-dependency static binary |
| D6 | Phasing: PWA vs native | **P0 = ttyd + xterm.js PWA; P1+ = native Swift app** | Validates the whole loop (LAN + tmux + terminal + transport) in ~2 minutes with zero native code; gives an instant usable artifact; the native app then replaces the webview with SwiftTerm while keeping the same agent/protocol | Go straight to the native app | The P0 path proves something the native path wouldn't (e.g. protocol shape) — by then the protocol is already locked |
| D7 | Agent auth | **Random token, LAN-only** (no TLS in v1) | Simplest secure-enough for a single-user home LAN; token in phone Keychain + Mac keychain; documented as a simplification | TLS (self-signed or LAN CA) / SSH tunneling | Multi-user LANs; carrying secrets that outlive the Wi-Fi; moving off the home network |

## 7. Failure modes & edge cases

| # | Failure / edge case | v1 behavior | Mitigation / design response |
|---|---|---|---|
| F1 | **Mac sleeps** (lid close / idle) | Agent stops answering; phone shows Reconnecting | Agent takes an `IOPMAssignment`/`caffeinate`-style assertion while a client is attached; docs recommend "Prevent sleep when disconnected from power" for headless use |
| F2 | **Router AP/client isolation** | Mac and phone can't see each other even on the same SSID | Quick-start tells the user to disable "AP isolation / client isolation"; the P0 test (open `http://mac-ip:7681`) doubles as a diagnosis |
| F3 | **mDNS / 2.4 GHz vs 5 GHz** | `.local` names may not resolve across bands | v1 uses plain **IP + port** (the agent prints a QR/code with its address on startup); Bonjour is a later nicety, not a dependency |
| F4 | **App backgrounded** (lock screen) | Socket may be torn down by iOS; tmux keeps running | On foreground: Transport reconnects + `screen` reset (flow 4.5); long-term sessions are tmux's job, the phone is a view |
| F5 | **tmux server restart** (Mac reboot, `kill-server`) | Attached sessions vanish mid-session | `session.destroyed` frames update the list; app shows "Session ended — reattach"; agent re-spawns its control client on demand (the server is the truth, not the agent) |
| F6 | **Two clients drive one pane** (phone + Mac terminal attached) | Both see the same output; inputs interleave as tmux delivers them | Documented as a *feature* (tmux multi-attach), not a race; v1 doesn't add per-client input locks (a v2 concern if it bites) |
| F7 | **Control-mode output isn't always valid UTF-8** (octal-escaped control chars) | Naive string decoding can garble | The agent decodes the octal escapes into bytes *before* framing; the phone's terminal engine (SwiftTerm) consumes bytes, not "nice strings" — the protocol carries `data` as an escape/byte-safe string |
| F8 | **Fast output floods the socket** (`cat bigfile`, `yes`) | Phone lags or drops frames | Backpressure/coalescing (§5): bounded queue, drop-oldest, 16 ms flush; a `reset` frame always re-converges the screen |
| F9 | **Token leaks on the LAN** | Another device could impersonate the phone | v1: single-user home LAN + random high-entropy token (documented simplification, D7); v2: per-client tokens / optional TLS |
| F10 | **Protocol version drift** (old phone, new agent) | Unknown frame types | `hello`/`hello.ack` exchange `caps`; each side ignores unknown *types* gracefully and errors only on malformed envelopes; `v` lets a future binary protocol coexist |

## 8. Open questions

1. **Sixel / graphics on the phone** — SwiftTerm supports Sixel & imgcat/Kitty; do we render them in v1 or pass them through invisibly?
2. **tmux mouse passthrough** — if a pane app wants the mouse, does the phone's touch map to tmux mouse events, or stay keyboard-only in v1?
3. **iCloud/KVS or a local config store** for the agent address (so the phone remembers *which* Mac, not just the token)?
4. **Bonjour/mDNS discovery** — nice-to-have auto-configure; v1 is manual IP.
5. **Binary protocol** — JSON v1 is debuggable; a compact binary v2 for high-throughput output is plausible. Keep the envelope.
6. **Per-client input locks** — if two clients drive one pane, is a "typing lock" a v2 feature or unnecessary?

## 9. References

- tmux Control Mode — <https://github.com/tmux/tmux/wiki/Control-Mode> (`-C` vs `-CC`, `%output`, `refresh-client -C`)
- tmux 3.7c — <https://github.com/tmux/tmux/releases>
- SwiftTerm (iOS `TerminalView`, engine, Metal, OSC 8, Sixel) — <https://github.com/migueldeicaza/SwiftTerm> · API docs <https://migueldeicaza.github.io/SwiftTerm/documentation/swiftterm/>
- xterm.js (`@xterm/xterm`, add-ons) — <https://xtermjs.org> · <https://github.com/xtermjs/xterm.js>
- SwiftNIO / NIOWebSocket — <https://github.com/apple/swift-nio>
- libssh2 — <https://github.com/libssh2/libssh2> · swift-nio-ssh — <https://github.com/apple/swift-nio-ssh>
