# PocketTmux — CLAUDE.md

Build/install notes for this repo. General contributing workflow lives in [CONTRIBUTING.md](CONTRIBUTING.md); design docs in `docs/`.

## Build prerequisites (gotchas)

- **Xcode 26.2** is the baseline. SwiftTerm is resolved at **1.20.0** (`Project.yml`: `from: 1.19.0`).
- **Every `xcodebuild` invocation needs `-skipPackagePluginValidation`.** SwiftTerm 1.20.0 ships a build-tool plugin (`SwiftTermBuildInfoPlugin`) whose "Validate plug-in" step fails on Xcode 26.2, aborting the build *before* compilation — even for the simulator. Without the flag you only see `Validate plug-in “SwiftTermBuildInfoPlugin” …` + a base64 blob, no useful error. The plugin only generates build-info constants from a trusted, pinned source, so skipping validation is safe.
- `Project.yml` is the source of truth; regenerate the (git-ignored) project with `xcodegen generate` after editing it. If build settings look stale, regenerate first.
- The project sets `SWIFT_STRICT_CONCURRENCY: minimal`, but Swift 6 language mode still enforces some isolation errors. `TerminalCoordinator` must keep the `@MainActor` class annotation **and** the `@MainActor` conformance on the non-isolated `TerminalViewDelegate` (`final class …: NSObject, @MainActor TerminalViewDelegate, …`) — dropping either reintroduces "conformance … crosses into main actor-isolated code".

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

Quick compile check (no signing needed): `xcodebuild build -scheme PocketTmux -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/Sim -skipPackagePluginValidation`.

`devicectl device install app` upgrades in place — a plain re-install of the new build over the old one.
