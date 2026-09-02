# PocketTmux — CLAUDE.md

Build/install notes for this repo. General contributing workflow lives in [CONTRIBUTING.md](CONTRIBUTING.md); design docs in `docs/` (start with `docs/PRODUCT.md` and `docs/ARCHITECTURE.md`; the wire format is `docs/PROTOCOL.md`).

## Layout (two apps, one package)

```
App/Project.yml        XcodeGen spec — targets: PocketTmux (iOS), PocketTmuxMac (→ PocketTmux.app), pockettmuxd, PocketTmuxTests
App/PocketTmuxKit/     Swift package: PocketTmuxKit (protocol v2, tmux parsers, pairing) + PocketTmuxAgent (server, tmux -CC)
App/iOS/  App/macOS/  App/Daemon/  App/iOSTests/
scripts/               start-agent.sh · stop-agent.sh · pair.sh · check-attach-prime.py (e2e) · make-icon.swift
```

Anything protocol- or tmux-related belongs in the package, never duplicated in an app target. `swift test --package-path App/PocketTmuxKit` runs the package tests in seconds.

## Build prerequisites (gotchas)

- **Xcode 26.2** is the baseline. SwiftTerm is resolved at **1.20.0** (`Project.yml`: `from: 1.19.0`).
- **Every `xcodebuild` invocation needs `-skipPackagePluginValidation`.** SwiftTerm 1.20.0 ships a build-tool plugin (`SwiftTermBuildInfoPlugin`) whose "Validate plug-in" step fails on Xcode 26.2, aborting the build *before* compilation — even for the simulator and even for the Mac schemes that don't use SwiftTerm. Without the flag you only see `Validate plug-in “SwiftTermBuildInfoPlugin” …` + a base64 blob, no useful error. The plugin only generates build-info constants from a trusted, pinned source, so skipping validation is safe.
- `Project.yml` is the source of truth; regenerate the (git-ignored) project with `cd App && xcodegen generate` after editing it or adding files. If build settings look stale, regenerate first.
- The project sets `SWIFT_STRICT_CONCURRENCY: minimal`, but Swift 6 language mode still enforces some isolation errors. `TerminalCoordinator` must keep the `@MainActor` class annotation **and** the `@MainActor` conformance on the non-isolated `TerminalViewDelegate` (`final class …: NSObject, @MainActor TerminalViewDelegate, …`) — dropping either reintroduces "conformance … crosses into main actor-isolated code".
- The package is Swift 6 language mode too; GCD-confined classes in `PocketTmuxAgent` are `@unchecked Sendable` on purpose (state lives on one serial queue).

## Schemes

```sh
cd App && xcodegen generate
xcodebuild build -scheme PocketTmuxMac -destination 'platform=macOS' -derivedDataPath build/Mac -skipPackagePluginValidation
xcodebuild build -scheme pockettmuxd   -destination 'platform=macOS' -derivedDataPath build/Mac -skipPackagePluginValidation
xcodebuild build -scheme PocketTmux -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/Sim -skipPackagePluginValidation
xcodebuild test  -scheme PocketTmux -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/Sim -skipPackagePluginValidation
```

