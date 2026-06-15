# Trackpad Command Batch Performance Summary

Date: 2026-06-16

## Scope

Zoomed trackpad movement is part of the local interaction path users feel as
"half-beat late" pan/cursor-follow latency. This artifact covers the pure
viewport/input hot path only. It does not claim VNC receive-path, network
traffic, helper-video FPS, or physical iPhone thermal improvement.

## Change

- Store pointer commands in `RFBPointerCommandBatch` so the common 0, 1, and 2
  command cases do not require an array in the trackpad drag hot path.
- Keep `PointerGestureOutcome.commands` as a compatibility/debug view while
  production trackpad dispatch uses the batch directly.
- Compute zoomed trackpad reveal deltas directly from the coupled transform's
  cursor view point and clamped target pan, avoiding an extra temporary
  `ViewportTransform` while preserving the existing damping and finger-paced
  cursor tests.

## Benchmark Evidence

Command shape:

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
  NARU_SIM_BENCHMARK_ITERATIONS=5 \
  NARU_HELPER_VIDEO_INPUT_BENCHMARK_SAMPLES=5000 \
  swift test --filter HelperVideoViewportInputHotPathBenchmarkTests/testPureViewportInputHotPathThroughputBenchmark
```

The baseline was run from a detached `/tmp/naru-remote-benchmark-baseline`
worktree at `origin/main` (`f7f562b6`). The current run used the same sample
count and iteration count immediately after the baseline run.

| Metric | Baseline | Current | Delta |
| --- | ---: | ---: | ---: |
| Clock monotonic time | `0.002687 s` | `0.002463 s` | about 8% lower |
| CPU time | `0.003013 s` | `0.002717 s` | about 10% lower |
| CPU cycles | `9755.558 kC` | `8830.766 kC` | about 9% lower |
| CPU instructions retired | `39314.492 kI` | `35345.626 kI` | about 10% lower |
| Peak physical memory | `5870.541 kB` | `5811.430 kB` | not claimed |

Focused behavior gate:

```bash
swift test --filter 'PointerGestureResolverTests|ViewportInputHotPathDriverTests|HelperVideoViewportInputHotPathBenchmarkTests/testPureInputHotPathPublishesImmediateTransforms'
```

This passed 23 focused pointer, viewport, and benchmark smoke tests after the
change.

## Related Rejected Experiment

A range-based app-side H.264 Annex-B sample-buffer parser was also tried before
this artifact. It avoided one intermediate NAL `Data` copy, but the focused
sample-buffer benchmark only moved by about 0.4% on CPU cycles, about 0.3% on
retired instructions, and had noisy wall-clock behavior. It was reverted and
should not be repeated unless a future profiler shows per-NAL `Data` material
copying has become a dominant cost again.

## Interpretation

This is a small but repeatable local interaction win in the exact resolver path
used by trackpad cursor movement and zoomed viewport follow-pan. It should make
each gesture sample cheaper, but product Green still requires simulator gate,
physical iPhone hand-feel, helper-video primary validation, and VNC/control
fallback evidence.

## Privacy

This artifact stores only aggregate synthetic benchmark metrics, fixed sample
counts, fixed test names, and a commit identifier. It does not store host
identity, credentials, endpoints, device identifiers, profile identifiers,
frame pixels, screenshots, display dimensions, pointer coordinates from a real
session, byte counts, exact live-frame timing series, Compose text, keysyms,
clipboard contents, or raw network errors.
