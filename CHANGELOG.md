# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-01

### Added
- Initial repository scaffold: `App/` (XcodeGen + SwiftUI skeleton), `docs/`, `.github/` (CI, release pipeline, issue/PR templates), license (MIT), contributing & code-of-conduct guides
- Planning & design docs: `docs/ARCHITECTURE.md` (components, request flow, transport protocol, decisions & alternatives, failure modes), `docs/TECH_STACK.md` (all components with version/license/rationale, researched 2026-09), `docs/ROADMAP.md` (P0→v1.0 phases, milestones, DoD)
- CI: `ci.yml` (SwiftLint + xcodegen + xcodebuild build & test on a macOS runner / iOS simulator)
- Release pipeline: `release.yml` (tag → archive → ad-hoc `.ipa` → GitHub Release)
- App skeleton: `PocketTmuxApp` + `ContentView` (connection bar + terminal placeholder, P1 integration points marked)
- Baseline toolchain recorded: Xcode 26.2 / Swift 6.2.3, xcodegen 2.45.4, SwiftLint 0.65.1; tmux 3.7c; SwiftTerm v1.19.0; @xterm/xterm 6.0.0; libssh2 1.11.1

### Notes
- 0.1.0 is pre-1.0: app, protocol, and agent interfaces may change without notice
- The macOS `Agent/` target lands in P1 (see `docs/ROADMAP.md`)
