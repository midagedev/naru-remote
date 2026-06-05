# 2026-06-05 Smooth Viewport + Compose Regression Summary

## Trigger

Physical iPhone feedback after the previous viewport/Compose pass: zooming and
panning still felt unnatural and choppy, and Compose input still did not work
properly.

## Findings

- The spec/research trail already said active viewport interaction should use an
  8 Hz-class content cadence, but the shared production constant had drifted
  back to 15 Hz.
- The app's Metal host already applies zoom/pan locally with a `UIView`
  transform while the `MTKView` draws remote frames on demand. Extra mid-gesture
  remote frame decode/upload work can therefore compete with touch tracking
  without improving the finger-following path.
- UTF-8 Compose payloads were rejected when the VNC server had not confirmed
  UTF-8 clipboard support. That made helper-less macOS Screen Sharing style
  setups fail before even attempting the legacy paste path.

## Changes

- Restored `StreamPressurePacingDefaults.viewportInteractionContentFrameIntervalSeconds`
  to `1.0 / 8.0`, shared by the app and `VNCLiveBenchmark`.
- Added a regression test so the active viewport-interaction cadence stays
  8 Hz-class instead of silently drifting back upward.
- Changed the UTF-8 clipboard policy so `.unknown` support allows best-effort
  legacy VNC paste with `unknown` status and a warning message.
- Kept explicit `.unsupported` UTF-8 clipboard support as a failure with
  helper-aware diagnostics.

## Live Benchmark

Command shape:

```bash
swift run VNCLiveBenchmark \
  --ask-password \
  --first-frame-profiles none \
  --stream-shape-profiles local-low-latency \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 6 \
  --stream-shape-client-pressure app \
  --stream-shape-viewport-interaction app \
  --json
```

Result: passed against the redacted local target.

Key safe aggregates:

- schema: 26
- viewport interaction content interval: 0.125 seconds
- viewport interaction pacing: 11/11 samples, 1000 permille
- transport: request-response
- received samples: 11
- content updates: 10
- empty updates: 1
- actual encoding mix: ZRLE rectangles only
- renderer uploads: 90% partial, 10% full
- average update latency: 406 ms
- p95 update latency: 2519 ms
- very slow updates: 1
- continuous-updates probe: failed with safe catalog label

## Verification

- `swift test --filter TextInjectionAdapterTests`
  - Result: passed, 8 tests, 0 failures.
- `swift test --filter NaruRemoteAppModelTests/testModelAllowsBestEffortUTF8ComposeWhenClipboardSupportIsUnconfirmed`
  - Result: passed, 1 test, 0 failures.
- `swift test --filter RemoteInputDockSyncPolicyTests`
  - Result: passed, 52 tests, 0 failures.
- `swift test --filter ViewportGestureRedrawThrottleTests`
  - Result: passed, 7 tests, 0 failures.
- `swift test --filter BenchmarkStreamShapePacingPolicyTests`
  - Result: passed, 18 tests, 0 failures.
- `swift test --filter NaruRemoteAppModelTests`
  - Result: passed, 81 tests, 0 failures.
- `swift test --filter TrackpadModeModelTests`
  - Result: passed, 11 tests, 0 failures.
- `swift test`
  - Result: passed, 770 tests, 10 skipped, 0 failures.

## Remaining Risk

- Physical iPhone hand feel still needs retesting because simulator/unit tests
  cannot measure finger-to-glass latency or thermal throttling.
- Best-effort legacy UTF-8 paste is intentionally `unknown`, not confirmed
  success. Some VNC servers may still paste mojibake until helper or confirmed
  UTF-8 clipboard support is available.
