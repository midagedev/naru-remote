# Viewport Transform Cache Performance Summary

Date: 2026-06-14

## Scope

Helper-video keeps visual frames and local input on separate paths, so the
zoom/pan/trackpad feel depends heavily on the pure viewport input hot path.
This benchmark targets repeated local viewport updates without constructing
UIKit views, Metal layers, or a live network session.

## Change

- Cache `ViewportTransform` fit scale, display scale, content size, and content
  origin when the transform is created.
- Reuse the cached transform geometry for pan-only copies, where framebuffer
  size, view size, zoom scale, and content size do not change.
- Store `ViewportInputHotPathUpdate` change flags when the update is created
  instead of recomputing zoom/pan comparisons at each access site.

## Benchmark Evidence

Command shape:

```bash
env NARU_RUN_SIM_BENCHMARKS=1 \
  NARU_SIM_BENCHMARK_ITERATIONS=5 \
  NARU_HELPER_VIDEO_INPUT_BENCHMARK_SAMPLES=5000 \
  xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
    -only-testing:NaruRemoteBenchmarkTests/HelperVideoViewportInputHotPathBenchmarkTests/testPureViewportInputHotPathThroughputBenchmark \
    test
```

Before/after comparison used the same simulator, benchmark sample count, and
iteration count. The after run was repeated once before treating the result as
PR-worthy. Raw timing samples stay out of the artifact; the relative aggregate
change was:

| Metric | Improvement |
| --- | ---: |
| CPU cycles | about 16% lower |
| CPU instructions retired | about 16% lower |
| CPU time | about 16% lower |

Monotonic wall-clock time is intentionally not used as promotion evidence
because the baseline wall-clock samples had high relative variance. Memory is
also not claimed as an improvement.

Additional focused gate:

```bash
swift test --filter 'ViewportTransformTests|ViewportInputHotPathDriverTests|PointerGestureResolverTests|ViewportRequestRegionPolicyTests'
```

Additional simulator gate slices:

```bash
swift test --filter 'SessionViewportViewGeometryTests|PointerGestureResolverTests|TrackpadModeModelTests|ViewportInputHotPathDriverTests|ViewportGestureRedrawThrottleTests|ViewportRedrawDiagnosticsTests|DiagnosticExportTests|HelperVideoViewportInputHotPathBenchmarkTests|ComposeInputSessionIsolationTests'

env NARU_RUN_SIM_BENCHMARKS=1 \
  NARU_SIM_BENCHMARK_ITERATIONS=5 \
  NARU_HELPER_VIDEO_INPUT_BENCHMARK_SAMPLES=5000 \
  xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
    -only-testing:NaruRemoteBenchmarkTests/HelperVideoViewportInputHotPathBenchmarkTests/testPureViewportInputHotPathThroughputBenchmark \
    -only-testing:NaruRemoteBenchmarkTests/MetalFramebufferHotCursorOverlayBenchmarkTests/testFallbackHotCursorOverlayUpdateBenchmark \
    -only-testing:NaruRemoteBenchmarkTests/MetalFramebufferHotCursorOverlayBenchmarkTests/testZoomedViewportTransformWithFallbackHotCursorBenchmark \
    test
```

The focused Core geometry, pointer, request-region, viewport hot-path, and
benchmark-bundle slices passed after the optimization. A full
`simulator-input-viewport-gate` run was not used as promotion evidence in this
session because its Compose storm UI-test step did not complete before manual
stop; this artifact therefore claims only the focused Core and benchmark slices
above.

## Interpretation

This is a local interaction hot-path improvement, not a VNC receive-path,
network traffic, or live FPS fix. It reduces the repeated geometry work paid
while a user is actively zooming, panning, or using trackpad cursor-follow, and
it preserves the larger product direction: VNC still needs server-cadence or
helper-video work to reach sustained Chrome-Remote-like smoothness.

## Privacy

This artifact stores only synthetic benchmark shape, relative aggregate
improvement, and safe test status. It does not store host identity,
credentials, endpoints, device identifiers, profile identifiers, pixels, frame
dimensions, coordinates, byte counts, exact timings, raw logs, composed text,
or clipboard contents.
