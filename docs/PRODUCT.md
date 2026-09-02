# PocketTmux — Product (v1.0)

> One line: **your Mac's tmux sessions on your iPhone, as the same shell.**
> Not a remote shell — "another terminal of the Mac". Two apps, one protocol,
> tmux as the single source of truth. Quality bar: production.

## 1. Who it is for, and the job

A developer who lives in tmux on a Mac and wants to *keep driving* what is
running there from the phone: answer a coding agent (pi, Claude Code, cursor
agent) that is waiting for input, watch a build, nudge a long job, open a new
window and kick something off — without a laptop, over the home Wi-Fi or
Tailscale.

That shapes three non-negotiables:

1. **Two-way, low-latency input.** Every key the phone sends is a tmux key in
   the real pane (`send-keys -H`), including Esc/Ctrl/arrows/F-keys. The
   accessory keyboard is part of the product, not a nicety.
2. **The pane you see is the pane.** No screen scraping, no polling: tmux
   control mode streams the pane's output; the first frame is rebuilt from
   tmux's own per-pane state (alternate screen, mouse reporting, cursor keys,
   scrollback, cursor position) so a TUI that started hours ago looks right.
3. **Zero friction to pair.** Open the Mac app → *Pair iPhone…* → scan. Same
   Wi-Fi Macs also show up by themselves (Bonjour). Tailscale works with the
   QR/link.

## 2. The two apps

| | PocketTmux for Mac | PocketTmux for iPhone |
|---|---|---|
| Form | Menu-bar app (`LSUIElement`), macOS 14+ | iPhone app, iOS 16+ |
| Role | Hosts the agent (WebSocket + `tmux -CC`), pairing, settings, overview | Macs → Sessions → Terminal |
| Runs | At login (optional), always in the menu bar | On demand; reconnects and re-attaches by itself |
| Also | `pockettmuxd` — the same agent as a CLI for headless Macs / scripts | — |

Both are built from one repo and one Swift package (`PocketTmuxKit`), so the
protocol, tmux parsers and pairing format can never drift between them.

## 3. PocketTmux for Mac

### 3.1 Menu-bar panel

```
┌─ PocketTmux ──────────────────────────────┐
│ ● Agent running · port 7682        [on ]  │
│   100.67.189.40 · 192.168.0.64            │
│ CONNECTED IPHONES                         │
│   Doyeon's iPhone   pi-agent   3m         │
│ TMUX SESSIONS                             │
│   work      3 windows · 2 attached · now  │
│   pi-agent  1 window  · 1 attached · 3m 📱 │
│ [Pair iPhone…]  [Settings…]        [Quit] │
└───────────────────────────────────────────┘
```

- Status line: running / stopped / error (port in use, tmux missing) with a
  Retry; the toggle starts and stops the agent.
