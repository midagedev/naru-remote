# Hot Cursor Overlay Performance Summary

Date: 2026-06-14

## Scope

Trackpad mode uses a UIKit-hosted hot cursor overlay so cursor movement can
follow touch input without waiting for SwiftUI publication. This benchmark
targets the fallback cursor path used when the server cursor image is not yet
available.

## Change

- Cache the fallback cursor symbol image instead of asking UIKit for it on
  every cursor sample.
- Skip repeated `image`, `bounds`, hidden-state, and subview-front updates when
  the cursor overlay already has the requested values.
- Keep cursor `center` updates immediate so the visible cursor position still
  follows every trackpad sample.
- Add an iPhone simulator benchmark for repeated fallback hot-cursor overlay
  updates and include it in `simulator-input-viewport-gate`.

## Benchmark Evidence

Command shape:

```bash
env NARU_RUN_SIM_BENCHMARKS=1 \
  NARU_SIM_BENCHMARK_ITERATIONS=5 \
  NARU_HELPER_VIDEO_INPUT_BENCHMARK_SAMPLES=5000 \
  xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
    -only-testing:NaruRemoteBenchmarkTests/MetalFramebufferHotCursorOverlayBenchmarkTests/testFallbackHotCursorOverlayUpdateBenchmark \
    test
```

Before/after comparison used the same simulator, sample count, and iteration
count. The benchmark showed a clear improvement:

| Metric | Improvement |
| --- | ---: |
| Monotonic wall time | about 42% lower |
| CPU time | about 41% lower |
| CPU cycles | about 41% lower |
| CPU instructions retired | about 37% lower |

## Interpretation

This is not a visual-stream FPS fix by itself. It removes repeated UIKit work
from the trackpad cursor hot path, which directly supports the product target
that zoomed trackpad movement and cursor-follow pan should stay local and
responsive while remote frames arrive asynchronously.

## Privacy

This artifact stores only synthetic benchmark shape and relative aggregate
improvement. It does not store host identity, credentials, endpoints, device
identifiers, profile identifiers, pixels, frame dimensions, coordinates, byte
counts, exact timings, raw logs, composed text, or clipboard contents.
