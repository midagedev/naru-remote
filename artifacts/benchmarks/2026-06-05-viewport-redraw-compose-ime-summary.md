# 2026-06-05 Viewport Redraw / Compose IME Follow-up

## Trigger

Physical iPhone feedback after the renderer-upload diagnostics PR still reported
unnatural zoom/pan motion and unreliable Compose input.

## Changes

- During active Metal-hosted viewport gestures, incoming VNC frames now mark a
  deferred flush instead of scheduling another redraw while pending framebuffer
  uploads are suspended. Local pinch/pan/deceleration redraws remain owned by
  the viewport display link.
- Viewport redraw and deceleration display links now prefer the device screen
  maximum frame rate, allowing ProMotion devices to use their native interactive
  cadence for local navigation.
- Compose Send now snapshots active marked text before `UITextView.unmarkText()`
  and falls back to that marked text if UIKit briefly reports an empty committed
  string. An actually empty editor remains empty, avoiding stale fallback sends.

## Verification

- `swift test --filter RemoteInputDockSyncPolicyTests --filter ViewportGestureRedrawThrottleTests`
  - 14 tests passed.
- `swift test`
  - 636 tests passed, 10 skipped, 0 failures.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Build succeeded.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - 4 benchmark tests passed.
  - Monotonic averages: full allocation/upload about 3.0 ms,
    steady-state full upload about 0.45 ms, small dirty rect about
    0.018 ms, same-frame upload-gate skip about 0.003 ms.

## Residual Risk

This is still simulator/build verification plus model-level tests. The next
high-value check is a physical iPhone run against the Mac VNC server while
recording the v12 diagnostic export, especially renderer upload buckets and
whether the Korean/CJK sent paste matches the compact dock draft exactly.
