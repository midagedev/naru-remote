# PiP Zoomed Viewport Crop Performance Summary

Date: 2026-06-16 KST

## Scope

This artifact records a focused simulator/host benchmark for the PiP Watch
zoomed viewport pixel-buffer path. It covers the local crop/resample write used
when PiP follows the user's zoomed/panned focus instead of showing the full
framebuffer.

The change keeps the existing output semantics: PiP still writes a stable
full-size BGRA pixel buffer, but the cropped source pixels are read through
unsafe row/column pointers instead of nested `Array` subscript lookups.

## Benchmark Command

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_SIM_BENCHMARK_WIDTH=1920 \
NARU_SIM_BENCHMARK_HEIGHT=1080 \
NARU_PIP_SAMPLE_BUFFER_BENCHMARK_SAMPLES=20 \
swift test --filter PiPWatchSampleBufferFactoryBenchmarkTests/testZoomedViewportPixelBufferFactoryBenchmark
```

The benchmark renders a 2x zoomed centered PiP viewport from a synthetic
1920x1080 framebuffer into a full-size BGRA CoreVideo pixel buffer.

## Results

| Metric | Baseline | Current | Delta |
| --- | ---: | ---: | ---: |
| Clock monotonic time | 5.701 s | 4.973 s | -12.8% |
| CPU time | 5.658 s | 4.928 s | -12.9% |
| CPU cycles | 18,204,829.073 kC | 15,686,431.865 kC | -13.8% |
| Instructions retired | 106,485,484.110 kI | 94,748,328.079 kI | -11.0% |
| Peak physical memory | 31,324.723 kB | 31,393.536 kB | not improved |

## Verification

```bash
swift test --filter PiPWatchSampleBufferRendererTests
```

The focused renderer suite passes 8 tests, including BGRA byte order,
zoomed/panned viewport output, sample-buffer readiness, and renderer
presentation-time behavior.

The benchmark target now includes
`testZoomedViewportPixelBufferFactoryBenchmark` as the regression guard for
this non-full-frame PiP path. The benchmark remains opt-in and skips unless
`NARU_RUN_SIM_BENCHMARKS=1` is present.

## Rejected Experiments

- Helper-video app-runner snapshot avoidance: rejected because replacing a few
  `model.snapshot` reads with direct `NaruRemoteAppModel` property reads did
  not reduce the app-runner benchmark. Instructions increased slightly and CPU
  cycles were noisy.
- Helper-video AVCC length-prefix micro-optimization: rejected because
  reserving the AVCC payload and appending raw length bytes measured slower
  than the existing `Data(bytes:count:)` prefix append in the
  sample-buffer-factory benchmark.

Do not repeat either rejected experiment unless a later profile shows that
snapshot construction or AVCC length-prefix construction has become a dominant
cost.

## Privacy

This artifact records only aggregate CPU/time/memory metrics, fixed synthetic
dimensions, fixed sample counts, and fixed XCTest names. It does not include
screenshots, framebuffer pixels, target hostnames, credentials, helper tokens,
profile fingerprints, device identifiers, raw connection payloads, Compose
text, keysyms, pointer coordinates from a real session, clipboard contents, or
raw Xcode logs.