The Mac app is **not sandboxed** (it execs the user's tmux and opens a pty); keep `com.apple.security.app-sandbox` false.

## Signing / Apple account (doyeon hwang personal)

- **Team:** `WQT8B59KJH` (Apple ID `plmokn7034soo@icloud.com`, UID `26H27JRF97`).
- **Cert:** `Apple Development: plmokn7034soo@icloud.com (YHVRJZY9LB)` — `YHVRJZY9LB` is the **person ID**, *not* the team. Never use it as `DEVELOPMENT_TEAM` (`xcodebuild` will fail with "No Account for Team …").
- Provisioning profile `e45d0808-c0b0-49c5-83ca-72812b462f6a.mobileprovision` ("iOS Team Provisioning Profile: com.waylake.pockettmux", team `WQT8B59KJH`) already exists locally and includes the phone's UDID.
- **Do not use manual signing from the CLI** — passing `PROVISIONING_PROFILE_SPECIFIER` globally leaks the profile into SwiftTerm's package targets ("does not support provisioning profiles"). Use automatic signing.

## Build + install on the physical iPhone (verified working)

Device: **iPhone 15 Pro** — `devicectl` ID `0D5A0A22-5B84-51D7-B40F-49752A5E8F90`, `xcodebuild` destination ID `00008130-001919102292001C`.

```sh
cd App
xcodebuild build -scheme PocketTmux \
  -destination 'id=00008130-001919102292001C' \
  -derivedDataPath build/Device \
  -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=WQT8B59KJH \
  -allowProvisioningUpdates

xcrun devicectl device install app \
  --device 0D5A0A22-5B84-51D7-B40F-49752A5E8F90 \
  build/Device/Build/Products/Debug-iphoneos/PocketTmux.app
```

`devicectl device install app` upgrades in place. Seeing the app's `print`s on the phone: `xcrun devicectl device process launch --console --terminate-existing --device 0D5A0A22-… com.waylake.pockettmux`.

## Running an agent for tests

The user's own agent usually listens on **7682** — never restart or kill it. For experiments use another port:

```sh
App/build/Mac/Build/Products/Debug/pockettmuxd --port 7699 --name TestMac     # same token file
POCKETTMUX_PORT=7699 python3 scripts/check-attach-prime.py                       # → ALL OK
```

The e2e script creates and kills its own tmux sessions (`pt_alt`, `pt_norm`, `pt_mouse`, `pt_win`).

## Scrolling — read before touching gestures

Scrolling was dead everywhere (TUI *and* shell scrollback) for one reason:
**`tmux -CC` replays nothing that predates the control client.** No `?1049h`,
no `?1006h`, no pane content. SwiftTerm therefore believed it was on the normal
buffer with mouse off and an empty scrollback, so `gestureRecognizerShouldBegin`
(gated on `isCurrentBufferAlternate`) was hard-wired to `false`.

`ScreenPrimer` (package, `PocketTmuxAgent/Tmux/ScreenPrimer.swift`) fixes it at
the source: on attach and on every window/pane switch the agent reads
`#{alternate_on}` / `#{mouse_any_flag}` / `#{mouse_sgr_flag}` /
`#{keypad_cursor_flag}` / `#{cursor_x}` / `#{cursor_y}` and `capture-pane -p -e`,
and sends the equivalent escapes + content as a `screen{reset}` frame. Don't
"fix" scrolling in the gesture recognizers — check that priming is still
happening first: `python3 scripts/check-attach-prime.py`. Full write-up:
`docs/TROUBLESHOOTING.md` §3.

Second trap: SwiftTerm adds its own mouse-drag pan once mouse mode is on. The
swipe pan's delegate makes **every other pan on the view require it to fail**
(`gestureRecognizer(_:shouldBeRequiredToFailBy:)`) — don't reintroduce a
`require(toFail:)` on just the scroll pan, and don't disable `allowMouseReporting`
(taps → clicks in TUIs depend on it).

Third trap: feed screen bytes through `TerminalView.feed(byteArray:)`, never
`getTerminal().feed(...)`. Since SwiftTerm 1.20 only the view's `feed` queues a
display update; bytes fed straight into the engine land in the buffer but stay
invisible until an unrelated redraw (a swipe, a rotation) — the symptom is a
blank terminal with the caret at 0,0 while `CLIENT: feed …` lines keep coming.

## Window size — read before touching resize

A tmux window has one size shared by all clients. While a phone is attached the
agent pins every window the phone looks at (`resize-window -x -y` +
`window-size manual`) and unpins them on detach (`TmuxControl.teardown`). Don't
send `refresh-client -C` alone (ignored under `manual`) and don't force sizes on
attach (the Mac terminal visibly jumps) — `docs/TROUBLESHOOTING.md` §2.
