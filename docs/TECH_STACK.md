# Tech Stack — PocketTmux

*Every component, with version · license · why it was chosen · the alternative that was considered. All versions verified **2026-09-01** via GitHub API, npm registry, and Apple Developer tooling on the development machine.*

## Principles

1. **Boring technology.** Prefer the option with the longest track record and the largest ecosystem. Novelty is a cost.
2. **LAN-first.** The network is trusted and low-latency. Complexity is justified by the *host* (tmux, Mac), not the wire.
3. **Native on iOS.** The phone is a native Swift app (SwiftUI). No webview as the *primary* terminal surface (the PWA phase is a validation tool, not the product).
4. **tmux is the source of truth.** The architecture must make "phone and Mac terminal show the same pane" trivially true.

## The stack

### iPhone (the app)

| Component | Choice | Version | License | Why |
|---|---|---|---|---|
| OS / SDK | iOS (Xcode SDK) | iOS 26.2 SDK · **minimum deployment iOS 16.0** | — | Build with Xcode 26.2 against the iOS 26.2 SDK; target iOS 16+ so a wide range of current iPhones run it (the phone is on iOS 26 in 2026, but a low floor keeps it usable on older hardware) |
| Language | Swift | 6.2.3 (Xcode 26.2) | Apache-2.0 | The native iOS language; modern concurrency; compiles fast |
| UI framework | SwiftUI | (iOS 16+) | MIT | Declarative, fast to iterate, first-class in 2026; the app UI (connection, session list, terminal chrome) is simple |
| Terminal engine | **SwiftTerm** | **v1.19.0** (released 2026-08-18) | **MIT** | The native VT100/xterm emulator for Swift. A **UIKit `TerminalView`** you embed; a real terminal engine (not a text view): 256/TrueColor, cursor, resize, selection, OSC 8 hyperlinks, Sixel/imgcat/Kitty graphics, optional **Metal GPU rendering**. **Battle-tested in shipping apps** (Secure Shellfish, La Terminal, CodeEdit). **Active**: release 2026-08-18, push 2026-08-31, 1.7k★. SPM. *See decision D1.* |
| Transport (client) | WebSocket | URLSessionWebSocketTask (stdlib) | — | Zero-dependency WebSocket client on iOS. LAN is enough for v1. *See D2.* |
| Storage | Keychain | (iOS 16+) | — | Host:port + token live in the Keychain (not UserDefaults) |

### Mac (the agent + tmux)

| Component | Choice | Version | License | Why |
|---|---|---|---|---|
| OS | macOS | 26 (Tahoe) | — | The host; the agent is a macOS daemon |
| Multiplexer | **tmux** | **3.7c** (released 2026-08-17) | **MIT** | The user's existing multiplexer; sessions/windows/panes + history are the source of truth; brew-managed; 3.7 is the current stable line. *See D3.* |
| tmux bridge | **Control mode (`tmux -CC`)** | (tmux 3.7) | — | tmux's own programmatic-client interface: event-driven `%output`, lifecycle events, stable IDs, `refresh-client -C` sizing. Chosen over `capture-pane` polling. *See D4.* |
| Agent runtime | Swift + **SwiftNIO** | Swift 6.2.3 · **swift-nio 2.102.0** (released 2026-09-01) | MIT | One language across agent + app; NIO is Apple's production networking stack (NIOWebSocket included); strong concurrency for a long-lived socket. *See D5.* |
| Agent packaging | macOS daemon (menu-bar app later) | — | — | Self-contained; launch-at-login via the menu-bar shell (P2) |

### The P0 path (validation, pre-native)

| Component | Choice | Version | License | Why |
|---|---|---|---|---|
| Web terminal | **ttyd** (C single-binary) | (latest tag — verify at deploy) | MIT | Runs `ttyd tmux …` on the Mac; serves xterm.js over WebSocket; **zero native code** proves the LAN+tmux+terminal loop in 2 minutes. It's the P0 artifact, *not* the product (the native app replaces it). *See D6.* |
| Web terminal engine | **xterm.js** (`@xterm/xterm`) | **6.0.0** (npm latest) | **MIT** | The battle-tested browser terminal (VS Code, Hyper, ttyd). Used in the P0 PWA (Safari → home screen) and available as the D1 fallback if we ever ship a webview shell |

### Alternative transport (v2+)

| Component | Choice | Version | License | Why it's on the list |
|---|---|---|---|---|
| SSH stack | **libssh2** (or swift-nio-ssh) | **libssh2 1.11.1** (2024-10) | BSD-3 | The SSH option behind D2. libssh2 is the C reference (mature, BSD); swift-nio-ssh is the Swift/NIO path SwiftTerm's own sample uses. We pick whichever fits the agent at v2; listed so the version is known. |

