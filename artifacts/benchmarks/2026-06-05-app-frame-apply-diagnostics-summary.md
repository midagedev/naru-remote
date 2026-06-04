# 2026-06-05 App Frame-Apply Diagnostics Summary

## Trigger

Long-running goal: make sustained iPhone VNC sessions practical under heat,
low-FPS, and stutter reports. Existing diagnostics split RFB receive timing into
network-read and client-processing buckets, but they did not show whether the
app's MainActor frame-apply path was the local bottleneck after a frame had
already been decoded.

## Research Direction

- RFC 6143 keeps normal framebuffer updates demand-driven by the client, so
  Naru can reduce follow-up request pressure when local work is repeatedly slow.
- Apple frame-rate guidance frames a 60 Hz render budget as about 16.67 ms; a
  repeated app-apply bucket above the interactive threshold is therefore a
  useful local pressure signal for stutter triage.
- Apple power guidance supports reducing update/network frequency under power
  pressure; Naru reuses the existing temporary power-saver pacing floor rather
  than changing persisted viewer settings.

## Change

- Diagnostic schema v11 adds safe app frame-apply aggregate timing:
  sample count plus average/max `notMeasured|subFrame|interactive|lagging|stalled`
  buckets.
- The app records MainActor frame-apply time after each delivered frame,
  covering session-state publication, preview throttling, framebuffer forwarding,
  cursor/liveness bookkeeping, and PiP/renderer handoff.
- Adaptive client-pressure pacing now treats repeated lagging app-apply content
  frames the same way it already treated repeated lagging client-processing
  frames: subsequent requests temporarily use the power-saver pacing floor.

## Privacy Boundary

The app does not export raw milliseconds, raw samples, dimensions, coordinates,
pixels, byte counts, target identity, device power state, or raw errors. Raw
timing is used only in memory while the stream is active.

## Verification

- Focused diagnostic/app-model tests:
  - `swift test --filter NaruRemoteAppSnapshotTests --filter NaruRemoteAppModelTests/testSessionStreamPressurePacingState --filter NaruRemoteAppModelTests/testAppAdaptiveClientPressurePacing --filter NaruRemoteAppModelTests/testActiveSessionExportIncludesSafeStreamPerformanceSummary --filter DiagnosticExportTests/testRenderCollectionJSONIncludesSafeStreamPerformanceSummary --filter DiagnosticExportTests/testStreamPerformanceReport --filter DiagnosticExportTests/testRenderSharePayloadIncludesPlainTextAndCollectionJSON`
  - Result: passed, 26 tests, 0 failures.
- Full package tests:
  - `swift test`
  - Result: passed, 627 tests, 10 skipped, 0 failures.
- iOS simulator app build:
  - `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build`
  - Result: passed.
- Live Mac VNC connect-path smoke:
  - `LiveMacRFBSmokeTests/testStreamingSessionMirrorsConnectButtonPathAgainstRealMac`
  - Result: passed, connectSession ~= 1.16 s, firstFramePump ~= 3.38 s.

## Remaining Risk

This improves observability and automatic local-pressure backoff, but it does
not by itself prove physical iPhone thermal comfort. The next real-device report
should now indicate whether the bottleneck is receive/decode, app frame apply,
renderer upload shape, server encoding mix, or request pacing.
