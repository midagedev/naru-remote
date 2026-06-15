# Helper Video Split Decode Performance - 2026-06-15

## Scope

Reduce helper-video client receive-path CPU and copy pressure by avoiding
full-frame `Data` concatenation for H.264 access-unit messages. This is a
helper-video receive/decode micro-performance improvement only; it is not a
physical iPhone Green claim.

## Change

`HelperVideoWireCodec` now decodes an access-unit envelope from the already
received JSON frame, binary length header, and binary payload. The finite
`startStream` receive path and the sustained `streamEvents` receive path use
that split decode instead of building `jsonFrame + binaryHeader + binaryPayload`
and then decoding the combined frame.

The protocol framing is unchanged. Parameter sets, keyframes, deltas,
end-of-stream units, start responses, stall messages, and mailbox
backpressure behavior keep the same semantics.

## Commands

```bash
swift test --filter 'HelperVideoFakeTransportTests|HelperVideoStreamNetworkServiceTests|HelperVideoStreamSessionRunnerTests'
```

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_PAYLOAD_BYTES=262144 \
NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_SAMPLES=1000 \
swift test --filter HelperVideoWireCodecBenchmarkTests
```

## Results

The benchmark decodes 1,000 access units per measured iteration with a 256 KiB
binary payload.

| Path | Clock time | CPU cycles | CPU instructions |
| --- | ---: | ---: | ---: |
| Full-frame decode | 0.018150 s | 49209.438 kC | 164592.894 kI |
| Split-frame decode | 0.011103 s | 27095.705 kC | 106735.765 kI |
| Reduction | 38.8% | 44.9% | 35.2% |

Functional regressions passed: 28 selected helper-video transport, network, and
session-runner tests.

## Product Decision

Use split-frame decode for helper-video access units in the client receive path.
This is PR-worthy because it removes avoidable per-frame payload copying from
the helper-video primary visual candidate and has a clear measured CPU/time
improvement. It does not change the physical-device promotion gate: smoothness
still requires the helper-video physical iPhone gate and manual sustained
thermal/hand-feel evidence.

## Safety

This artifact records only aggregate benchmark timings and fixed test names. It
does not include helper endpoints, credentials, profile fingerprints, access
unit payloads, frame content, display dimensions, byte counts from a real
session, device identifiers, hostnames, Compose text, clipboard contents, raw
network errors, or exact per-frame timing series.
