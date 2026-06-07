# Input-Aware VNC Request Pacing Summary - 2026-06-08

## Reproduction

The focused regression first failed with the current architecture: after a
session was active, enabling focused Compose or transient pointer/direct-key
interaction still left the VNC stream pacing at the ordinary 30 fps-class
visual cadence. That meant the app could coalesce or delay frame application,
but it had already spent request, receive, decode, and queue work while UIKit
IME or local viewport interaction needed the device.

## Design

Use one active-session service level before both expensive stages:

- `visual`: ordinary VNC visual cadence.
- `viewportNavigation`: existing viewport-aware VNC request policy for active
  pinch/pan/trackpad viewport work; transient pointer/direct-key activity uses
  a 20 fps-class request floor.
- `textInput`: focused Compose wins over other interaction reasons and applies
  a 10 fps-class VNC request floor before the next framebuffer update request.

This is intentionally request-side pacing, not only frame-application pacing.
RFB is client-demand-driven, and RFC 6143 explicitly allows fast clients to
regulate incremental framebuffer update request rate to avoid excessive
traffic. The app therefore slows work at the protocol backpressure point while
keeping VNC alive for cursor/liveness/fallback.

## Change

- Added shared `textInputContentFrameIntervalSeconds` and
  `transientInputContentFrameIntervalSeconds` pacing defaults.
- Extended `SessionStreamPacingPolicy` with an `activeInputPacingInterval`
  floor and `usesActiveInputPacing` classification.
- Applied current frame-delivery priority to VNC stream request pacing:
  Compose focus -> 10 Hz-class; transient input -> 20 Hz-class; viewport
  gestures -> existing viewport-aware full/partial policy.
- Added `activeInputPacingSampleCount` to diagnostic schema v33 so physical
  iPhone logs can show whether the protection engaged without exposing text,
  keysyms, pointer coordinates, pixels, endpoints, byte counts, or exact
  timings.

## Verification

Focused reproduction/regression:

```bash
swift test --filter 'NaruRemoteAppTests.NaruRemoteAppModelTests/testSessionStreamPacingPolicyUsesActiveInputFloor|NaruRemoteAppTests.NaruRemoteAppModelTests/testComposeFocusPacesVNCRequestsBeforeDecodeWork|NaruRemoteAppTests.NaruRemoteAppModelTests/testTransientInputPacesVNCRequestsBeforeDecodeWork'
```

Result: pass.

Diagnostic/snapshot regression:

```bash
swift test --filter 'NaruRemoteAppTests.NaruRemoteAppSnapshotTests/testSessionStreamStatsBuildSafeDiagnosticPerformanceReport|NaruRemoteCoreTests.DiagnosticExportTests/testRenderCollectionJSONIncludesSafeStreamPerformanceSummary|NaruRemoteCoreTests.DiagnosticExportTests/testStreamPerformanceReportSanitizesReceiveTimingBuckets|NaruRemoteCoreTests.DiagnosticExportTests/testStreamPerformanceReportDecodesMissingNewerFieldsAsSafeDefaults'
```

Result: pass.

Frame-delivery priority regression:

```bash
swift test --filter NaruRemoteAppTests.SessionFrameDeliveryPriorityModelTests
```

Result: pass.

Helper-primary VNC control-plane guard:

```bash
swift test --filter NaruRemoteAppTests.NaruRemoteAppModelTests/testHelperVideoPrimarySamplesVNCFallbackAndKeepsControlPathActive
```

Result: pass.

Full suite:

```bash
swift test
```

Result: pass on rerun; 1253 tests, 14 skipped, 0 failures.

Live helper-video gate:

```bash
scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

Result: blocked before true helper-video capture by local setup gates:

- `overallGateState`: `blockedByScreenRecordingPermission`
- Screen Recording watch: `timedOut`
- final helper permission: `missing`
- physical iPhone: connected, but Xcode account and provisioning profile are
  missing, so install/build preflight remains blocked

Safe JSON output:
`artifacts/benchmarks/2026-06-08-helper-video-live-gate-input-aware.json`.

## Privacy Boundary

This artifact contains no host identity, credentials, ports, command text,
draft text, marked text, keysyms, pointer coordinates, dimensions, pixels, byte
counts, raw stdout/stderr, raw network errors, raw OS errors, or exact live
timing samples.

## Remaining Gate

True helper-video ScreenCaptureKit capture and physical iPhone install remain
gated by macOS Screen Recording permission for the helper app plus Xcode
account/provisioning setup. After those are fixed, rerun
`scripts/run-naru-live-benchmark.sh helper-video-live-gate` to collect the
actual helper-video FPS/latency gate.
