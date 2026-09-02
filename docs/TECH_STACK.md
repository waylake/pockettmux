# Tech Stack — PocketTmux

*Every component, with version · license · why it was chosen · the alternative that was considered. Versions verified **2026-09-01/02** via GitHub API and the development machine's toolchain.*

## Principles

1. **Boring technology.** Prefer the option with the longest track record and the largest ecosystem. Novelty is a cost.
2. **LAN-first.** The network is trusted and low-latency (Tailscale is encrypted by itself). Complexity is justified by the *host* (tmux, Mac), not the wire.
3. **Native on both ends.** SwiftUI on iPhone and Mac; no webview as a terminal surface.
4. **tmux is the source of truth.** The architecture must make "phone and Mac terminal show the same pane" trivially true.
5. **Zero third-party dependencies except the terminal engine.** Everything else is Apple frameworks.

## The stack

### Shared (`App/PocketTmuxKit`)

| Component | Choice | Version | License | Why |
|---|---|---|---|---|
| Language | Swift, language mode 6 | 6.2.3 (Xcode 26.2) | Apache-2.0 | One language across the repo; value types + `Sendable` make the protocol types trivially safe across queues |
| Package | Swift Package Manager (local package, two products) | — | — | `PocketTmuxKit` (pure) and `PocketTmuxAgent` (macOS) are compiled once and linked by three targets; `swift test` runs the unit tests in seconds |
| JSON | `Codable` + `JSONEncoder/Decoder` | Foundation | — | Typed frames with pinned wire shapes (tests) |

### iPhone (`App/iOS`)

| Component | Choice | Version | License | Why |
|---|---|---|---|---|
| OS / SDK | iOS 26.2 SDK · **minimum iOS 16.0** | — | — | Wide device coverage; `NavigationStack`, `MenuBarExtra`-era SwiftUI |
| UI | SwiftUI (+ UIKit for the terminal view and the camera) | iOS 16+ | — | Declarative UI for Macs/Sessions/Settings; UIKit only where a view is UIKit |
| Terminal engine | **SwiftTerm** | **1.20.0** (resolved; `from: 1.19.0`) | **MIT** | Native VT100/xterm emulator with a UIKit `TerminalView`, accessory keyboard, mouse reporting, alternate screen, TrueColor. *See D1.* Ships a build-tool plugin → `-skipPackagePluginValidation` on the CLI |
| Transport | `URLSessionWebSocketTask` | Foundation | — | Zero-dependency WebSocket client. *See D2.* |
| Discovery | `NWBrowser` (Bonjour `_pockettmux._tcp`) | Network.framework | — | Same-Wi-Fi Macs appear by themselves. *See D8.* |
| Pairing | `AVCaptureMetadataOutput` (QR) + `pockettmux://` URL scheme | AVFoundation | — | Scan the Mac's QR or open the link |
| Storage | Keychain (profiles, JSON) + `@AppStorage` (preferences) | Security | — | Tokens never live in UserDefaults |

### Mac (`App/macOS`, `App/Daemon`, `PocketTmuxAgent`)

| Component | Choice | Version | License | Why |
|---|---|---|---|---|
| OS | macOS 14+ (developed on 26.4) | — | — | `MenuBarExtra(.window)`, `SMAppService`, `SettingsLink` |
| Multiplexer | **tmux** | **3.7c** (2026-08-17) | **MIT** | The user's existing multiplexer. *See D3.* |
| tmux bridge | **Control mode (`tmux -CC`)** on a `forkpty` pty + `capture-pane` priming | — | — | Event-driven `%output`, stable ids, `refresh-client -C`. *See D4.* |
| WebSocket server | `NWListener` + `NWProtocolWebSocket` | Network.framework | — | WebSocket upgrade, ping/pong and Bonjour registration in the framework; no NIO, no OpenSSL. *See D5.* |
| Keep-awake | `IOPMAssertionCreateWithName` (`PreventUserIdleSystemSleep`) | IOKit | — | The Mac must not sleep under an attached phone (F1) |
| Launch at login | `SMAppService.mainApp` | ServiceManagement | — | The supported API since macOS 13 |
| Logging | `os.Logger` + in-memory ring buffer | os | — | Console.app *and* Settings › Log |
| App form | Menu-bar app (`LSUIElement`), hardened runtime, **not sandboxed** | — | — | Must exec the user's `tmux` and open a pty. *See D9.* |

