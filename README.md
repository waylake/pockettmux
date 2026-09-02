# PocketTmux

**Your Mac's tmux, in your pocket.** Two native apps: a **menu-bar app for the Mac** that hosts the agent and pairs by QR, and an **iPhone app** that attaches to your tmux sessions as another terminal of the Mac — over Wi-Fi or Tailscale, no cloud in between.

```
  iPhone — PocketTmux.app                          Mac — PocketTmux.app (menu bar)
┌────────────────────────────────┐                ┌────────────────────────────────────┐
│ Macs → Sessions → Terminal     │  ws (LAN /     │ agent: WebSocket + tmux -CC        │
│   SwiftTerm · window strip     │  Tailscale)    │ pairing QR · settings · log        │
│   accessory keyboard · paste   │ ◀────────────▶ │       │                            │
└────────────────────────────────┘                │       ▼ control mode               │
                                                  │ tmux server — sessions/windows/panes│
                                                  └────────────────────────────────────┘
```

A key tapped on the phone is a tmux key in the real pane; the pane's output streams back and is rendered by a native terminal engine. **tmux is the single source of truth** — the phone is just another client, like the Mac's own terminals. Full request flow: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#4-request-flow). Wire format: [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Features

**PocketTmux for Mac** (macOS 14+, menu bar)
- Start/stop the agent; status, port and reachable addresses at a glance
- **Pair iPhone…** — QR / link with the address you choose (Tailscale first), token copy
- Connected iPhones (which session each is on) and live tmux sessions (open in Terminal, kill)
- Settings: launch at login, auto-start, keep Mac awake while a phone is attached, Bonjour advertising, name, port, token regenerate, tmux path, log
- `pockettmuxd` — the same agent as a CLI for headless Macs and scripts

**PocketTmux for iPhone** (iOS 16+)
- **Macs**: saved Macs (many, Keychain), nearby Macs found over Bonjour, add by QR / `pockettmux://` link / manually
- **Sessions**: live list, new / rename / kill, attach; connection status with round-trip time
- **Terminal**: SwiftTerm rendering (TrueColor, alternate screen, mouse reporting), accessory keyboard (Esc / Ctrl / arrows / F-keys), **window strip** (switch, new, rename, kill), paste with bracketed-paste semantics, swipe-to-scroll inside TUIs (pi, Claude Code, vim, less) and primed scrollback in shells, font size, haptic bell, keep-awake
- Reconnects with backoff and re-attaches by itself; the first paint after any attach is rebuilt from tmux's own state (no blank or garbled screens)

## Install

**Mac**
1. Download `PocketTmux-macOS-*.zip` from [Releases](https://github.com/waylake/pockettmux/releases) (or build: see below), move `PocketTmux.app` to Applications, open it (CI builds are unsigned: right-click → Open the first time).
2. It appears in the menu bar. `tmux` must be installed (`brew install tmux`).
3. Menu bar → **Pair iPhone…**

**iPhone**
1. Install the `.ipa` from Releases (ad-hoc) or build & run from Xcode on your device.
2. Open PocketTmux → **+** → **Scan QR** → point at the Mac's pairing window. On the same Wi-Fi the Mac also shows up under *Nearby Macs*.
3. Tap a session. You're in.

> First run on the Mac shows the *"allow incoming connections?"* firewall prompt — allow it, or the phone can't reach the agent.

## Build from source

Prereqs: macOS 26, Xcode 26.2+, `brew install xcodegen tmux` (`swiftlint` optional).

```sh
git clone https://github.com/waylake/pockettmux.git
cd pockettmux/App
xcodegen generate                       # PocketTmux.xcodeproj from Project.yml (git-ignored)
open PocketTmux.xcodeproj               # schemes: PocketTmux (iOS), PocketTmuxMac, pockettmuxd
```

Command line (every `xcodebuild` needs `-skipPackagePluginValidation`, see [CLAUDE.md](CLAUDE.md)):

```sh
# Mac app
xcodebuild build -scheme PocketTmuxMac -destination 'platform=macOS' \
  -derivedDataPath build/Mac -skipPackagePluginValidation
open build/Mac/Build/Products/Debug/PocketTmux.app

# iPhone app (simulator)
xcodebuild build -scheme PocketTmux -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/Sim -skipPackagePluginValidation

# headless agent + pairing QR without the Mac app
../scripts/start-agent.sh && ../scripts/pair.sh

# tests
swift test --package-path PocketTmuxKit                     # protocol, parsers, primer
xcodebuild test -scheme PocketTmux -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/Sim -skipPackagePluginValidation   # iOS unit tests
python3 ../scripts/check-attach-prime.py                    # end-to-end against a running agent
```

## Documentation

| Doc | What it covers |
|---|---|
| [docs/PRODUCT.md](docs/PRODUCT.md) | Product plan for both apps: jobs, screens, behaviour, design language, release scope |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, request flows (pair, attach, keys, windows, resize, reconnect), decisions & alternatives, failure modes |
| [docs/PROTOCOL.md](docs/PROTOCOL.md) | Wire protocol v2 reference (frames, priming, pairing, discovery) |
| [docs/TECH_STACK.md](docs/TECH_STACK.md) | Every technology with version, license, rationale |
| [docs/ROADMAP.md](docs/ROADMAP.md) | What shipped in v1.0, what's next (notifications, pane picker, TLS, iPad) |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Real failure modes with root causes and the research behind each fix |

## Project layout

```
.
├── App/
│   ├── Project.yml          # XcodeGen spec — four targets (source of truth)
│   ├── PocketTmuxKit/       # Swift package: PocketTmuxKit (protocol, parsers) + PocketTmuxAgent (agent)
│   ├── iOS/                 # PocketTmux for iPhone (SwiftUI + SwiftTerm)
│   ├── iOSTests/            # iOS unit tests
│   ├── macOS/               # PocketTmux for Mac (menu-bar app)
│   └── Daemon/              # pockettmuxd (CLI agent)
├── scripts/                 # start/stop-agent, pair (QR), e2e check, icon generator
├── docs/                    # product, architecture, protocol, stack, roadmap, troubleshooting
├── .github/                 # CI (lint · package · ios · mac) and tag-driven releases
└── CHANGELOG.md
```

## Contributing, versioning, license

See [CONTRIBUTING.md](CONTRIBUTING.md) (setup, workflow, Conventional Commits, tests). Semantic Versioning; pushing a `vX.Y.Z` tag builds the `.ipa`, the Mac app zip and the `pockettmuxd` tarball into a GitHub Release with the [CHANGELOG](CHANGELOG.md) section as notes. [MIT](LICENSE).
