# PocketTmux wire protocol — v2

*The contract between the iPhone app and the agent (Mac app or `pockettmuxd`).
Implemented once in `App/PocketTmuxKit/Sources/PocketTmuxKit/Protocol/`
(`WireCodec`, `ClientMessage`, `ServerMessage`) and used by both ends; the
round-trip tests in `PocketTmuxKitTests/WireCodecTests.swift` pin the exact
JSON shapes below.*

## 1. Transport

- WebSocket over TCP, `ws://<host>:<port>/ws` (default port **7682**; 7681
  is reserved for the ttyd prototype path). The agent binds every interface,
  so LAN and Tailscale addresses work identically.
- **Text frames, one JSON object per frame**: `{"type": "<name>", "payload": {…}}`.
  Byte payloads are **base64** strings (control-mode output is not always
  valid UTF-8).
- Max message size 4 MiB. The agent replies to WebSocket pings with pongs.
- No TLS (documented simplification, see ARCHITECTURE F9): trust = same
  network + the token.

## 2. Handshake

The first client frame **must** be `hello`, within 10 s:

```json
{"type":"hello","payload":{"v":2,"auth":"<token>","client":{"name":"Doyeon's iPhone","model":"iPhone15,2","app":"PocketTmux iOS 1.0.0"}}}
```

- `v` must equal the agent's protocol version (2). Any other value →
  `error{code:"auth"}` + close (so an old app fails loudly, not silently).
- Wrong token → `error{code:"auth", message:"invalid token"}` then close.
- Success →

```json
{"type":"hello.ack","payload":{"host":{"name":"Doyeon's MacBook Pro","agent":"1.0.0","tmux":"tmux 3.7c"},"caps":["paste","windows","attach.size","bonjour"]}}
```

`caps` lets a client gate UI on agent features.

## 3. Client → agent

| type | payload | Effect |
|---|---|---|
| `session.list` | `{}` | Reply `session.list` |
| `session.create` | `{name}` | `tmux new-session -d -s name`; name validated (§6); then a `session.list` push |
| `session.rename` | `{id, name}` | `rename-session`; then `session.list` push |
| `session.attach` | `{id, cols?, rows?}` | Spawn `tmux -CC attach -t id`. With `cols/rows` the window is sized **before** the first paint. Replies `session.attached` then `screen{mode:"reset"}`. Re-attaching the already-attached session is a no-op. |
| `session.detach` | `{}` | Control client leaves; reply `session.detached{reason:"requested"}` |
| `session.kill` | `{id}` | `kill-session` (detaches first if attached); `session.list` push |
| `window.select` | `{id}` | `select-window`; followed by `screen{reset}` + `windows` push |
| `window.create` | `{}` | `new-window` in the attached session; becomes active → `screen{reset}` + `windows` |
| `window.kill` | `{id}` | `kill-window`; `windows` push |
| `window.rename` | `{id, name}` | `rename-window`; `windows` push |
| `input` | `{data: base64}` | Raw key bytes → `send-keys -H` to the active pane (coalesced ~16 ms) |
| `paste` | `{text}` | `load-buffer` + `paste-buffer -p` (bracketed paste iff the pane asked for it) |
| `resize` | `{cols, rows}` | `resize-window` + `refresh-client -C`; debounced 250 ms on the agent |
| `ping` | `{sentAt}` | Reply `pong{sentAt}` (RTT = now − sentAt) |

`id`s are tmux's own: sessions `$N`, windows `@N`, panes `%N`. The agent
rejects anything else with `error{code:"bad_frame"}` — user text is never
passed to `-t`.

## 4. Agent → client

| type | payload | When |
|---|---|---|
| `hello.ack` | `{host:{name,agent,tmux}, caps:[…]}` | After a valid `hello` |
| `session.list` | `{sessions:[{id,name,windows,attached,created,activity}]}` | Reply to `session.list`; **pushed** after create/rename/kill from any client and on tmux's `%sessions-changed` |
| `session.attached` | `{session:{…}, windows:[{id,index,name,active,panes}]}` | Control client attached |
| `session.detached` | `{reason}` | `requested` · `sessionKilled` (session gone: kill-session, server exit) · `replaced` (another attach on this connection) · `controlExited` (tmux -CC ended otherwise) |
| `windows` | `{sessionID, windows:[…]}` | Any window change while attached (add/close/rename/select/layout) |
| `screen` | `{mode:"reset"\|"update", data: base64}` | `reset` = a full repaint that starts with a clear (attach, window/pane switch, reconnect) — just feed it; `update` = live pane output, coalesced into ~16 ms frames |
| `pong` | `{sentAt}` | Reply to `ping` |
| `error` | `{code, message}` | `auth` · `bad_frame` · `unsupported` (unknown type after auth) · `tmux` (command failed) · `not_attached` |

Unknown frame **types** are ignored by both sides (forward compatibility);
only malformed envelopes are errors.

## 5. The `reset` frame (screen priming)

`tmux -CC` relays only output produced *after* the control client attached.
So on attach, window switch and pane switch the agent rebuilds the state
from tmux and sends one `reset` frame:

```
ESC[?1049l ESC[H ESC[2J ESC[3J          leave any alt screen, clear screen + scrollback
[ESC[?1049h]                            if #{alternate_on}
[ESC[?1000h ESC[?1002h [ESC[?1006h]]    if #{mouse_any_flag} [#{mouse_sgr_flag}]
[ESC[?1h]                               if #{keypad_cursor_flag} (DECCKM)
ESC[H <capture-pane -p -e, CRLF-joined> ESC[<n>A ESC[<x+1>G
```

`capture-pane` starts at `-min(#{history_size}, 2000)` on the normal buffer
(scrollback is replayed) and at `0` on the alternate screen (it has none).
The visible screen is printed in full, blank rows included, without a
trailing newline; the cursor is then moved **up** from the bottom row to
`#{cursor_y}` and to column `#{cursor_x}+1` — independent of the emulator's
own height. See `ScreenPrimer.swift` and TROUBLESHOOTING §3.

## 6. Names and validation

`TmuxNames.isValidName`: non-empty, ≤ 64 characters, printable, no `:` or
`.` (tmux target syntax), no leading `-` (would parse as an option). Both
ends apply it; the agent is authoritative.

## 7. Pairing payload

`pockettmux://pair?host=<ip>&port=<port>&token=<token>&name=<mac name>` —
shown as a QR by the Mac app / `scripts/pair.sh`, scanned or opened by the
iPhone app (URL scheme registered). `port` defaults to 7682; `name` is
optional. `PairingPayload` in the package encodes/decodes it.

## 8. Discovery

The agent advertises `_pockettmux._tcp` via Bonjour with TXT `name` (host
name) and `v` (protocol version). The iPhone browses it and resolves the
service to `host:port`. Tailscale does not carry mDNS — use the QR/link.

## 9. Version history

- **v2 (1.0.0)** — this document. Adds client identity in `hello`, host
  identity in `hello.ack`, windows (`session.attached.windows`, `windows`,
  `window.*`), `session.rename`, `paste`, attach size hint,
  `session.detached{reason}` (replaces `exit`), `ping{sentAt}`/`pong`,
  typed error codes, `session.kill` (was `session.destroy`), tab-separated
  tmux formats.
- **v1 (pre-1.0)** — `hello{v:1,auth}`, `session.list/create/attach/detach/destroy`,
  `input`, `resize`, `screen`, `exit`. Not accepted by v2 agents.
