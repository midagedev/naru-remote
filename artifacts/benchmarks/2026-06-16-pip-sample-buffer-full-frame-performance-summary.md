# PiP Sample Buffer Full-Frame Performance Summary

Date: 2026-06-16 KST

## Scope

This artifact records an opt-in benchmark for the PiP Watch sample-buffer
pixel-write path when the viewport covers the full framebuffer. It reduces CPU
and indexing/allocation pressure for PiP/watch sample-buffer creation only. It
does not claim live VNC FPS, helper-video FPS, physical iPhone thermal
behavior, or traffic improvement.

## Commands

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_SIM_BENCHMARK_WIDTH=1920 \
NARU_SIM_BENCHMARK_HEIGHT=1080 \
NARU_PIP_SAMPLE_BUFFER_BENCHMARK_SAMPLES=20 \
swift test --filter PiPWatchSampleBufferFactoryBenchmarkTests/testLegacyFullFramePixelBufferFactoryBenchmark
```

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_SIM_BENCHMARK_WIDTH=1920 \
NARU_SIM_BENCHMARK_HEIGHT=1080 \
NARU_PIP_SAMPLE_BUFFER_BENCHMARK_SAMPLES=20 \
swift test --filter PiPWatchSampleBufferFactoryBenchmarkTests/testFullFramePixelBufferFactoryBenchmark
```

The legacy and optimized cases were run in separate test processes. Each
measured iteration creates 20 synthetic 1920x1080 BGRA pixel buffers from the
same synthetic framebuffer.

## Baseline

The baseline always built identity `sourceColumns` and `sourceRows` arrays,
then used those lookup arrays for every output pixel even when the viewport was
the full framebuffer.

- Clock time: `5.688 s`
- CPU time: `5.640 s`
- CPU cycles: `18194909.654 kC`
- Retired instructions: `106437803.174 kI`
- Peak physical memory: `31265.741 kB`

## Result

The optimized path detects the full-frame viewport and writes directly from the
framebuffer pixel storage into the CoreVideo pixel buffer. Zoomed/cropped
viewports still use the existing resampling path.

- Clock time: `4.883 s`
- CPU time: `4.827 s`
- CPU cycles: `15718535.732 kC`
- Retired instructions: `94768673.531 kI`
- Peak physical memory: `31334.618 kB`

## Delta

- Clock time reduced by about 14%.
- CPU time reduced by about 14%.
- CPU cycles reduced by about 14%.
- Retired instructions reduced by about 11%.
- Peak physical memory did not improve; the observed 0.2% increase is treated
  as noise-level rather than a regression or gain.

## Rejected Variant

A 32-bit packed BGRA store variant was tried and rejected. It preserved pixel
byte order in renderer tests, but the same benchmark measured worse than the
direct byte-write fast path (`5.083 s` clock, `5.008 s` CPU time,
`16118490.079 kC`, `96771476.719 kI`, `31403.430 kB` peak physical memory).
Do not repeat that variant without a lower-level SIMD or CoreVideo-specific
reason.

## Validation

- `swift test --filter PiPWatchSampleBufferRendererTests`
- `swift test --filter 'PiPWatchSampleBufferRendererTests|PiPWatchSampleBufferFactoryBenchmarkTests'`
- The two opt-in benchmark commands above.

## Privacy

The benchmark uses synthetic framebuffer colors and records only aggregate
CPU/time/memory metrics, fixed dimensions, fixed sample counts, and fixed test
names. It must not export screenshots, frame pixels, target hostnames,
endpoints, credentials, profile fingerprints, device identifiers, Compose text,
clipboard contents, raw network errors, or exact per-frame timing series.
