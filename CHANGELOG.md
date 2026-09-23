# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Native Window/Pane hierarchy menu on iPhone. A phone-selected pane in a
  split tmux window is zoomed to the full phone grid, can be changed without
  flattening the split, and is restored on window switch or detach.
- Additive protocol-v2 `panes` and `pane.select` frames plus a `panes` agent
  capability; package and live-agent e2e coverage now includes split panes.

### Changed
- Replaced the fixed dark product theme with native Apple UI across iPhone and
  Mac: system navigation, lists, forms, sheets, toolbars, menus, empty states,
  settings chrome, semantic colors, Dynamic Type, and system appearance.
- Replaced the custom terminal window strip with a standard hierarchical
  toolbar menu and restored the native navigation-bar back button.
- Kept specialized presentation only where the product needs it: SwiftTerm,
  QR scanning/rendering, logs, and technical values.
- Added `docs/UI_GUIDELINES.md`, an Apple HIG/SwiftUI research record, component
  map, explicit exceptions, and review checklist.

### Fixed
- Split tmux windows no longer squeeze the phone's selected pane into half its
  grid and leave TUIs visibly clipped.
- Short-lived agent commands and the forked tmux control client now remove
  inherited `TMUX` / `TMUX_PANE`, preventing commands launched from a tmux shell
  from operating in the launching client's context.

## [1.0.0] - 2026-09-02

PocketTmux is now **two apps** built from one repo and one shared Swift package.

### Added
- **PocketTmux for Mac** — a menu-bar app that hosts the agent: start/stop with status, port and reachable addresses; connected iPhones; live tmux sessions (open in Terminal, kill); **Pair iPhone…** window (QR + link + token, address picker with Tailscale first); Settings (launch at login, auto-start, keep Mac awake while attached, Bonjour, name, port, token regenerate, tmux path, log).
- **PocketTmux for iPhone** — Macs screen with saved profiles (many Macs, Keychain), **nearby Macs via Bonjour**, pairing by QR / `pockettmux://` deep link / manual entry; Sessions with new / rename / kill and round-trip time; Terminal with a **window strip** (switch, new, rename, kill), **paste** (bracketed-paste aware), font size, haptic bell, keep-awake; reconnect with jittered backoff and automatic re-attach.
- **`PocketTmuxKit` package** — `PocketTmuxKit` (protocol v2 codec, tmux control-mode parser, `-F` format parsers, name validation, pairing payload) and `PocketTmuxAgent` (WebSocket server on Network.framework, `tmux -CC` control client, screen primer, window pinning, paste, Bonjour, sleep assertion, token store, ring log). Unit tests run with `swift test`.
- **Protocol v2** (`docs/PROTOCOL.md`): client/host identity, windows, rename, paste, attach size hint (the pane is resized *before* the first paint), typed detach reasons and error codes, ping/pong RTT.
- Screen priming now also restores the **cursor position** and re-runs on every window/pane switch, so switching to a window running vim shows vim with the caret in place.
- `pockettmuxd` CLI on the same library: `--port --token --name --no-bonjour --no-keep-awake --tmux --regenerate-token`.
- CI builds the package tests, the iOS app (+ tests), the Mac app and the daemon; releases attach the `.ipa`, `PocketTmux.app` zip and `pockettmuxd` tarball.
- `scripts/check-attach-prime.py` grew into a full end-to-end check (prime, size-before-paint, windows, input, paste, ping, detach reasons, auth).
- Docs: `PRODUCT.md` (both apps), `PROTOCOL.md`, rewritten `ARCHITECTURE.md`, `ROADMAP.md`, `TECH_STACK.md`; new troubleshooting entries (Bonjour, port in use, unsigned builds).
- README rewritten as a product page: app screenshots of both apps in `docs/assets/`, mermaid architecture and attach-sequence diagrams, install/pairing/security sections.

### Changed
- Repo layout: `App/iOS`, `App/macOS`, `App/Daemon`, `App/PocketTmuxKit` (was `App/PocketTmux`, `App/Agent`, `App/AgentCore`). `Project.yml` defines four targets and references the local package.
- The agent stopped printing to stdout ad hoc; it logs through `AgentLog` (unified log + ring buffer) and the daemon echoes it.
- tmux `-F` formats are tab-separated (session and window names may contain `|`).
- `session.destroy` → `session.kill`; `exit` → `session.detached{reason}`.

### Removed
- Protocol v1 (a v1 `hello` is rejected with `error{auth}` so old builds fail loudly).
- `docs/PRODUCT-v1.md` (superseded by `docs/PRODUCT.md`), the single-profile Keychain record (migrated into the profile list on first launch).

### Fixed
- Sending `error{auth}` on a bad token was racing the socket close; the frame is now flushed before the connection is cancelled.
- `pockettmuxd` crashed on SIGTERM (`exit()` from a raw signal handler); signals are handled through dispatch sources.
- Tapping a Mac on the Macs screen or a session on the Sessions screen did nothing: `.onTapGesture` on a `List` row never fires next to `swipeActions`/`contextMenu` on iOS 26, so both rows are plain `Button`s now.
- CI and Release ran on `macos-15` (Xcode 16.4) and could not compile the apps at all: the isolated `@MainActor TerminalViewDelegate` conformance failed with "unknown attribute 'MainActor'" and `CIContext` was still non-`Sendable`. Both workflows now run on `macos-26` and pin Xcode 26.2 through `.github/scripts/select-xcode.sh`.
- The Release job looked for a `## [vX.Y.Z]` changelog heading while the file uses `## [X.Y.Z]`, so every release shipped with placeholder notes; publishing is also idempotent now (a re-run refreshes notes/assets) and no longer swallows failures.

## [0.1.0] - 2026-09-01

### Added
- Initial repository scaffold: `App/` (XcodeGen + SwiftUI skeleton), `docs/`, `.github/` (CI, release pipeline, issue/PR templates), license (MIT), contributing & code-of-conduct guides
- Planning & design docs: `docs/ARCHITECTURE.md`, `docs/TECH_STACK.md`, `docs/ROADMAP.md`
- CI (`ci.yml`) and the tag → `.ipa` release pipeline (`release.yml`)
- App skeleton and the P0 `ttyd` path
- Native agent `pockettmuxd` (WebSocket + `tmux -CC`, token auth, QR pairing) and the first iPhone client; screen priming fix for scrolling in TUIs and shell scrollback (see `docs/TROUBLESHOOTING.md` §3)
