# ZRLE Phase Timing Benchmark Summary

Date: 2026-06-05 KST

## Goal

Establish a larger practical baseline for sustained iPhone-class VNC work by
separating safe ZRLE decode phase timing from the existing receive-path timing.
The target question for this PR is whether remaining update tails are dominated
by local ZRLE inflate, local tile/apply work, renderer upload pressure, or
server/network wait.

## Implementation Scope

- Add safe aggregate `RFBFramebufferDecodeMetrics` to framebuffer update
  results.
- Measure ZRLE inflate time and ZRLE tile/apply time inside the decoder.
- Thread decode metrics through `RFBFramePumpFrame`.
- Add optional ZRLE phase timing samples and aggregate summaries to
  `VNCLiveBenchmark` schema v31.
- Keep payload privacy unchanged: no framebuffer dimensions, coordinates,
  pixels, cursor pixels, byte counts, host identity, credentials, or raw
  per-frame sample arrays are exported.

## Focused Verification

```bash
swift test --filter RFBRawFramebufferDecoderTests --filter RFBFramePumpTests
swift test --filter BenchmarkStreamShapeSummaryTests
```

Result:

- `RFBRawFramebufferDecoderTests` + `RFBFramePumpTests`: 31 tests passed.
- `BenchmarkStreamShapeSummaryTests`: 21 tests passed.

## Live Localhost Screen Sharing Benchmark

Safe command shape:

```bash
NARU_LIVE_MAC_HOST=127.0.0.1 \
NARU_LIVE_MAC_PASSWORD=<redacted> \
swift run VNCLiveBenchmark \
  --attempts 1 \
  --full-refresh-samples 1 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 20 \
  --stream-shape-frame-interval 0.0167 \
  --stream-shape-idle-frame-interval 0.05 \
  --stream-shape-empty-backoff app \
  --stream-shape-power-mode normal \
  --stream-shape-client-pressure app \
  --first-frame-profiles stream-shape-profiles \
  --stream-shape-profiles local-low-latency \
  --stream-shape-transport request-response \
  --continuous-update-samples 1 \
  --timeout 3 \
  --idle-timeout 1 \
  --json
```

Result:

- Schema: v31.
- Profile: `local-low-latency`.
- Transport: `request-response`.
- Practical verdict: `warning`.
- Practical issue: `content-fps-warning`.
- Stream-shape status: `mixed-updates`.
- Received/content/empty updates: 142 / 123 / 19.
- Delivered FPS: 7.10.
- Content FPS: 6.15.
- First stream-shape frame: 3211 ms.
- Update latency p50/p95/max: 28 / 488 / 552 ms.
- Receive total p50/p95/max: 28 / 488 / 551 ms.
- Network read p50/p95/max: 21 / 487 / 549 ms.
- Client processing p50/p95/max: 3 / 12 / 28 ms.
- Actual encoding mix: 142 ZRLE rectangles.
- ZRLE inflate avg/p50/p95/max: 0 / 0 / 0 / 23 ms.
- ZRLE tile/apply avg/p50/p95/max: 3 / 3 / 11 / 18 ms.
- Renderer full-upload pressure: 0 permille.
- Adaptive client-pressure pacing: 0 permille.
- Slow updates: 20.
- Slow content updates: 3.
- Very slow updates: 0.
- First slow update ordinal: 3.
- First slow content update ordinal: 96.

## Interpretation

This run did not reproduce the earlier 1000 ms-class first-content tail. The
new phase timing shows local ZRLE work is not the dominant p95 tail in this
baseline: ZRLE tile/apply p95 is 11 ms, inflate p95 is 0 ms, and client
processing p95 is 12 ms. The p95 update tail tracks receive/network wait
instead. Renderer full uploads are also absent.

The current baseline therefore moves from "fail due local decode/apply tail" to
"warning due content update rate." The next larger unit should compare
request/response versus ContinuousUpdates/Fence and profile choices over longer
runs, then repeat on the physical iPhone thermal path.

## Privacy Boundary

This artifact records only fixed labels, aggregate counts, aggregate FPS,
aggregate latency summaries, and ordinal tail positions. It does not include
host identity, credentials, framebuffer dimensions, coordinates, pixels, cursor
pixels, byte counts, raw samples, raw payload, raw error text, or Compose input.