### The P0 path (validation, historical)

`ttyd` + xterm.js served a tmux pane to Safari in two minutes and proved the loop before any native code existed. It is not part of the product; port 7681 stays reserved for it.

### Alternative transport (v2+)

| Component | Version | License | Why it's on the list |
|---|---|---|---|
| TLS on the WebSocket (self-signed, fingerprint in the pairing payload) | — | — | The planned v1.2 upgrade of D7: keeps zero-config pairing, removes the LAN trust assumption |
| SSH (libssh2 1.11.1 / swift-nio-ssh) | 2024-10 | BSD-3 | The alternative behind D2 if we ever want to reuse an existing `sshd` |

## Toolchain (build / CI / release)

| Component | Choice | Version | Why |
|---|---|---|---|
| Project generator | **XcodeGen** | 2.45.4 | `App/Project.yml` is the source of truth for four targets; the `.xcodeproj` is generated and git-ignored |
| Linter | **SwiftLint** | 0.65.1 | `.swiftlint.yml` at the repo root; CI runs `--strict` |
| Package tests | `swift test --package-path App/PocketTmuxKit` | Xcode 26.2 | Protocol, parsers, primer, encoder — no simulator needed |
| App builds | `xcodebuild` (+ `-skipPackagePluginValidation`) | Xcode 26.2 | iOS simulator build+test; Mac app + daemon build |
| E2E | `scripts/check-attach-prime.py` (raw WebSocket client, stdlib Python) | — | Attach/prime/windows/input/paste/auth against a live agent and real tmux |
| CI | GitHub Actions on `macos-26` (arm64) | — | lint · package · ios · mac jobs; `.github/scripts/select-xcode.sh` pins Xcode 26.2 (the image defaults to the newest 26.x, and `macos-15` only has Xcode 16.x, which cannot compile isolated `@MainActor` conformances) |
| Release | tag `vX.Y.Z` → `release.yml` | — | unsigned `.ipa` (packaged by hand: `-exportArchive` needs a signing identity), `PocketTmux.app` zip, `pockettmuxd` tarball, changelog notes; publishing is idempotent per tag |

## Version notes

- **SwiftTerm** — `from: 1.19.0`, resolves to **1.20.0** on Xcode 26.2. The 1.x line is pinned; the 2.0 API on `main` is a scoped migration for later.
- **tmux 3.7c** — released 2026-08-17. Control-mode facts in PROTOCOL §5 / TROUBLESHOOTING were verified against it.
- **Xcode 26.2 / Swift 6.2.3 / iOS 26.2 SDK** on macOS 26.4.1 — the development baseline.
- **xcodegen 2.45.4**, **SwiftLint 0.65.1** — Homebrew.

## Risks & mitigations (stack-level)

| Risk | Why it matters | Mitigation |
|---|---|---|
| SwiftTerm 1.x vs 2.0 dual API | The repo's `main` is 2.0 | Pin `from: 1.19.0` (SPM keeps us on 1.x); migrate deliberately |
| SwiftTerm build-tool plugin fails validation on Xcode 26.2 | CLI builds abort before compiling | `-skipPackagePluginValidation` everywhere (scripts, CI, CLAUDE.md) |
| Control-mode output isn't UTF-8 | Garbled screens | Bytes end-to-end, base64 on the wire (F7) |
| Unencrypted WebSocket on LAN | Snooping | Token + documented simplification; TLS in v1.2 (D7/F9) |
| Output floods | Phone lags | 16 ms coalescing, 512 KiB immediate flush, `reset` re-converges (F8) |
| Unsigned Mac artifacts from CI | Gatekeeper warning on first open | Right-click → Open; Developer ID + notarization is a v1.1 task |

## Decision cross-reference

The "why" behind each row is the decision in [ARCHITECTURE.md → §6](ARCHITECTURE.md#6-key-technical-decisions--alternatives) (D1–D9) and the failure notes (§7, F1–F13).
