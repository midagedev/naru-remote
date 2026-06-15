# Profile Preview Thumbnail Performance Summary

Date: 2026-06-15 KST

## Scope

This artifact records the opt-in benchmark for the active-session preview cache
path that creates connection-grid last-frame thumbnails from live VNC
framebuffers. It is a thermal/power/allocation reduction for live sessions and
grid previews, not a claim that VNC receive cadence or physical iPhone FPS is
Green.

## Command

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_PROFILE_PREVIEW_BENCHMARK_SAMPLES=200 \
swift test --filter ProfilePreviewThumbnailBenchmarkTests/testProfilePreviewThumbnailGenerationBenchmark
```

The benchmark generates 200 synthetic 1920x1080 framebuffer thumbnails per
measured iteration using the default 320x200 thumbnail bound.

## Baseline

The baseline generated an intermediate `[RFBColor]` thumbnail array and then
converted it to `Data` through `flatMap`.

- Clock time: `5.775 s`
- CPU time: `5.663 s`
- CPU cycles: `17936516.674 kC`
- Retired instructions: `100678438.426 kI`
- Peak physical memory: `16602.125 kB`

## Result

The optimized path writes RGBA bytes directly into the final `Data` buffer,
uses the framebuffer's pixel storage directly for downsampling, and decodes
stored thumbnails through `Data.withUnsafeBytes` without copying to `[UInt8]`.

- Clock time: `1.747 s`
- CPU time: `1.727 s`
- CPU cycles: `5496996.210 kC`
- Retired instructions: `30890787.925 kI`
- Peak physical memory: `15638.682 kB`

## Delta

- Clock time reduced by about 70%.
- CPU time reduced by about 70%.
- CPU cycles reduced by about 69%.
- Retired instructions reduced by about 69%.
- Peak physical memory reduced by about 6%.

## Validation

- `swift test --filter ProfilePreviewStoreTests`
- `NARU_RUN_SIM_BENCHMARKS=1 NARU_SIM_BENCHMARK_ITERATIONS=5 NARU_PROFILE_PREVIEW_BENCHMARK_SAMPLES=200 swift test --filter ProfilePreviewThumbnailBenchmarkTests/testProfilePreviewThumbnailGenerationBenchmark`

## Privacy

The benchmark uses synthetic framebuffer colors and records only aggregate
CPU/time/memory metrics, fixed dimensions, fixed sample counts, and fixed test
names. It must not export screenshots, frame pixels, target hostnames,
endpoints, credentials, profile fingerprints, device identifiers, Compose text,
clipboard contents, raw network errors, or exact per-frame timing series.
