# Contributing to PocketTmux

Thanks for taking the time to contribute! This is (currently) a personal project, but all contributions — code, docs, design, tests, and good questions — are welcome.

## Project overview

The mental model (details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)):

- **`App/`** — the iOS app (Swift + SwiftUI). The terminal is rendered by **SwiftTerm**; the transport (WebSocket) sits behind a small boundary so the UI doesn't care how bytes travel.
- **`Agent/` (macOS, from P1)** — a small daemon that owns the **tmux control-mode** channel and speaks the transport protocol (WebSocket via SwiftNIO).
- **tmux** is the source of truth; the Mac's own terminals and the phone are both clients.

## Getting started

**Prereqs (one-time):**

```sh
brew install xcodegen    # project generator — the spec is App/Project.yml
brew install swiftlint     # style (optional locally; CI enforces it)
```

Xcode 26.2+ on macOS 26 is assumed (the baseline is in [docs/TECH_STACK.md](TECH_STACK.md)).

**Then:**

```sh
git clone https://github.com/waylake/pockettmux.git
cd pockettmux/App
xcodegen generate            # → PocketTmux.xcodeproj (git-ignored; regenerable)
open PocketTmux.xcodeproj   # pick a destination, ⌘R
```

**Useful xcodebuild commands** (run from `App/`):

```sh
DEST='platform=iOS Simulator,name=iPhone 16'
xcodebuild -project PocketTmux.xcodeproj -scheme PocketTmux -destination "$DEST" build
xcodebuild -project PocketTmux.xcodeproj -scheme PocketTmux -destination "$DEST" test
```

> If your local Xcode has no simulators, install the platform: `xcodebuild -downloadPlatform iOS`.

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

**Examples:**

```
feat(app): add connection screen with host/port fields
fix(agent): flush control-mode output when a pane exits
docs(readme): document the P0 ttyd quick start
chore(build): bump xcodegen to 2.45.4
```

Use the imperative and keep the subject to about 72 characters; explain *why* in the body; close issues or note breaking changes in the footer.

## Code style

- **SwiftLint** is the style authority — the config is `.swiftlint.yml`. Run `swiftlint lint` (CI runs `--strict`).
- SwiftUI-first for UI; drop to UIKit only where needed (e.g., hosting the SwiftTerm `TerminalView`).
- Prefer value types. Keep the transport boundary small and well-named — that's where protocol changes happen.

## Tests

- Unit tests live in `App/PocketTmuxTests/` and run in CI (`xcodebuild test`).
- Focus on the non-obvious: protocol encode/decode, the connect/reconnect state machine, control-mode frame parsing.
- UI: the simulator is the test environment for now; scripted UI tests come later if the app grows.

## Versioning & releases

- **SemVer** (`MAJOR.MINOR.PATCH`). `0.x` = "pre-1.0, breaking changes OK." After 1.0, bump `MAJOR` for breaking changes to the app/protocol/agent.
- **Releases are tag-driven:** push `vX.Y.Z` (e.g., `v0.2.0`) → the [release workflow](.github/workflows/release.yml) archives the app, exports an ad-hoc `.ipa`, and opens a GitHub Release with the changelog as notes.
- **The changelog is part of the PR:** update [CHANGELOG.md](CHANGELOG.md) (Keep a Changelog) in the same PR that changes behavior.
- Today signing is ad-hoc/free-tier; a paid developer account (TestFlight, etc.) is a later concern — see the roadmap (P3).

## Where things live (docs)

- **User-facing** (what the app does, how to run it): `README.md`
- **Design & decisions** (why it's shaped this way, the request flow, the protocol, trade-offs, open questions): `docs/ARCHITECTURE.md`, `docs/TECH_STACK.md`, `docs/ROADMAP.md`
- If you change how the system works or *why*, update the matching doc in the same PR.

## Licensing & attribution

MIT — see [LICENSE](LICENSE). If you add a third-party dependency, note it (license, purpose) in [docs/TECH_STACK.md](docs/TECH_STACK.md) in the same PR.
