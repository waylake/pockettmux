<div align="center">

<img src="docs/assets/icon.png" width="104" height="104" alt="PocketTmux">

# PocketTmux

**Your Mac's tmux, in your pocket.**

A menu-bar agent for the Mac and a native iPhone terminal that attach to the **same tmux server** —
over Wi-Fi or Tailscale, with no cloud in between.

[![CI](https://img.shields.io/github/actions/workflow/status/waylake/pockettmux/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/waylake/pockettmux/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/waylake/pockettmux?style=flat-square&color=e0563f)](https://github.com/waylake/pockettmux/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?style=flat-square&logo=apple&logoColor=white)](#install)
[![iOS 16+](https://img.shields.io/badge/iOS-16%2B-111?style=flat-square&logo=apple&logoColor=white)](#install)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-f05138?style=flat-square&logo=swift&logoColor=white)](App/PocketTmuxKit/Package.swift)
[![tmux 3.7](https://img.shields.io/badge/tmux-3.7-1bb91f?style=flat-square)](https://github.com/tmux/tmux)
[![MIT](https://img.shields.io/badge/license-MIT-111?style=flat-square)](LICENSE)

<p>
  <img src="docs/assets/ios-terminal.png" width="240" alt="Terminal attached to a tmux session">
  <img src="docs/assets/ios-nvim.png" width="240" alt="Neovim running in a tmux window">
  <img src="docs/assets/ios-keyboard.png" width="240" alt="Accessory keyboard with Esc, Ctrl and arrows">
</p>

</div>

---

The pane your Mac's terminals see is the pane your phone renders. A key tapped on the phone is a
tmux key in the real pane; the pane's bytes stream back and are drawn by a native VT engine
(SwiftTerm). **tmux stays the single source of truth** — the phone is one more client, exactly like
a terminal window on the Mac.

```mermaid
flowchart LR
    subgraph P["iPhone — PocketTmux"]
        UI["Macs · Sessions · Terminal"] --- TV["SwiftTerm view"]
    end
    subgraph M["Mac — PocketTmux.app / pockettmuxd"]
        AS["AgentServer<br/>WebSocket + Bonjour"] --> TC["TmuxControl<br/>tmux -CC on a pty"]
    end
    T["tmux server<br/>sessions · windows · panes"]
    MT["Terminal.app,<br/>iTerm, Ghostty…"]
    P <-- "ws v2 · LAN / Tailscale" --> AS
    TC <--> T
    MT <--> T
```

Two apps, one Swift package, no third-party services and no daemon to install beyond `tmux` itself.

## Screens

<table>
<tr>
<td width="33%" align="center"><img src="docs/assets/ios-onboarding.png" width="215" alt="First run"><br><sub><b>First run</b><br>Pair by QR, or pick a Mac found over Bonjour</sub></td>
<td width="33%" align="center"><img src="docs/assets/ios-macs.png" width="215" alt="Macs"><br><sub><b>Macs</b><br>Saved Macs in the Keychain · nearby Macs live</sub></td>
<td width="33%" align="center"><img src="docs/assets/ios-sessions.png" width="215" alt="Sessions"><br><sub><b>Sessions</b><br>Live tmux sessions, round-trip time, new / rename / kill</sub></td>
</tr>
</table>

<table>
<tr>
<td width="34%" align="center"><img src="docs/assets/mac-menu.png" width="300" alt="Mac menu-bar panel"><br><sub><b>Menu bar</b><br>Agent state, addresses, connected iPhones, live sessions</sub></td>
<td width="33%" align="center"><img src="docs/assets/mac-pair.png" width="215" alt="Pair iPhone window"><br><sub><b>Pair iPhone…</b><br>QR + link + token, address picker (Tailscale first)</sub></td>
<td width="33%" align="center"><img src="docs/assets/mac-settings.png" width="290" alt="Mac settings"><br><sub><b>Settings</b><br>Launch at login, keep awake, Bonjour, port, token, tmux path</sub></td>
</tr>
</table>

## Features

**PocketTmux for Mac** — macOS 14+, menu bar, not sandboxed (it execs your `tmux` and opens a pty)

|  | |
|---|---|
| **Agent** | Start/stop, port, status and every reachable address (Tailscale listed first) |
| **Pairing** | QR / `pockettmux://` link / copyable token, with the address you choose |
| **Visibility** | Connected iPhones and the session each one is on; live tmux sessions with *open in Terminal* and *kill* |
| **Settings** | Launch at login, auto-start, keep the Mac awake while a phone is attached, Bonjour advertising, display name, port, token regenerate, `tmux` path, ring log |
| **Headless** | `pockettmuxd` — the same agent as a CLI for remote or scripted Macs |

**PocketTmux for iPhone** — iOS 16+

|  | |
|---|---|
| **Macs** | Many saved Macs (Keychain), nearby Macs over Bonjour, add by QR / link / manual entry |
| **Sessions** | Live list with window and client counts, attach, create, rename, kill, RTT next to the status dot |
| **Terminal** | SwiftTerm rendering (TrueColor, alternate screen, mouse reporting), accessory keyboard (<kbd>esc</kbd> <kbd>ctrl</kbd> <kbd>⇥</kbd> <kbd>~</kbd> <kbd>\|</kbd> arrows), window strip (switch / new / rename / kill), paste with bracketed-paste semantics, font size, haptic bell, keep-awake |
| **Scrolling** | Swipe scrollback inside TUIs *and* shells — the first paint after any attach is rebuilt from tmux's own state, so nothing is blank or garbled ([why this is hard](docs/TROUBLESHOOTING.md#3-nothing-scrolls--not-in-a-tui-not-in-the-shell-scrollback)) |
| **Resilience** | Jittered backoff reconnect with automatic re-attach after Wi-Fi drops, backgrounding and Mac sleep |

## Install

### Mac

```sh
# 1 · download PocketTmux-macOS-*.zip from Releases, then
mv PocketTmux.app /Applications
brew install tmux            # the only prerequisite
open /Applications/PocketTmux.app
```

CI builds are unsigned — the first launch needs **right-click → Open**. The app appears in the menu
bar; choose **Pair iPhone…**.

> [!NOTE]
> macOS shows the *"allow incoming connections?"* firewall prompt on first start. Allow it, or the
> phone cannot reach the agent.

### iPhone

Download `PocketTmux-iOS-*-unsigned.ipa` from [Releases](https://github.com/waylake/pockettmux/releases)
and re-sign it with your own Apple ID (Sideloadly, AltStore), or build and run the `PocketTmux`
scheme on your device from Xcode — no paid developer account needed either way.

### Pair

1. Mac: menu bar → **Pair iPhone…**
2. iPhone: **+** → **Scan QR** (on the same Wi-Fi the Mac also appears under *Nearby Macs*)
3. Tap a session. You're in.

> [!TIP]
> Tailscale works out of the box and needs no port forwarding: the pairing QR carries the
> `100.x.y.z` address, and mDNS is not required.

## How an attach works

```mermaid
sequenceDiagram
    participant P as iPhone
    participant A as Agent
    participant T as tmux
    P->>A: hello{v:2, token}
    A-->>P: hello.ack{host, caps}
    P->>A: session.attach{id, cols, rows}
    A->>T: forkpty → tmux -CC attach -t $1
    A->>T: resize-window + window-size manual
    A->>T: display-message #{alternate_on}… · capture-pane -p -e
    A-->>P: session.attached{session, windows}
    A-->>P: screen{reset} — primed escapes + content + cursor
    T-->>A: %output %7 …
    A-->>P: screen{update} every 16 ms
```

Control mode gives exact bytes and stable ids but replays nothing that predates the client, so the
agent primes the first frame from tmux's own state — the trick that makes scrollback and TUIs work
on the phone. Full flows in [ARCHITECTURE §4](docs/ARCHITECTURE.md#4-request-flow); frames in
[PROTOCOL](docs/PROTOCOL.md).

## Build from source

Prereqs: macOS 26, Xcode 26.2+, `brew install xcodegen tmux` (`swiftlint` optional).

```sh
git clone https://github.com/waylake/pockettmux.git
cd pockettmux/App
xcodegen generate            # PocketTmux.xcodeproj from Project.yml (git-ignored)
open PocketTmux.xcodeproj    # schemes: PocketTmux (iOS) · PocketTmuxMac · pockettmuxd
```

<details>
<summary>Command line — every <code>xcodebuild</code> needs <code>-skipPackagePluginValidation</code></summary>

```sh
# Mac app
xcodebuild build -scheme PocketTmuxMac -destination 'platform=macOS' \
  -derivedDataPath build/Mac -skipPackagePluginValidation
open build/Mac/Build/Products/Debug/PocketTmux.app

# iPhone app (simulator)
xcodebuild build -scheme PocketTmux -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/Sim -skipPackagePluginValidation

# headless agent + pairing QR, no Mac app involved
../scripts/start-agent.sh && ../scripts/pair.sh

# tests
swift test --package-path PocketTmuxKit                     # 23 tests: protocol, parsers, agent logic
xcodebuild test -scheme PocketTmux -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/Sim -skipPackagePluginValidation   # 15 iOS unit tests
python3 ../scripts/check-attach-prime.py                    # e2e against a running agent
```

SwiftTerm ships a build-tool plugin whose validation step fails on Xcode 26.2 — without the flag the
build aborts before compilation. Details in [CLAUDE.md](CLAUDE.md).

</details>

## Repository

```
App/
├── Project.yml         XcodeGen spec — four targets (source of truth for the .xcodeproj)
├── PocketTmuxKit/      Swift package
│   ├── PocketTmuxKit   protocol v2 codec · tmux control-mode parser · -F formats · pairing URL
│   └── PocketTmuxAgent AgentServer · AgentConnection · TmuxControl · TmuxRunner · ScreenPrimer
├── iOS/                PocketTmux for iPhone (SwiftUI + SwiftTerm)
├── macOS/              PocketTmux for Mac (menu-bar app)
├── Daemon/             pockettmuxd (CLI agent)
└── iOSTests/           iOS unit tests
docs/                   product · architecture · protocol · stack · roadmap · troubleshooting
scripts/                start/stop-agent · pair (QR) · check-attach-prime (e2e) · make-icon
```

Anything protocol- or tmux-related lives in the package, never duplicated in an app target.

## Documentation

| Doc | What it covers |
|---|---|
| [PRODUCT](docs/PRODUCT.md) | Jobs, screens, behaviour, design language, release scope |
| [ARCHITECTURE](docs/ARCHITECTURE.md) | Components, request flows, decisions & alternatives, failure modes |
| [PROTOCOL](docs/PROTOCOL.md) | Wire protocol v2: frames, priming, pairing, discovery |
| [TECH_STACK](docs/TECH_STACK.md) | Every dependency with version, license and rationale |
| [ROADMAP](docs/ROADMAP.md) | Shipped in v1.0; next: notifications, pane picker, TLS, iPad |
| [TROUBLESHOOTING](docs/TROUBLESHOOTING.md) | Real failures, root causes, and the research behind each fix |

## Security model

Trust is *same network + token*: a 32-character random token per Mac in `~/.pockettmux/token`
(mode 0600), compared in constant time, presented in the first frame. There is **no TLS in v1** —
the intended deployments are a home LAN and Tailscale, which is already encrypted. Regenerate the
token any time from Settings › Security; TLS with a pinned certificate and per-device tokens are
[planned for v1.2](docs/ROADMAP.md#v12--security--reach).

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) covers setup, workflow, Conventional Commits and tests.
Semantic Versioning; pushing a `vX.Y.Z` tag builds the unsigned `.ipa`, the Mac app zip and the
`pockettmuxd` tarball into a GitHub Release with the [CHANGELOG](CHANGELOG.md) section as notes.

[MIT](LICENSE) · built on [tmux](https://github.com/tmux/tmux) and
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
