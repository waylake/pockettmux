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
- [ ] Build: `xcodebuild -project App/PocketTmux.xcodeproj -scheme PocketTmux -destination 'platform=iOS Simulator,name=iPhone 16' build`
- [ ] Test: `... test` (and new tests for the change, if there's logic)
- [ ] `swiftlint lint` is clean (or the exception is documented)
- [ ] If behavior/protocol changed → `CHANGELOG.md` updated + the relevant `docs/` updated
- [ ] If UI → a screenshot (simulator) attached

## Notes for review
<!-- Anything the reviewer should know: trade-offs, follow-ups, known limits -->
