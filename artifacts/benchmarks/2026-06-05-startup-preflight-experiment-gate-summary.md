# Startup Preflight Experiment Gate Summary - 2026-06-05

Target: `iphone-sustained-usability-v2`

Scope:
- Diagnostic JSON schema v26.
- Persisted viewer setting for the app-side one-hidden-frame startup preflight
  experiment.
- Safe physical-device comparison fields for T390 disabled vs one-hidden-frame
  runs.

Safe changes:
- Added `startupPreflightMode` to app settings with default disabled and
  default `{}` on-disk encoding.
- Wired the live app stream loop to use the persisted setting when no test
  preflight override is injected.
- Kept startup preflight bounded to one hidden post-first-frame incremental
  update and left production default disabled.
- Added top-level `viewerStartupPreflightMode` and stream-performance
  startup preflight requested/consumed/outcome fields.
- Kept hidden preflight frames out of framebuffer state, previews, regular
  delivered/content frame stats, and renderer upload paths.

Verification completed in this PR:
- `swift test --filter AppSettingsCodableTests`
- `swift test --filter DiagnosticExportTests`
- `swift test --filter NaruRemoteAppSnapshotTests/testSessionStreamStatsBuildSafeDiagnosticPerformanceReport`
- `swift test --filter NaruRemoteAppModelTests/testStartupPreflightUsesAppSettingWhenNoOverrideIsInjected`
- `swift test --filter NaruRemoteAppModelTests/testStartupPreflightConsumesHiddenIncrementalAfterFirstVisibleFrame`
- `swift test --filter NaruRemoteAppModelTests/testStartupPreflightContinuesVisibleStreamAfterHiddenIncremental`
- `swift test --filter NaruRemoteAppModelTests/testActiveSessionExportIncludesSafeStreamPerformanceSummary`
- `swift test`
- `xcodegen generate --spec project.yml`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

Residual gate:
- T390 still requires paired physical iPhone runs with startup preflight
  disabled and one-hidden-frame enabled. Only a run with
  `startupPreflightOutcome` = `consumed` should be treated as valid evidence for
  deciding whether startup preflight deserves a production default change.

Privacy:
- This artifact intentionally contains only fixed field names, fixed mode
  labels, bounded counts, fixed outcome labels, test names, and target names.
  It contains no host identity, credentials, framebuffer dimensions,
  coordinates, pixels, cursor pixels, byte counts, raw FPS, hidden frame
  timings, hidden frame contents, raw samples, raw payloads, raw errors, draft
  text, marked text, IME state, or external command output.
