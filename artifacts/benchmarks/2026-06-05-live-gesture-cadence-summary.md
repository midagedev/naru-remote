# 2026-06-05 Live Gesture Cadence Summary

## Trigger

Physical iPhone feedback still reported unnatural, choppy zoom/pan and low
remote-frame perception while using zoomed viewport navigation.

## Research Refresh

- RFC 6143 keeps framebuffer updates request-driven and normally incremental:
  the viewer should keep asking for changed framebuffer content it wants to
  display.
- RFC 6143's Cursor pseudo-encoding exists so a viewer can draw the pointer
  locally and improve perceived performance, but freezing the whole remote
  framebuffer during cursor/viewport motion still makes the desktop feel stale.
- Apple's `UIScrollView` documentation frames pinch/zoom/pan as native
  scroll-view physics. Naru is still using a custom Metal-hosted viewport, so
  the next-best correction is to keep local motion on the compositor path while
  letting bounded live frames continue.
- Apple's `CADisplayLink.preferredFrameRateRange` documentation notes that the
  system may lower callback cadence for hardware, Low Power Mode, thermal, and
  accessibility policy. Naru records safe buckets instead of assuming the
  preferred rate always lands.

## Finding

Two independent freeze gates were active during local viewport interaction:

- The app model paused new RFB framebuffer requests whenever a visible frame
  existed and the viewport was being manipulated.
- Content frames that did arrive during interaction were deferred at the model
  layer until gesture end.

That protected the touch loop, but on a physical phone it can look like the
remote desktop stopped refreshing until the user lifts their finger.

## Change

- Removed the model-level request pause from the active frame stream loop.
- Stopped deferring content-frame publication until gesture end.
- Raised the viewport-interaction content cadence from 8fps to a bounded 15fps.
- Let the Metal host upload the first gesture-time frame and then coalesce to
  the same 15fps cadence, while keeping local zoom/pan presentation on the Core
  Animation compositor path.
- Aligned the `VNCLiveBenchmark` viewport-interaction profile with the app:
  it now models live content/idle cadence floors instead of injecting synthetic
  request-pause windows.

## Verification

- `swift test --filter ViewportGestureRedrawThrottleTests --filter NaruRemoteAppModelTests/testModelKeepsFrameRequestsAliveWithViewportInteractionPacing --filter NaruRemoteAppModelTests/testViewportInteractionPublishesBoundedLiveFramesDuringGesture`
  - Result: passed, 8 tests, 0 failures.
- `swift test --filter BenchmarkStreamShapePacingPolicyTests --filter ViewportGestureRedrawThrottleTests --filter NaruRemoteAppModelTests/testModelKeepsFrameRequestsAliveWithViewportInteractionPacing --filter NaruRemoteAppModelTests/testViewportInteractionPublishesBoundedLiveFramesDuringGesture`
  - Result: passed, 26 tests, 0 failures.
- `swift test --filter SessionViewportViewGeometryTests --filter PointerGestureResolverTests --filter TrackpadModeModelTests`
  - Result: passed, 45 tests, 0 failures.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - Result: passed, 4 tests, 0 failures.
  - Approximate monotonic-time averages: full allocation/upload about 3.0ms,
    steady-state full upload about 0.55ms, small dirty rect about 0.026ms,
    same-frame upload-gate skip at microsecond scale.
- `swift test`
  - Result: passed, 746 tests, 10 skipped, 0 failures.
- `xcodegen generate --spec project.yml`
  - Result: passed.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: passed.

## Residual Risk

This should improve perceived remote-frame continuity during zoomed/trackpad
navigation. It does not yet replace the custom viewport with a real
`UIScrollView` physics surface, and it still needs physical iPhone retesting for
finger-to-glass latency and thermal behavior.
