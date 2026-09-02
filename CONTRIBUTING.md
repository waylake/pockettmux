# Contributing to PocketTmux

Thanks for taking the time to contribute! This is (currently) a personal project, but all contributions — code, docs, design, tests, and good questions — are welcome.

## Project overview

Two apps and one shared Swift package, all in `App/` (details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)):

| Piece | Path | Scheme | What it is |
|---|---|---|---|
| PocketTmux for Mac | `App/macOS/` | `PocketTmuxMac` | Menu-bar app (SwiftUI `MenuBarExtra`) that hosts the agent, pairing QR, settings and the clients/sessions overview. Product `PocketTmux.app`. |
| PocketTmux for iPhone | `App/iOS/` | `PocketTmux` | SwiftUI app; the terminal is rendered by **SwiftTerm**. Macs → Sessions → Terminal. |
| `pockettmuxd` | `App/Daemon/` | `pockettmuxd` | Headless agent — the same engine as the Mac app, for scripts and servers. |
| `PocketTmuxKit` package | `App/PocketTmuxKit/` | `swift test` | `PocketTmuxKit` (protocol v2 wire codec, tmux control-mode parsers, pairing payload) and `PocketTmuxAgent` (WebSocket server, tmux control). Pure Swift, no UI. |

**tmux** is the source of truth; the Mac's own terminals and the phone are both clients. The protocol lives in the package (`Sources/PocketTmuxKit/Protocol/`), so a protocol change is a package change first, then both apps.

## Getting started

**Prereqs (one-time):**

```sh
brew install xcodegen      # project generator — the spec is App/Project.yml
brew install swiftlint     # style (optional locally; CI enforces it)
brew install tmux          # the agent needs tmux ≥ 3.2 on the Mac
```

Xcode 26.2+ on macOS 26 is assumed (the baseline is in [docs/TECH_STACK.md](docs/TECH_STACK.md)).

**Then:**

```sh
git clone https://github.com/waylake/pockettmux.git
cd pockettmux/App
xcodegen generate            # → PocketTmux.xcodeproj (git-ignored; regenerable)
open PocketTmux.xcodeproj   # pick a scheme + destination, ⌘R
```

`Project.yml` is the source of truth; XcodeGen picks up whole source folders, so adding files needs no spec edit — just regenerate.

**Building from the command line** (run from `App/`). Every `xcodebuild` needs `-skipPackagePluginValidation`: SwiftTerm's build-tool plugin fails its validation step on Xcode 26 before anything compiles (see [CLAUDE.md](CLAUDE.md)).

```sh
# shared package (fastest loop for protocol / parser / agent logic)
swift test --package-path PocketTmuxKit

# iPhone app — simulator
xcodebuild build -project PocketTmux.xcodeproj -scheme PocketTmux \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/Sim -skipPackagePluginValidation

# Mac menu-bar app
xcodebuild build -project PocketTmux.xcodeproj -scheme PocketTmuxMac \
  -destination 'platform=macOS' -derivedDataPath build/Mac -skipPackagePluginValidation

# headless agent
xcodebuild build -project PocketTmux.xcodeproj -scheme pockettmuxd \
  -destination 'platform=macOS' -derivedDataPath build/Daemon -skipPackagePluginValidation
```

> If your local Xcode has no simulators, install the platform: `xcodebuild -downloadPlatform iOS`.
> Installing on a physical iPhone (signing, `devicectl`) is documented in [CLAUDE.md](CLAUDE.md).

**Running the agent without Xcode:**

```sh
scripts/start-agent.sh        # builds pockettmuxd if needed, runs it in the background (POCKETTMUX_PORT=… to change the port)
scripts/pair.sh               # shows the pairing QR + link for the phone
scripts/stop-agent.sh [port]  # stop it again
```

The Mac app's *Pair iPhone…* window is the GUI equivalent of `pair.sh`; both read the token from `~/.pockettmux/token`.

## Development workflow

1. **Branch from `main`** — `git switch -c feat/<short-topic>` (or `fix/`, `docs/`, `chore/`).
2. **Commit with Conventional Commits** (below).
3. **Open a PR** — fill the template; CI must be green; link the issue if there is one.
4. **Review is via PR** — expect feedback within a few days; address it with new commits (squash-merge is fine for small work).

Keep `main` releasable at all times. For a large change, land it in pieces.