- Connected iPhones: device name, which session it is attached to, since when.
- tmux sessions: live (every 3 s while open + on tmux's `%sessions-changed`),
  with *Open in Terminal* and *Kill session…* in the row menu.

### 3.2 Pair iPhone… window

A QR of `pockettmux://pair?host=…&port=…&token=…&name=…`, a picker for which
address to embed (Tailscale first, then Wi-Fi/LAN), the link with *Copy*, the
token masked with *Reveal* / *Copy*. The iPhone scans it (or opens the link
via AirDrop/Messages — the URL scheme is registered) and is paired.

### 3.3 Settings

- **General** — Launch at login · Start agent when the app launches · Keep
  Mac awake while an iPhone is attached · Advertise on the local network
  (Bonjour) · Name shown on iPhone.
- **Network** — Port (restart applies) · reachable addresses.
- **Security** — Token (masked; Reveal / Copy / Regenerate…). Stored in
  `~/.pockettmux/token` (0600) so the CLI agent and `scripts/pair.sh` use the
  same one. Regenerating means every phone pairs again.
- **Advanced** — tmux path (auto-detected: Homebrew, /usr/local, /usr/bin;
  overridable) · agent log (last 500 lines, copy/clear).
- **About** — version, protocol version, license.

### 3.4 Non-goals (Mac)

Rendering terminal content on the Mac (it has its own terminals), multi-user
tokens, TLS, remote access outside LAN/Tailscale.

## 4. PocketTmux for iPhone

### 4.1 Screens (3-step navigation)

```
Macs ──▶ Sessions ──▶ Terminal
 │          │             ├ status bar: ● session · window · ⌨︎ ▣ …
 │          │             ├ window strip: [0:zsh] [1:pi] [+]
 │          │             └ SwiftTerm + accessory keyboard
 │          └ live list · new · rename · kill · attach
 └ saved Macs · nearby Macs (Bonjour) · add (QR / manual) · settings
```

**Macs.** Saved Macs (Keychain, many), nearby Macs found over Bonjour, *Add*
(scan the QR, or host/port/token by hand). One saved Mac → auto-resume on
launch. Onboarding block on first launch: install the Mac app → Pair iPhone…
→ scan.

**Sessions.** The Mac's tmux sessions, sorted by activity: name, windows,
attached clients, last activity; badge on the one the phone is attached to.
Pull to refresh (the list is also pushed live). New (name validated the way
tmux validates), Rename, Kill (confirmed). Connection row: `Connected · tmux
3.7c · 12 ms` (RTT from a 10 s ping), `Reconnecting…`, or the error.

**Terminal.** Full screen. Status bar (back = detach, state dot, session,
window; dismiss-keyboard, paste, menu: new/rename/kill window, font −/+,
detach). Window strip: tap to switch, long-press to rename/kill, `+` for a
new window — switching re-primes the screen from tmux, so a window that was
running vim shows vim, cursor in the right place. Swipe-to-scroll: on the
alternate screen the drag becomes SGR wheel events (pi fullscreen, Claude
Code, opencode) or cursor keys (less, man, vim); on the normal screen it is
the emulator's own scrollback (primed with up to 2000 lines of history).
Bell → haptic. Screen stays awake while on this screen (setting).

**Settings.** Font size (12–20), haptics on bell, keep screen awake, about.

### 4.2 Connection behaviour

- Reconnect with exponential backoff (1 s → 30 s, ±20 % jitter); on
  `hello.ack` the wanted session is re-attached and the agent repaints in
  full — the screen never goes blank on a Wi-Fi blip or after the phone was
  locked.
- Attach carries the phone's terminal size so the pane is resized *before*
  the first paint (no wrapped-then-reflowed garbage).
- Detached because the session was killed on the Mac → banner *"Session
  ended on the Mac"*, back to Sessions. Control client died for another
  reason → one automatic re-attach.
- Wrong token → clear error on the Macs screen, edit the profile.

### 4.3 Non-goals (iPhone)

iPad layout, multiple simultaneous Macs, file transfer, split panes (the
active pane of a window is what the phone shows; multi-pane windows are a
documented simplification), TLS.

## 5. Design language — Japanese dev-tool sensibility, English copy

Quiet, monospaced, restrained: mono small-caps section labels (`SESSIONS`,
`NEARBY MACS`), no gradients, no big shadows, no emoji, no corner radius
above 6 pt, standard controls. Data and status in monospace, body in SF.

Palette — traditional Japanese colors on terminal ink (the iPhone app is
always dark; the Mac app follows the system appearance and uses the accent
and status colors only):

| Role | Name | Hex |
|---|---|---|
| background | 墨 sumi | `#0B0D11` |
| surface | 藍墨 aizumi | `#12161D` / `#181E28` |
| text | 和紙 washi | `#E4E0D4` |
| muted | 鼠 nezumi | `#8A8B8D` |
| accent / attach / destructive | 朱 shu | `#E0584C` |
| warn / connecting | 山吹 yamabuki | `#E0A44C` |
| connected / success | 萌葱 moegi | `#43A885` |
| info / link | 藍 ai | `#4A6FA5` |

Status dot vocabulary everywhere: moegi = connected/running, yamabuki =
connecting/reconnecting, muted = idle/stopped, shu = error.

## 6. Verified facts that shaped v1 (tmux 3.7c)

- `tmux -CC` stdin is a *command stream*, not keys. Keys go via
  `send-keys -H` with **one hex number per key**; a concatenated hex string
  is silently dropped.
- Control mode replays **nothing** that predates the control client — no
  `?1049h`, no `?1006h`, no content. The agent primes the phone from
  `#{alternate_on}`, `#{mouse_*_flag}`, `#{keypad_cursor_flag}`,
  `#{cursor_x}/#{cursor_y}` and `capture-pane -p -e` (TROUBLESHOOTING §3).
- A session window has **one size shared by all clients**. While a phone is
  attached the agent pins the window it looks at (`resize-window` +
  `window-size manual`) and unpins on detach so the Mac client re-asserts its
  size (TROUBLESHOOTING §2).
- Bracketed paste is tmux's job: `load-buffer` + `paste-buffer -p` wraps the
  text in `ESC[200~ … ESC[201~` only if the pane asked for it.

## 7. Release scope

**v1.0** = everything above. See [ROADMAP.md](ROADMAP.md) for what comes
after (TLS, iPad, pane picker, notifications, Homebrew tap, App Store).
