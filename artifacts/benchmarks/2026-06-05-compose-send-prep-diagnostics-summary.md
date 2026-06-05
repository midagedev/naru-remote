# Compose Send Preparation Diagnostics Summary - 2026-06-05

Target: `iphone-sustained-usability-v2`

Scope:
- Diagnostic JSON schema v24.
- Local Compose Send preparation mode/count/timing bucket.
- T390 physical iPhone input-delay evidence.

Safe changes:
- Added `ComposeSendPreparationReport` with fixed mode labels:
  `fastSnapshot` and `markedTextStabilization`.
- `RemoteInputDockView` records the preparation report after bounded
  stabilization reads, after final draft synchronization, and before paste
  dispatch.
- `NaruRemoteAppModel` includes the latest preparation report in diagnostic
  input JSON and clears it when the user edits the draft or changes sessions.
- `DiagnosticInputReport` exports only mode, bounded snapshot count, and coarse
  `DiagnosticTimingBucket`.

Verification completed in this PR:
- `swift test --filter RemoteInputDockSyncPolicyTests/testComposeSendPreparationPlan`
- `swift test --filter NaruRemoteAppModelTests/testDiagnosticExportIncludesComposeSendPreparationWithoutDraftText`
- `swift test --filter NaruRemoteAppModelTests/testEditingComposeDraftClearsStaleComposeSendPreparationDiagnostic`
- `swift test --filter NaruRemoteAppModelTests/testComposeSendPreparationRecordedAfterFinalDraftSyncSurvivesExport`
- `swift test --filter DiagnosticExportTests`
- `swift test` (829 tests, 10 skipped)
- `xcodegen generate --spec project.yml`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

Residual gate:
- T390 still needs a physical iPhone run. The new fields are intended to tell
  whether Compose Send delay came from marked-text stabilization before paste
  dispatch or from the later injection/remote-app path.

Privacy:
- This artifact intentionally contains only fixed field names, fixed mode
  labels, test names, and target names. It contains no host identity,
  credentials, framebuffer dimensions, coordinates, pixels, cursor pixels, byte
  counts, raw samples, raw payloads, draft text, marked text, raw IME state, or
  raw error text.
