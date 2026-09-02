## Summary
<!-- 1–3 sentences: what changed and why -->

## Type
- [ ] Feature (new capability)
- [ ] Fix (bug, behavior)
- [ ] Refactor (no behavior change)
- [ ] Docs
- [ ] CI / build
- [ ] Other: ___

## Related
- Closes / relates to: #___

## Self-check
- [ ] `cd App && xcodegen generate` — the project regenerates cleanly
- [ ] Package: `swift test --package-path App/PocketTmuxKit` passes (if `PocketTmuxKit/` changed)
- [ ] iPhone: `xcodebuild -project App/PocketTmux.xcodeproj -scheme PocketTmux -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation test`
- [ ] Mac: `xcodebuild -project App/PocketTmux.xcodeproj -scheme PocketTmuxMac -destination 'platform=macOS' -skipPackagePluginValidation build` (and `-scheme pockettmuxd` if the agent changed)
- [ ] `swiftlint lint` is clean (or the exception is documented)
- [ ] If behavior/protocol changed → `CHANGELOG.md` updated + the relevant `docs/` updated
- [ ] If UI → a screenshot (simulator / Mac) attached

## Notes for review
<!-- Anything the reviewer should know: trade-offs, follow-ups, known limits -->
