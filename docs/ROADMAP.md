# Roadmap — PocketTmux

*Phases, milestones, definitions of done, and non-goals. "Done" for a phase means the DoD is met and it's usable by the primary user (the maintainer) on their own Mac + iPhone over home Wi-Fi.*

## Phases at a glance

| Phase | Goal | App | Agent (Mac) | Transport | Est. |
|---|---|---|---|---|---|
| **P0** | Prove the loop: LAN + tmux + terminal, zero native code | PWA (Safari) | `ttyd` (C binary) | WebSocket (ttyd) | ~2 min setup |
| **P1** | Native v0.1: a real terminal on the phone, one session | SwiftUI + SwiftTerm | Swift + SwiftNIO (control mode) | WebSocket (custom frames) | ~2–4 weeks |
| **P2** | v0.2: sessions, UX, reconnect, agent as a menu-bar app | Session manager, scrollback, reconnect UX | Menu-bar app (launch-at-login, port/token) | WebSocket + auth (token) | ~2–4 weeks |
| **P3** | v1.0: polish, docs, releases, (optional) TestFlight | Dark mode, fonts, haptics | Homebrew tap for the agent | + (optional) TLS | ~1–2 weeks |

## P0 — Prototype (the 2-minute proof)

**Goal:** Show a live tmux pane from the Mac on the phone's Safari — *no native app, no agent code* — to validate the end-to-end concept (LAN reachability, tmux as source of truth, a terminal renderer).

**What we do:**
1. `brew install tmux ttyd` on the Mac.
2. Run `ttyd -p 7681 tmux new -A -s main` — ttyd spawns/attaches a tmux session and serves xterm.js over WebSocket.
3. On the iPhone: open `http://<mac-lan-ip>:7681` in Safari → a terminal. *Add to Home Screen* → a PWA icon.
4. Type `ls`, `top`, run a shell — it works. **Concept proven.**

**Definition of done (P0):**
- [ ] A tmux session is visible and interactive on the phone (Safari/PWA)
- [ ] Typing on the phone reaches the Mac shell; output renders
- [ ] A quick-start note (in `docs/` or README) records the exact commands + the known LAN gotchas (AP isolation, IP)

**What P0 does *not* do:** no token/auth (LAN-only), no session manager UI, no reconnect logic, no native rendering. It's a spike.

## P1 — Native v0.1 (the real terminal)

**Goal:** Replace the PWA with the **native app**: a SwiftUI shell + **SwiftTerm** rendering, talking to a **custom Swift agent** over a **WebSocket** that bridges **tmux control mode**. One session, attach, type, see output, resize, reconnect.

**App (SwiftUI + SwiftTerm):**
- `TerminalView` (SwiftTerm UIKit) hosted in SwiftUI; a connection bar (host:port + token, Keychain)
- `Transport` — URLSessionWebSocketTask; encodes/decodes the **v1 protocol** (ARCHITECTURE §5); reconnect backoff
- `SessionStore` — session list + attach/detach state; the *one* session UX for v0.1

**Agent (Swift + SwiftNIO):**
- A WebSocket server (`ws://<mac>:7681`) using SwiftNIO + NIOWebSocket
- A **tmux bridge** speaking **control mode (`tmux -CC`)**: maps `%output` → `screen` frames, session events → `session.*` frames, `send-keys`/`resize-pane` on input/resize
- A **token** auth on `hello`; port/token from a config file

**Definition of done (P1):**
- [ ] The app builds (Xcode 26.2) and runs on an iPhone (iOS 16+)
- [ ] Attach to a tmux session: the pane renders (ANSI/colors), typing on the phone reaches the shell, output streams back
- [ ] Resize (rotation) updates the pane; scrollback view works
- [ ] Reconnect after Wi-Fi drop / foreground: `screen` reset restores the pane
- [ ] The agent starts/stops; a `hello` with the token authenticates
- [ ] Unit tests: protocol encode/decode, reconnect state machine, control-mode frame parsing

## P2 — v0.2 (sessions, UX, agent app)

**Goal:** Make it a *usable* tool: manage **multiple sessions** from the phone, solid **reconnect** UX, and the agent as a **menu-bar app** (launch-at-login, port/token config, status).

**App:**
- **Session manager**: list (live via `session.*` events), create (name/cwd/cmd), attach/detach, destroy; a session switcher
- **Scrollback**: tmux history view + on-phone scrollback cache (bounded)
- **Reconnect UX**: status (Connecting/Connected/Reconnecting…), state preserved, full restore on return

**Agent (menu-bar app):**
- A **menu-bar app**: start/stop the agent, status (port, connected clients), config (port, token), **launch at login**
- (Optional) **Bonjour/mDNS** advertisement for auto-discovery (nice-to-have)

**Definition of done (P2):**
- [ ] Create / attach / detach / destroy multiple sessions from the phone; the list stays live
- [ ] Scrollback (tmux history + on-phone) works
- [ ] Reconnect UX: clear status, state preserved, full restore
- [ ] The agent menu-bar app: launch-at-login, port/token config, status
- [ ] CI hardened (SwiftLint strict, build + test on the PR gate); protocol codec unit-tested

## P3 — v1.0 (polish, docs, releases)

**Goal:** A **shippable v1.0**: polish, a user guide, a systematic release pipeline (`.ipa` + Homebrew for the agent), and (optional) TestFlight.

**Work:**
- **Polish**: dark mode, font/size options, cursor/haptics, onboarding (paste the token)
- **Docs**: a user guide (setup, agent, usage, troubleshooting) + a protocol reference
- **Releases**: the tag → `.ipa` → GitHub Release pipeline; **Homebrew tap** for the agent (the maintainer already has a tap); a `Package.swift` for the agent
- **(Optional) TestFlight**: a paid developer account → TestFlight distribution (or keep ad-hoc)

**Definition of done (P3):**
- [ ] v1.0.0: the app + agent are polished and documented (user guide)
- [ ] A release: tag → `.ipa` → GitHub Release (with changelog) works end-to-end
- [ ] The agent is installable via Homebrew
- [ ] (Optional) TestFlight build uploaded

## Non-goals (v1)

- **iPad** layout / multitasking (phone-first; iPad is a later surface)
- **Multiple Macs** (one agent per Mac; the phone connects to one at a time in v1)
- **Outside the LAN** (VPN/Tailscale) — v2
- **SFTP / file transfer**, shell-on-phone
- **Per-client input locks** (multi-client contention is a documented simplification, F6)
- **TLS** (v2; v1 is LAN + token)

## Open questions (carried from ARCHITECTURE §8)

Sixel/graphics in v1? tmux mouse passthrough? agent-address store (iCloud/KVS)? Bonjour discovery? binary protocol v2? per-client locks? — tracked in ARCHITECTURE; each gets answered at the phase that needs it.
