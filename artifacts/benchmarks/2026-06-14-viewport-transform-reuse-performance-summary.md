# Viewport Transform Reuse Performance Summary

Date: 2026-06-14

## Scope

Zoomed iPhone sessions apply local viewport transforms on the UIKit/Metal
surface so pinch, pan, and trackpad cursor-follow movement stay immediate while
remote frames arrive on separate worker paths. This benchmark targets repeated
zoomed pan updates while the fallback trackpad cursor overlay is visible.

## Change

- Reuse the already computed `ViewportTransform` when applying the Metal host
  layer transform.
- Pass that same transform to immediate viewport publication and hot-cursor
  overlay placement instead of rebuilding equivalent geometry on every sample.
- Apply the same reuse pattern to pinch, zoomed pan, deceleration, external
  zoom/pan sync, and trackpad auto-pan paths.
- Keep layout-driven resyncs on the existing current-state path, because those
  are not per-gesture hot-path samples.
- Add an iPhone simulator benchmark for zoomed viewport transform updates with
  a visible fallback hot cursor, and include it in `simulator-input-viewport-gate`.

## Benchmark Evidence

Command shape:

```bash
env NARU_RUN_SIM_BENCHMARKS=1 \
  NARU_SIM_BENCHMARK_ITERATIONS=5 \
  NARU_HELPER_VIDEO_INPUT_BENCHMARK_SAMPLES=5000 \
  xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
    -only-testing:NaruRemoteBenchmarkTests/MetalFramebufferHotCursorOverlayBenchmarkTests/testZoomedViewportTransformWithFallbackHotCursorBenchmark \
    test
```

Before/after comparison used the same simulator, sample count, and iteration
count. Raw timing samples stay out of the artifact; the relative aggregate
change was:

| Metric | Improvement |
| --- | ---: |
| Monotonic wall time | about 12% lower |
| CPU time | about 12% lower |
| CPU cycles | about 9% lower |
| CPU instructions retired | about 8% lower |

Additional gate:

```bash
./scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

The simulator gate passed with iPhone and iPad simulator coverage after the new
benchmark was added to the viewport hot-path step.

## Interpretation

This is a local interaction hot-path improvement, not a VNC receive-path or
network traffic fix. It reduces repeated geometry and overlay work in the exact
local layer that users feel as zoom/pan and trackpad cursor-follow latency, and
keeps the larger streaming work pointed at helper-video and server cadence
gates.

## Privacy

This artifact stores only synthetic benchmark shape, relative aggregate
improvement, and safe gate status. It does not store host identity,
credentials, endpoints, device identifiers, profile identifiers, pixels, frame
dimensions, coordinates, byte counts, exact timings, raw logs, composed text,
or clipboard contents.
