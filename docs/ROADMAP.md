# Roadmap — PocketTmux

*"Done" means usable by the primary user (the maintainer) on their own Mac +
iPhone over home Wi-Fi and Tailscale, with the definition of done met.*

## Shipped

### v1.0 — two apps, one protocol *(this release)*

| Area | Delivered |
|---|---|
| Shared | `PocketTmuxKit` package: protocol v2 (`WireCodec`), tmux control-mode parser, `-F` formats, name validation, pairing payload; `PocketTmuxAgent`: WebSocket server (Network.framework), `tmux -CC` control client, screen priming, window pinning, paste, Bonjour, sleep assertion, token store, ring log — unit-tested (`swift test`) and end-to-end tested (`scripts/check-attach-prime.py`) |
| Mac app | Menu-bar app: start/stop, status + addresses, connected iPhones, live sessions (open in Terminal / kill), Pair iPhone… (QR, address picker, link/token copy), Settings (launch at login, auto-start, keep awake, Bonjour, name, port, token regenerate, tmux path, log) |
| CLI | `pockettmuxd` on the same library (`--port --token --name --no-bonjour --no-keep-awake --tmux --regenerate-token`) |
| iPhone app | Macs (saved + nearby via Bonjour + add by QR/link/manual, deep link), Sessions (live list, new/rename/kill, RTT), Terminal (SwiftTerm, accessory keyboard, window strip with new/select/rename/kill, paste, swipe-to-scroll in TUIs, primed scrollback, font size, haptic bell, keep awake), reconnect with jittered backoff + auto re-attach, multi-Mac profiles in Keychain |
| Infra | CI: SwiftLint, package tests, iOS build+test, Mac app + daemon build; release: tag → `.ipa` + `PocketTmux.app` zip + `pockettmuxd` tarball + changelog notes |

### v0.1 — scaffold *(2026-09-01)*

Planning docs, CI/release skeleton, iOS app skeleton, P0 ttyd path.

## Next

### v1.1 — quality of life

- **Notifications**: the Mac app (or agent) notices a pane's bell / a tmux
  `monitor-activity` hit and pushes a local notification to the phone while
  it is connected in the background ("pi is waiting for input").
- **Pane picker**: multi-pane windows show a pane strip like the window
  strip; the phone selects which pane to view/drive (`select-pane`).
- **Session create with cwd/command** (`session.create{name,cwd?,cmd?}`).
- **Homebrew tap** for `pockettmuxd` and a cask for the Mac app; Developer
  ID signing + notarization in the release workflow.
- iPhone: search/filter in Sessions, per-Mac font size, hardware keyboard
  shortcuts map (⌘K clear, ⌘[/] window switch).

### v1.2 — security & reach

- **TLS**: the Mac app mints a self-signed cert on first run; the pairing
  payload carries its fingerprint; the phone pins it (ARCHITECTURE D7/F9
  upgrade). Keeps the zero-config pairing.
- **Per-device tokens** with revoke from the Mac app's client list.
- Optional **read-only** pairing (view but don't type).

### v2 — beyond one Mac and one phone

- iPad layout (sidebar sessions + terminal), multiple simultaneous Macs.
- Binary frame format for high-throughput output (keep the JSON control
  plane).
- App Store / TestFlight distribution; Sixel/imgcat rendering decision.

## Non-goals (stay out of scope)

- File transfer / SFTP, shell-on-phone.
- Multi-user Macs (one agent, one token owner).
- Replacing tmux with a custom multiplexer.

## Open questions

Tracked in ARCHITECTURE §8: Sixel on the phone, binary protocol, per-client
input locks when two clients drive one pane.
