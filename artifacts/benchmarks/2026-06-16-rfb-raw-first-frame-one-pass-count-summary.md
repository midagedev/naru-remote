# RFB Raw First-Frame One-Pass Count - 2026-06-16

## Scope

Reduce local CPU work in the VNC Raw fallback first-paint path. This benchmark
decodes one synthetic 1920x1080 32-bit Raw full-frame update with no previous
framebuffer. It does not include server wait time, network transfer, Metal
upload, SwiftUI/UIKit layout, physical-device thermal behavior, or live FPS.

## Change

The first full Raw frame previously decoded the pixel payload into
`[RFBColor]`, then made a second pass over the decoded pixels to count
non-black pixels for the initial `changedPixelCount`.

`RFBFramebufferDecoder.decodeFullRawFrame` now uses a one-pass pixel decoder
only when the framebuffer needs initial replacement. That decoder creates the
same pixel array and counts non-black pixels in the same loop. Incremental
full-frame updates still use the existing compare-against-previous path, and
small/partial Raw rectangles are unchanged.

## Commands

Baseline was measured on `main` before the one-pass count change:

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_SIM_BENCHMARK_WIDTH=1920 \
NARU_SIM_BENCHMARK_HEIGHT=1080 \
swift test --filter RFBRawDecodeBenchmarkTests/testFullFrameRawFirstPaintDecodeBenchmark
```

The same benchmark was rerun after the decoder change, then repeated to check
stability. Focused decoder regression coverage also passed:

```bash
swift test --filter RFBRawFramebufferDecoderTests
swift test --filter RFBFramebufferDecoderTests
```

## Results

| Metric | Baseline | Current repeat | Change |
| --- | ---: | ---: | ---: |
| Clock time | `0.488 s` | `0.314 s` | about `36%` lower |
| CPU time | `0.485 s` | `0.309 s` | about `36%` lower |
| CPU cycles | `1544232.557 kC` | `977068.223 kC` | about `37%` lower |
| Instructions | `8708818.303 kI` | `5525754.930 kI` | about `37%` lower |
| Peak physical memory | `24840.000 kB` | `24790.784 kB` | flat/no claim |

The first after-run was consistent with the repeat: `0.309 s` clock,
`0.307 s` CPU time, `974400.180 kC`, and `5524890.339 kI`.

## Product Decision

Use the one-pass initial full Raw frame decode/count path. This is PR-worthy
because it removes a full 1080p decoded-pixel pass from the VNC visual
fallback startup path and shows a stable simulator CPU/time reduction. It does
not change the larger product finding that live VNC smoothness can still be
dominated by server cadence, network waits, and rendering/input separation.

## Rejected Experiments

- `Array(unsafeUninitializedCapacity:)` for the common direct RGB decode loop:
  rejected for this slice. It reduced CPU counters only about 3%, made clock
  timing noisy, and increased peak memory in the benchmark.
- Reserving extra capacity before `HelperVideoWireCodec.frameAccessUnit`
  appends its binary length/payload: rejected because both the raw unsafe
  length append and reserve-only variants measured slower than the existing
  path in the access-unit encoding benchmark.

Do not repeat those experiments unless a later profile identifies these exact
operations as the dominant cost again.

## Safety

This artifact records only aggregate benchmark timings, fixed synthetic
dimensions, and fixed test names. It does not include hostnames, endpoints,
credentials, frame pixels, screenshots, raw payload bytes, profile
fingerprints, device identifiers, Compose text, clipboard contents, raw
network errors, pointer coordinates, or exact per-frame timing series.