## Commit conventions

[Conventional Commits](https://www.conventionalcommits.org):

```
<type>(<optional scope>): <subject>

[optional body]
[optional footer: BREAKING CHANGE / Closes #123]
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `chore`, `revert`.
**Scopes** in use: `ios`, `mac`, `kit`, `agent`, `daemon`, `ci`, `scripts`, `docs`.

**Examples:**

```
feat(ios): add nearby Macs section (Bonjour)
fix(agent): flush control-mode output when a pane exits
feat(mac): regenerate token from Settings › Security
chore(build): bump xcodegen to 2.45.4
```

Use the imperative and keep the subject to about 72 characters; explain *why* in the body; close issues or note breaking changes in the footer.

## Code style

- **SwiftLint** is the style authority — the config is `.swiftlint.yml`. Run `swiftlint lint` (CI runs `--strict`).
- Swift 6 language mode with `SWIFT_STRICT_CONCURRENCY: minimal`; SwiftUI-first for UI; drop to AppKit/UIKit only where needed (e.g., hosting the SwiftTerm `TerminalView`).
- Prefer value types. Keep the wire protocol (`WireCodec`, `ClientMessage`, `ServerMessage`) small and well-named — that's where protocol changes happen, and both apps depend on it.
- Design language: quiet, monospaced labels, English copy, no emoji, no gradients, corner radius ≤ 6 pt.

## Tests

Three layers, from fastest to slowest:

- **Package tests** — `swift test --package-path App/PocketTmuxKit`. Wire codec round-trips, tmux control-mode parsing, pairing payloads, agent pure logic. Put protocol/parser tests here; they need no simulator.
- **iOS tests** — `App/iOSTests/` (scheme `PocketTmux`, `xcodebuild test … -skipPackagePluginValidation`). Client-side state: connection/reconnect state machine, profile store migration, view models.
- **End-to-end** — `python3 scripts/check-attach-prime.py` against a running agent (`scripts/start-agent.sh` or the Mac app). Speaks protocol v2 over a real WebSocket and asserts the attach priming frame, resize-before-paint, window ops, input/paste round-trips and ping/pong. Run it after touching the agent or the protocol. `POCKETTMUX_HOST` / `POCKETTMUX_PORT` / `POCKETTMUX_TOKEN` override the defaults.

CI runs the first two on every PR plus a build of `PocketTmuxMac` and `pockettmuxd`; the e2e script needs a real tmux and is run locally.

## Versioning & releases

- **SemVer** (`MAJOR.MINOR.PATCH`). After 1.0, bump `MAJOR` for breaking changes to the app/protocol/agent (the wire protocol carries its own `WireProtocol.version`).
- **Releases are tag-driven:** push `vX.Y.Z` → the [release workflow](.github/workflows/release.yml) builds the Mac app (`PocketTmux-macOS-vX.Y.Z.zip`), `pockettmuxd` (`pockettmuxd-vX.Y.Z.tar.gz`) and the iPhone app (`PocketTmux-iOS-vX.Y.Z-unsigned.ipa`), then opens a GitHub Release with the changelog section as notes.
- Every artifact is **unsigned** (no Developer ID certificate or provisioning profile in CI): the Mac app needs right-click → Open on first launch, and the `.ipa` must be re-signed with your own Apple ID (Sideloadly, AltStore) or replaced by an Xcode run on your device. Developer ID signing + notarization are on the v1.1 list.
- **The changelog is part of the PR:** update [CHANGELOG.md](CHANGELOG.md) (Keep a Changelog) in the same PR that changes behavior.

## Where things live (docs)

- **User-facing** (what the apps do, how to run them): `README.md`
- **Design & decisions** (why it's shaped this way, the request flow, the protocol, trade-offs, open questions): `docs/ARCHITECTURE.md`, `docs/TECH_STACK.md`, `docs/ROADMAP.md`, `docs/TROUBLESHOOTING.md`
- **Build gotchas** (plugin validation, signing, device install, scrolling design): `CLAUDE.md`
- If you change how the system works or *why*, update the matching doc in the same PR.

## Licensing & attribution

MIT — see [LICENSE](LICENSE). If you add a third-party dependency, note it (license, purpose) in [docs/TECH_STACK.md](docs/TECH_STACK.md) in the same PR.
