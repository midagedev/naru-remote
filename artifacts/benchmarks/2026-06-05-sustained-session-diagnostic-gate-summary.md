# Sustained Session Diagnostic Gate Summary - 2026-06-05

Target: `iphone-sustained-usability-v2`

Scope:
- Diagnostic JSON schema v25.
- Top-level sustained session assessment for physical iPhone T390 logs.
- Safe issue-code bridge from app stream metrics, viewport hints, thermal
  state, and Compose readiness.

Safe changes:
- Added `sustainedSessionAssessment` with fixed target, verdict, and issue-code
  labels.
- Added a safe `contentFramesPerSecondBucket` to stream performance diagnostics.
- Kept exact content FPS memory-only; diagnostics export only the fixed issue
  code chosen from that value.
- Connected `NaruRemoteAppModel` diagnostic export to generate the assessment
  from the active session's stream stats and input report.

Verification completed in this PR:
- `swift test --filter DiagnosticExportTests`
- `swift test --filter NaruRemoteAppSnapshotTests/testSessionStreamStatsBuildSafeDiagnosticPerformanceReport`
- `swift test --filter NaruRemoteAppModelTests/testActiveSessionExportIncludesSafeStreamPerformanceSummary`

Residual gate:
- T390 still requires a 10 minute physical iPhone run. The new assessment is
  intended to make that log directly actionable by naming fixed failure causes
  such as content frame rate, receive/apply/renderer pressure, thermal pressure,
  viewport pressure, or Compose route/preparation pressure.

Privacy:
- This artifact intentionally contains only fixed field names, fixed issue-code
  labels, test names, and target names. It contains no host identity,
  credentials, framebuffer dimensions, coordinates, pixels, cursor pixels, byte
  counts, raw FPS, raw timings, raw samples, raw payloads, draft text, marked
  text, IME state, hidden preflight contents, or raw error text.
