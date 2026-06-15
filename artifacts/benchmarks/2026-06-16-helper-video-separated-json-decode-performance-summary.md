# Helper Video Separated JSON Decode Performance - 2026-06-16

## Scope

Measure the helper-video network receive path after the wire length-header
optimization. The previous split access-unit decoder still required callers to
rebuild a `jsonHeader + jsonPayload` frame before decoding an access unit.

This is a synthetic wire-codec benchmark for the helper-video receive path. It
is not a physical iPhone Green claim, live FPS claim, thermal claim, or traffic
promotion result.

## Change

`HelperVideoWireCodec` now has separated JSON decode overloads that accept the
already received JSON header and JSON payload independently. The
`HelperVideoStreamNetworkClient` finite and streaming event paths pass those
pieces through directly instead of materializing a combined JSON frame.

The helper-video wire format, JSON header validation, binary payload
validation, stream event coalescing, timeout behavior, fallback labels, and app
runner semantics are unchanged.

## Commands

Baseline was measured on current `main` after the D88 length-header parser
change, with the network-style benchmark temporarily decoding through
`jsonHeader + jsonPayload`:

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_SAMPLES=1000 \
NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_PAYLOAD_BYTES=262144 \
swift test --filter HelperVideoWireCodecBenchmarkTests/testSplitAccessUnitNetworkStyleDecodeBenchmark
```

The same benchmark was rerun after switching the benchmark and network client
to separated JSON decode. Full wire-codec coverage and focused helper-video
transport/session coverage were also run:

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_SAMPLES=1000 \
NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_PAYLOAD_BYTES=262144 \
swift test --filter HelperVideoWireCodecBenchmarkTests
```

```bash
swift test --filter 'HelperVideoFakeTransportTests|HelperVideoStreamNetworkServiceTests|HelperVideoStreamSessionRunnerTests'
```

## Results

For 1,000 synthetic network-style access-unit decodes with a 256 KiB binary
payload per measured iteration:

| Metric | Baseline | Current | Change |
| --- | ---: | ---: | ---: |
| Clock time | `0.007320 s` | `0.006395 s` | about `13%` lower |
| CPU time | `0.007695 s` | `0.006733 s` | about `13%` lower |
| CPU cycles | `24250.981 kC` | `21514.050 kC` | about `11%` lower |
| Instructions | `105295.688 kI` | `97096.178 kI` | about `8%` lower |

Memory metrics were noisy across short runs and are not claimed.

## Product Decision

This is PR-worthy as a small sustained helper-video receive-path optimization:
the streaming event path is the path that should carry smooth helper-video
access units while VNC remains control/input/fallback.

Do not repeat the older full-frame assembly experiment or the D88 length-header
parser experiment for this slice. This follow-up removes the remaining
per-access-unit JSON frame rebuild in the network client.

## Safety

This artifact contains only fixed benchmark names, synthetic payload size, and
aggregate CPU/time metrics. It omits helper endpoints, credentials, profile
fingerprints, access-unit payloads, frame content, display dimensions, real
session byte counts, device identifiers, hostnames, Compose text, clipboard
contents, raw network errors, and exact per-frame timing series.
