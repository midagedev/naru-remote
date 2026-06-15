# Helper Video Annex-B Parser Performance - 2026-06-15

## Scope

Reduce app-side helper-video sample-buffer preparation cost by avoiding the
full-payload `Data` to `[UInt8]` copy in the Annex-B parser. This is an
H.264 sample-buffer factory micro-performance improvement only; it is not a
physical iPhone Green claim.

## Change

`HelperVideoH264AnnexBParser` now scans the received `Data` through
`withUnsafeBytes` and records start-code boundaries from the original payload
buffer. The parser still creates owned `Data` values for the NAL payloads it
returns, so the factory's parameter-set caching, AVCC payload construction, and
CoreMedia sample-buffer creation semantics remain unchanged.

## Commands

```bash
swift test --filter HelperVideoH264SampleBufferRendererTests
```

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_HELPER_VIDEO_SAMPLE_BUFFER_BENCHMARK_PAYLOAD_BYTES=262144 \
NARU_HELPER_VIDEO_SAMPLE_BUFFER_BENCHMARK_SAMPLES=500 \
swift test --filter HelperVideoSampleBufferFactoryBenchmarkTests
```

## Results

The benchmark prepares 500 delta access units per measured iteration with a
256 KiB binary payload after a cached parameter-set access unit.

| Path | Clock time | CPU time | CPU cycles | CPU instructions |
| --- | ---: | ---: | ---: | ---: |
| Array-copy parser | 1.630 s | 1.601 s | 5043918.311 kC | 24324873.735 kI |
| Unsafe-bytes parser | 0.609 s | 0.602 s | 1915992.024 kC | 7072515.380 kI |
| Reduction | 62.6% | 62.4% | 62.0% | 70.9% |

Functional regressions passed: 11 selected helper-video H.264 parser,
sample-buffer factory, and renderer tests.

## Rejected Follow-Up

I also tried removing the intermediate media-unit `filter` and reserving AVCC
payload capacity in the same function. That did not improve the stable CPU
metrics and produced a noisier clock run, so this PR keeps only the
full-payload parser-copy removal.

## Product Decision

Use the unsafe-bytes parser scan for helper-video app-side H.264 sample-buffer
preparation. This is PR-worthy because it removes an avoidable per-access-unit
full payload copy from the app visual path and has clear measured reductions in
CPU time, CPU cycles, and retired instructions.

## Safety

This artifact records only aggregate benchmark timings, fixed synthetic payload
sizes, and fixed test names. It does not include helper endpoints, credentials,
profile fingerprints, access-unit payloads, frame content, display dimensions,
byte counts from a real session, device identifiers, hostnames, Compose text,
clipboard contents, raw network errors, or exact per-frame timing series.
