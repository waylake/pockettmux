# PocketTmux

**Your Mac's tmux, in your pocket.** PocketTmux is a native iOS app (Swift + SwiftUI) that lets you attach to `tmux` sessions running on your Mac — over your local Wi-Fi, with no cloud in between.

> [!NOTE]
> "PocketTmux" is a working name — rename PRs welcome. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design rationale.

## How it works

```
  iPhone (PocketTmux.app)                         Mac
┌────────────────────────────────┐    Wi-Fi (LAN)   ┌────────────────────────────────┐
│ SwiftUI UI                          │                  │ Agent (macOS daemon)           │
│   └─ TerminalView (SwiftTerm)   │  ── keystrokes ───▶  │   └─ tmux control mode (tmux -CC)  │
│   └─ Transport (WebSocket)      │  ◀── screen ──────  │       session → window → pane     │
└────────────────────────────────┘                  └────────────────────────────────┘
```

A keypress on the phone becomes a tmux keypress in the target pane; pane output streams back and is rendered by the in-app terminal engine. **tmux is the single source of truth** — the phone is just another client, like the Mac's own terminals. The complete request/response flow (attach, input, screen update, resize, reconnect) is documented in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#4-request-flow).

## Features

**v0.1 (this release) — planning & skeleton:**
- Well-structured repo: planning docs (architecture, tech stack, roadmap), CI, release pipeline, license, contributing guide
- Buildable iOS app skeleton (SwiftUI) with a connection screen
- A P0 path to get a terminal on your phone in minutes (a `ttyd`-based PWA) — see [docs/ROADMAP.md](docs/ROADMAP.md)

**Planned (v1.0):**
- Attach / detach / create / destroy tmux sessions from the phone
- Live screen rendering (ANSI, 256-color, TrueColor), terminal resize, scrollback
- Reconnect with state restore; agent auth (token)
- macOS menu-bar agent (launch at login, port & token config)

## Quick start

**Prereqs (Mac):** macOS 26, Xcode 26.2+, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), [tmux](https://github.com/tmux/tmux) 3.7+ (`brew install tmux`).
**Prereqs (phone):** iPhone running iOS 16+ (developed against iOS 26).

```sh
git clone https://github.com/waylake/pockettmux.git
cd pockettmux/App
xcodegen generate          # regenerates PocketTmux.xcodeproj from Project.yml
open PocketTmux.xcodeproj # pick a device/simulator, ⌘R to build & run
```

### v1 — native agent + app

```sh
cd pockettmux
scripts/start-agent.sh     # builds & runs pockettmuxd (ws://0.0.0.0:7682), token in ~/.pockettmux/token
scripts/pair.sh            # shows a pairing QR on screen
```

On the iPhone: open PocketTmux → **Scan pairing QR** → point at the QR.
The host/port/token are filled in and it connects. From then on the phone
reconnects with a single tap. Manual fallback: Connect screen with
the Tailscale/LAN IP, port 7682, token from `cat ~/.pockettmux/token`.

> First run on the Mac shows the *“allow incoming connections?”* firewall
> prompt — allow it, or the phone can't reach the agent (the app shows
> Reconnecting…).
> CLI note: xcodebuild needs `-skipPackagePluginValidation` for the SwiftTerm
> build-tool plugin; the Xcode GUI builds normally.

**P0 — a terminal on the phone in 2 minutes (optional):** run `ttyd tmux new -A -s main` on the Mac, open `http://<mac-ip>:7681` in the phone's Safari, and use *Add to Home Screen* to get a PWA. This validates the same architecture with zero native code; the native app replaces it from P1 on.

## Documentation

| Doc | What it covers |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, the full request flow (keypress → tmux → screen), the transport protocol, key design decisions & alternatives, failure modes |
| [docs/TECH_STACK.md](docs/TECH_STACK.md) | Every technology with version, license, rationale & alternatives — researched as of **2026-09** (GitHub API / npm registry / Apple Developer) |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phases P0 → v1.0, milestones, definitions of done, non-goals |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Real failure modes (attach → "session ended", window-size flicker) with root causes & the research behind each fix |

## Project layout

```
.
├── App/                    # the iOS app (XcodeGen + SPM)
│   ├── Project.yml           # project spec (source of truth for the .xcodeproj)
│   ├── PocketTmux/             # app sources (SwiftUI)
│   └── PocketTmuxTests/          # unit tests
├── docs/                     # design & planning docs
├── .github/                  # CI/CD workflows, issue & PR templates
├── CHANGELOG.md              # Keep a Changelog
└── ...
```

The macOS agent will live in a separate `Agent/` target (added in P1 — see the roadmap).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — dev setup, workflow, commit conventions, testing, versioning & releases. TL;DR: fork → feature branch → Conventional Commits → PR (CI green + self-checklist) → review.

## Versioning & releases

**Semantic Versioning** (`MAJOR.MINOR.PATCH`); `0.x` is pre-1.0 (breaking changes expected). Releasing = push a `vX.Y.Z` tag → the [release workflow](.github/workflows/release.yml) archives the app and opens a GitHub Release with the `.ipa` and the changelog. The changelog follows [Keep a Changelog](https://keepachangelog.com).

## License

[MIT](LICENSE) — see the file. Third-party components (and their licenses) are listed in [docs/TECH_STACK.md](docs/TECH_STACK.md).