## Toolchain (build / CI / release)

| Component | Choice | Version | Why |
|---|---|---|---|
| Project generator | **XcodeGen** | **2.45.4** (2.46.0 available) | `App/Project.yml` is the source of truth; the `.xcodeproj` is generated (kept out of git). Standard, fast, CI-friendly |
| Package manager | Swift Package Manager | (Xcode 26.2) | Dependencies (SwiftTerm in P1) via SPM; `Package.resolved` is tracked |
| Linter | **SwiftLint** | **0.65.1** (Homebrew) | The Swift style authority; a minimal `.swiftlint.yml`; CI runs `--strict` |
| Build / test | xcodebuild | (Xcode 26.2) | `xcodebuild … build / test` on an iOS simulator; the CI command |
| CI | GitHub Actions | (2026) | `ci.yml` (PR gate: SwiftLint + xcodegen + xcodebuild build & test) on a **macOS runner (macos-15)** |
| Release | GitHub Releases + tag → workflow | — | `release.yml`: tag → `xcodebuild archive` → ad-hoc `.ipa` → GitHub Release with the changelog. Systematic versioning without a paid account (yet). *See CONTRIBUTING → Versioning.* |
| Git | git | 2.54 | main + feature branches, Conventional Commits, PRs |
| GitHub CLI | gh | 2.98 | repo create / push / release in the setup |

## Version notes (verified 2026-09-01)

- **SwiftTerm v1.19.0** — released **2026-08-18** (GitHub API: `releases/latest` → tag `v1.19.0`). MIT. Push **2026-08-31**. Note: the repo's `main` describes the **2.0 API**; the **1.x line** (tags like v1.19.0, `v1.x` branch) is the version we pin for P1 — a 2.0 migration is a P1/P2 decision, not a v0 concern.
- **tmux 3.7c** — released **2026-08-17** (GitHub API: `releases/latest` → tag `3.7c`, "tmux 3.7c", bug-fix release of the 3.7 line). MIT.
- **@xterm/xterm 6.0.0** — npm registry `latest` → version **6.0.0** (MIT). The P0 xterm.js.
- **swift-nio 2.102.0** — released **2026-09-01** (GitHub API: `releases/latest` → tag `2.102.0`). Apple. MIT. The agent's NIO.
- **libssh2 1.11.1** — released **2024-10** (GitHub API: `releases/latest` → tag `libssh2-1.11.1`). BSD. The v2 SSH reference (mature, slower-moving — fine for a reference).
- **xcodegen 2.45.4** — installed locally (2.46.0 is the current Homebrew). MIT. (Repo: yonaskolb/XcodeGen.)
- **SwiftLint 0.65.1** — current Homebrew stable. NASA.
- **Xcode 26.2 / Swift 6.2.3 / iOS 26.2 SDK** — the development machine's toolchain (macOS 26.4.1). The baseline the docs and CI assume.
- **ttyd** — C single-binary; tag-based releases (no GitHub "releases" as of 2026-09 — verify the exact tag at P0 deploy). MIT.

## Risks & mitigations (stack-level)

| Risk | Why it matters | Mitigation |
|---|---|---|
| **SwiftTerm 1.x vs 2.0 dual API** | The repo's `main` is 2.0; we pin the 1.x line (v1.19.0) | **Pin the exact version** in `Package.swift` (SPM). A 2.0 migration (with their migration guide) is a scoped P1/P2 task, not a silent upgrade. |
| **Control-mode output isn't always valid UTF-8** (octal-escaped control chars) | Naive string handling garbles the screen | The agent decodes octal escapes to **bytes** before framing; the terminal engine consumes bytes (see ARCHITECTURE F7). |
| **WebSocket is unencrypted on the LAN** (v1) | A snooping LAN device sees frames | Documented simplification (ARCHITECTURE D7/F9): single-user home LAN + high-entropy token. TLS / SSH are the v2 upgrades. |
| **High-throughput output floods the phone** | A fast `cat`/`yes` lags or drops | Backpressure/coalescing (ARCHITECTURE §5): bounded queue, drop-oldest, ~16 ms flush, `reset` always re-converges. |
| **xcodegen-generated project drift** | Hand-edited project files would conflict with regeneration | `Project.yml` is the **only** source of truth; the `.xcodeproj` is git-ignored; CI regenerates. |

## Decision cross-reference

The "why" behind each row is the decision in [ARCHITECTURE.md → §6](ARCHITECTURE.md#6-key-technical-decisions--alternatives) (D1–D7) and the failure notes (§7, F1–F10). This table is the *what* + *version*; the architecture doc is the *why* + *trade-off*.
