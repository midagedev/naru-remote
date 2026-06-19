# 2026-06-17 Helper Video Wire Codec Split Decode Benchmark

## Context

Helper-video access units are encoded H.264 payloads carried beside a small JSON
envelope. The client receive path now decodes access units from the already
split JSON frame, binary length header, and binary payload instead of rebuilding
one combined `Data` frame before decode. This targets helper-video client CPU
and wall-time overhead in the visual-primary path.

This is a local SwiftPM benchmark, not a physical-device FPS, thermal, or
traffic-promotion claim.

## Command

```sh
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_SAMPLES=200 \
NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_PAYLOAD_BYTES=262144 \
swift test --filter HelperVideoWireCodecBenchmarkTests
```

Result: passed.

## Measurements

Payload: `262144` bytes per access unit.
Samples: `200` per iteration.
Iterations: `5`.

| Metric | Full-frame decode | Split-frame decode | Delta |
| --- | ---: | ---: | ---: |
| Clock monotonic time | `0.002644 s` | `0.001384 s` | `47.7%` lower |
| CPU time | `0.002945 s` | `0.001625 s` | `44.8%` lower |
| CPU cycles | `9098.401 kC` | `5293.410 kC` | `41.8%` lower |
| CPU instructions retired | `34718.421 kI` | `23518.748 kI` | `32.3%` lower |

Memory peak was not used for the improvement claim because the two XCTest
measurements run in the same process and the split measurement inherited a
higher process peak that does not isolate per-decode allocation.

## Product-Quality Reading

This is a measured helper-video receive-path CPU/wall-time improvement. It
supports the product direction that helper video should become the visual
primary path while VNC remains control/input/fallback when VNC cannot meet the
10fps gate.

This does not make the product Green. Physical iPhone promotion remains
unclaimed, and the user-visible helper-video FPS/thermal result still needs the
physical-device gate when physical testing is re-enabled.

## Privacy Rule

This artifact may expose fixed benchmark names, aggregate timing/CPU metrics,
payload-size labels, sample counts, and iteration counts. It must not expose
hostnames, endpoints, credentials, signing identifiers, physical device
identifiers, raw helper payload bytes, H.264 frame contents, screenshots,
pixels, coordinates, composed text, clipboard contents, or exact per-frame
timing series.
