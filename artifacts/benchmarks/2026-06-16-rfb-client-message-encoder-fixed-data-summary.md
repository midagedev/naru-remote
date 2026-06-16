# RFB Client Message Encoder Fixed-Length Data Summary

Date: 2026-06-16 KST

## Goal

Reduce local input-lane overhead for the small RFB client messages emitted by
Direct Keys and trackpad pointer movement. This does not change network
cadence, but it removes avoidable CPU work from the key/pointer hot path that
must stay responsive while visual streaming is busy.

## Change

- Added an opt-in `RFBClientMessageEncoderBenchmarkTests` benchmark for repeated
  `KeyEvent` down/up plus `PointerEvent` message encoding.
- Changed `RFBClientMessageEncoder.keyEvent(keysym:isDown:)` and
  `encodePointerEvent(buttonMask:x:y:)` to fill fixed-size `Data` buffers
  directly instead of building temporary `[UInt8]` arrays and converting them
  to `Data`.

The benchmark consumes the encoded bytes through a checksum. An earlier
count-only draft benchmark was discarded because the optimizer could elide too
much of the fixed-size message work.

## Evidence

Command:

```sh
env NARU_RUN_SIM_BENCHMARKS=1 \
  NARU_SIM_BENCHMARK_ITERATIONS=10 \
  NARU_RFB_CLIENT_MESSAGE_BENCHMARK_SAMPLES=250000 \
  swift test -c release --filter RFBClientMessageEncoderBenchmarkTests
```

Logs:

- Baseline: `/tmp/naru-rfb-client-message-baseline-checksum-20260616-112414.log`
- Current: `/tmp/naru-rfb-client-message-current-checksum-20260616-114339.log`

| Metric | Baseline | Current | Result |
| --- | ---: | ---: | ---: |
| Clock monotonic time | 0.155 s | 0.060 s | 61% lower |
| CPU time | 0.155 s | 0.060 s | 61% lower |
| CPU cycles | 506,579.765 kC | 194,298.918 kC | 62% lower |
| CPU instructions retired | 2,863,174.154 kI | 1,138,037.784 kI | 60% lower |
| Peak physical memory | 6,145.664 kB | 6,078.618 kB | 1% lower |

Memory physical deltas inside the measured loop were too noisy to claim.

## Verification

- `swift test --filter RFBClientMessageEncoderTests`
- `swift test --filter DirectKeystrokeModeTests`
- `swift test --filter FakeRFBServerIntegrationTests`
- Final opt-in benchmark command above

## Decision

Proceed as a small performance PR. The improvement is local, narrow, and
measured well above benchmark noise while preserving exact RFB wire bytes.
