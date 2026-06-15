# RFB Raw Read-Data Fast Path - 2026-06-15

## Scope

Reduce VNC Raw full-frame first-paint decode memory pressure by letting large
pixel payloads stay as `Data` until pixel decoding. This is a VNC fallback/raw
decode micro-performance improvement only; it is not a physical iPhone Green
claim.

## Change

`RFBByteReader` now has a `readData(_:)` fast path. `ConnectionByteReader`
returns the `Data` produced by `readExactly` directly, and
`PrefixedByteReader` preserves that fast path once its small prefix is drained.
The Raw full-frame decoder now reads the pixel payload as `Data` and decodes
colors through `Data.withUnsafeBytes`, avoiding a whole-frame `Data` to
`[UInt8]` copy before color conversion.

Small rectangle and compressed paths keep using `readBytes(_:)`; their behavior
is unchanged.

## Commands

```bash
swift test --filter 'RFBByteReaderTests|RFBRawFramebufferDecoderTests|RFBProtocolDecoderTests|RFBFramePumpTests'
```

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=5 \
NARU_SIM_BENCHMARK_WIDTH=1920 \
NARU_SIM_BENCHMARK_HEIGHT=1080 \
swift test --filter RFBRawDecodeBenchmarkTests
```

## Results

The benchmark decodes one synthetic 1920x1080 32-bit Raw full-frame update per
measured iteration.

| Path | Clock time | CPU time | CPU cycles | CPU instructions | Peak physical memory |
| --- | ---: | ---: | ---: | ---: | ---: |
| `readBytes` full-frame payload | 0.514 s | 0.508 s | 1610893.994 kC | 9231329.883 kI | 41440.230 kB |
| `readData` full-frame payload | 0.520 s | 0.494 s | 1559683.515 kC | 8711090.317 kI | 24899.046 kB |
| Improvement | flat/noisy | 2.8% lower | 3.2% lower | 5.6% lower | 39.9% lower |

Functional regressions passed: 56 selected RFB byte-reader, raw framebuffer,
protocol decoder, and frame-pump tests.

## Product Decision

Use `readData(_:)` for large Raw full-frame pixel payloads. This is PR-worthy
because it removes an avoidable whole-frame copy from the VNC visual fallback
path and cuts peak benchmark memory by about 40%, with smaller CPU-time,
cycle, and retired-instruction reductions. The wall-clock metric was effectively
flat/noisy in this microbenchmark. It does not change the larger live VNC
finding that Apple Screen Sharing cadence and first-byte wait dominate many
poor-network runs.

## Safety

This artifact records only aggregate benchmark timings, fixed synthetic
dimensions, and fixed test names. It does not include hostnames, endpoints,
credentials, frame pixels, screenshots, raw payload bytes, profile
fingerprints, device identifiers, Compose text, clipboard contents, raw network
errors, or exact per-frame timing series.
