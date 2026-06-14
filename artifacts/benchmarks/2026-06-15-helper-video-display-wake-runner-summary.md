# Helper Video Display Wake Runner Summary

Date: 2026-06-15 KST

## Question

The helper-video ScreenCaptureKit path regressed from previous ready evidence:
`helper-video-live-gate` was blocked by helper screen capture even though Screen
Recording permission was granted. Standalone probes showed the screen capture
transport timing out or stalling before the app could decode frames.

## Finding

The Mac can temporarily report no active display sources when the screen is
sleeping or idle. In that state, ScreenCaptureKit screen probes either time out
or emit non-displayable/stalled capture results. Wrapping the true screen gates
with a short display wake and keeping an animated stimulus window visible makes
the same helper path produce frames again.

## Change

- `helper-screen-probe` now runs with the same animated stimulus window used by
  the sustained screen probe.
- Helper-video screen probe and app-bootstrap benchmark modes now start a
  privacy-safe `caffeinate -dimsu` display wake window before capture.
- The display wake defaults are configurable with fixed, non-sensitive labels:
  `NARU_HELPER_VIDEO_DISPLAY_WAKE_SECONDS` and
  `NARU_HELPER_VIDEO_DISPLAY_WAKE_SETTLE_SECONDS`.
- The external helper frame-count timeout budget was widened slightly so the
  short ScreenCaptureKit probe is not marked as transport failed before the
  helper has a chance to emit the first encoded frames.

## Before

Same-session pre-change evidence:

- `helper-screen-probe`: `fail`, `transportBlocked`,
  `helper-video-external-helper-timed-out`
- `helper-sustained-screen-probe`: `fail`, `transportBlocked` or stalled screen
  capture
- `helper-screen-app-bootstrap-benchmark`: `failed`, requested `30` frames,
  `screen-capturekit-app-bootstrap-failed`
- `helper-video-live-gate`: `blockedByHelperScreenCapture`

## After

Commands:

```bash
bash scripts/run-naru-live-benchmark.sh helper-screen-probe
bash scripts/run-naru-live-benchmark.sh helper-sustained-screen-probe
bash scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark
bash scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

Safe result:

- `helper-screen-probe`: `pass`, `readyForPhysicalGate`, no issue codes
- `helper-sustained-screen-probe`: `pass`, `readyForPhysicalGate`, no issue
  codes
- `helper-screen-app-bootstrap-benchmark`: `passed`, requested `30` frames, no
  issue codes
- `helper-video-live-gate.helperVideoGate.screenCaptureVerdict`: `pass`
- `helper-video-live-gate.helperVideoGate.sustainedScreenCaptureVerdict`: `pass`
- `helper-video-live-gate.appBootstrapBenchmark.status`: `passed`
- `helper-video-live-gate.gateSummary.overallGateState`:
  `blockedByPhysicalIPhoneGate`
- `helper-video-live-gate.gateSummary.primaryBlockedGateLabels`:
  `physical-iphone-gate-blocked`

Interpretation:

The helper-video screen capture gate is no longer the primary blocker in this
environment. The next gate is again physical iPhone signing/provisioning, which
is the expected blocker after helper-video readiness.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
swift test --filter NaruHelperVideoStreamFramePipelineTests/testFrameStreamEmitsSafeStallWhenScreenCaptureFailureHappensBeforeFirstAccessUnit
bash scripts/run-naru-live-benchmark.sh helper-screen-probe
bash scripts/run-naru-live-benchmark.sh helper-sustained-screen-probe
bash scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark
bash scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

## Safety

The artifact records only fixed labels and aggregate pass/fail states. It does
not include helper executable paths, endpoints, credentials, raw XCTest output,
device identifiers, display dimensions, pixels, frame payloads, byte counts,
exact timings, pointer coordinates, text, clipboard contents, or raw OS errors.
