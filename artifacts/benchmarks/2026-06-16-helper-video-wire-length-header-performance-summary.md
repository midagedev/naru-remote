# Helper Video Wire Length Header Performance - 2026-06-16

## Scope

Measure a narrow helper-video receive-path hot spot after the split access-unit
decode work: parsing the 4-byte JSON and binary length headers inside
`HelperVideoWireCodec`.

This is a synthetic wire-codec benchmark. It is not a physical iPhone Green
claim, live FPS claim, thermal claim, or traffic promotion result.

## Change

`HelperVideoWireCodec` now parses fixed 4-byte length headers from
`Data.withUnsafeBytes` and, when decoding a combined frame, reads the JSON and
binary headers directly from the frame buffer at known offsets.

The wire format, length limits, JSON decoding, binary payload validation,
network client behavior, and helper/app fallback semantics are unchanged.

## Commands

Baseline was measured on `origin/main` before the production change:

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_SAMPLES=1000 \
NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_PAYLOAD_BYTES=262144 \
swift test --filter HelperVideoWireCodecBenchmarkTests
```

The same command was rerun after the production change. Focused helper-video
transport/session coverage was also run:

```bash
swift test --filter 'HelperVideoFakeTransportTests|HelperVideoStreamNetworkServiceTests|HelperVideoStreamSessionRunnerTests'
```

## Results

For 1,000 synthetic access-unit decodes with a 256 KiB binary payload per
measured iteration:

| Benchmark | Metric | Baseline | Current | Change |
| --- | --- | ---: | ---: | ---: |
| Full-frame decode | Clock time | `0.014542 s` | `0.012648 s` | about `13%` lower |
| Full-frame decode | CPU time | `0.014548 s` | `0.012717 s` | about `13%` lower |
| Full-frame decode | CPU cycles | `45542.147 kC` | `40505.876 kC` | about `11%` lower |
| Full-frame decode | Instructions | `164201.409 kI` | `153974.057 kI` | about `6%` lower |
| Split decode | Clock time | `0.007423 s` | `0.006745 s` | about `9%` lower |
| Split decode | CPU time | `0.007743 s` | `0.007017 s` | about `9%` lower |
| Split decode | CPU cycles | `24333.822 kC` | `22067.545 kC` | about `9%` lower |
| Split decode | Instructions | `106709.829 kI` | `98109.161 kI` | about `8%` lower |

Memory metrics were noisy across short runs and are not claimed.

## Product Decision

This is PR-worthy as a small helper-video receive-path optimization because the
current primary visual strategy depends on sustained helper-video access-unit
delivery, and the split decode path is the production-like receive path used by
`HelperVideoStreamNetworkClient`.

Do not repeat the older full-frame assembly experiment or AVCC length-prefix
append experiment for this change. This slice removes only per-header `Data` /
`[UInt8]` materialization from the wire-codec length parser.

## Safety

This artifact contains only fixed benchmark names, synthetic payload size, and
aggregate CPU/time metrics. It omits helper endpoints, credentials, profile
fingerprints, access-unit payloads, frame content, display dimensions, real
session byte counts, device identifiers, hostnames, Compose text, clipboard
contents, raw network errors, and exact per-frame timing series.
