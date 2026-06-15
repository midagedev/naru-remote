# Staged Dirty-Rect Upload Performance Summary

Date: 2026-06-15 KST

## Scope

This artifact records the opt-in simulator benchmark for Metal framebuffer
staged-upload preparation when a same-size VNC frame carries a small dirty
rectangle. It is a renderer-pressure and memory-traffic reduction for
text-heavy live sessions, not a physical iPhone Green claim, a live FPS claim,
or a network-traffic reduction claim.

## Command

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_SIM_BENCHMARK_WIDTH=1920 \
NARU_SIM_BENCHMARK_HEIGHT=1080 \
NARU_STAGED_UPLOAD_BENCHMARK_SAMPLES=500 \
swift test --filter SyntheticFramePipelineBenchmarkTests/testLegacyFullStagedSmallDirtyRectPreparationBenchmark

NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_SIM_BENCHMARK_WIDTH=1920 \
NARU_SIM_BENCHMARK_HEIGHT=1080 \
NARU_STAGED_UPLOAD_BENCHMARK_SAMPLES=500 \
swift test --filter SyntheticFramePipelineBenchmarkTests/testStagedSmallDirtyRectPreparationBenchmark
```

The benchmark prepares 500 staged uploads per measured iteration. Each sample
uses a synthetic 1920x1080 framebuffer and a 320x180 dirty rectangle after a
same-size baseline texture has already been uploaded.

The legacy and optimized benchmark cases are run in separate test processes so
the peak physical memory metric is not dominated by XCTest process high-water
from the previously executed case.

## Baseline

The legacy staged path prepared a full framebuffer `MTLBuffer` even when the
upload plan later used only a small dirty rectangle. For 1920x1080 RGBA frames,
that means preparing about 8.29 MiB of buffer data per sample.

- Clock time: `0.358 s`
- CPU time: `0.358 s`
- CPU cycles: `1164671.258 kC`
- Retired instructions: `2638902.616 kI`
- Peak physical memory: `40755.418 kB`

## Result

The optimized staged path evaluates the upload plan during preparation. For
same-size partial uploads, it copies only the dirty rectangle bytes into compact
region payloads and replaces those regions in the existing texture. First-frame,
dimension-changing, invalid, scattered, or high-area updates still fall back to
one full buffer.

The 320x180 dirty rectangle prepares 230,400 bytes instead of a full
8,294,400-byte framebuffer buffer.

- Clock time: `0.017 s`
- CPU time: `0.017 s`
- CPU cycles: `56101.377 kC`
- Retired instructions: `267786.993 kI`
- Peak physical memory: `32940.186 kB`

## Delta

- Clock time reduced by about 95%.
- CPU time reduced by about 95%.
- CPU cycles reduced by about 95%.
- Retired instructions reduced by about 90%.
- Peak physical memory reduced by about 19%.

## Validation

- `swift test --filter 'MetalFramebufferRendererTests/testStagedSmallDirtyRectPreparationUsesPartialBufferWhenTextureMatches|MetalFramebufferRendererTests/testPreparedStagedPartialUploadPreservesUntouchedPixelsFromPreviousFrame|MetalFramebufferRendererTests/testStagedPreparationUsesFullBufferWhenTextureIsMissing'`
- `NARU_RUN_SIM_BENCHMARKS=1 NARU_SIM_BENCHMARK_ITERATIONS=5 NARU_SIM_BENCHMARK_WIDTH=1920 NARU_SIM_BENCHMARK_HEIGHT=1080 NARU_STAGED_UPLOAD_BENCHMARK_SAMPLES=500 swift test --filter SyntheticFramePipelineBenchmarkTests/testLegacyFullStagedSmallDirtyRectPreparationBenchmark`
- `NARU_RUN_SIM_BENCHMARKS=1 NARU_SIM_BENCHMARK_ITERATIONS=5 NARU_SIM_BENCHMARK_WIDTH=1920 NARU_SIM_BENCHMARK_HEIGHT=1080 NARU_STAGED_UPLOAD_BENCHMARK_SAMPLES=500 swift test --filter SyntheticFramePipelineBenchmarkTests/testStagedSmallDirtyRectPreparationBenchmark`

## Product Decision

Adopt the partial staged-payload path. This removes full-frame buffer
preparation from the steady-state small-damage renderer path while preserving
full uploads for first frames, texture recreation, and non-localized damage.
The improvement is PR-worthy because same-size small dirty rectangles are the
common case for text cursor, terminal, editor, and AI CLI screen changes, where
renderer upload work can otherwise compete with local input and viewport
interaction.

This does not change VNC request cadence, helper-video cadence, transport
payload size, or physical device thermal policy. Physical iPhone/iPad
verification remains required before making broader smoothness claims.

## Privacy

The benchmark uses synthetic framebuffer colors and records only aggregate
CPU/time/memory metrics, fixed dimensions, fixed dirty-rectangle size, fixed
sample counts, and fixed test names. It must not export screenshots, frame
pixels, target hostnames, endpoints, credentials, profile fingerprints, device
identifiers, Compose text, clipboard contents, raw network errors, raw payload
bytes, or exact per-frame timing series.
