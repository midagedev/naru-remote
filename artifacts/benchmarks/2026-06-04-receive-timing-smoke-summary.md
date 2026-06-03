# 2026-06-04 Receive Timing Smoke Summary

Purpose: verify schema v19 receive-path timing can separate live VNC update
latency into aggregate total receive time, socket read time, and derived client
processing time before changing more production stream defaults.

Safety boundary: this artifact stores only aggregate benchmark output. It omits
host, password, server name, framebuffer dimensions, coordinates, pixels, byte
counts, cursor pixels, raw error descriptions, and raw per-frame samples.

## Research Direction

VNC optimization remains a latency, bandwidth, and CPU tradeoff rather than a
single best encoding choice. RFC 6143 defines incremental framebuffer update
requests and notes that fast clients may regulate request rate to avoid
excessive network traffic. TigerVNC and TightVNC expose compression/quality
controls because lossless/lossy compression levels move cost between network
traffic, server CPU, and image quality. TurboVNC's H.264 study reinforces that
frame-oriented codecs and high compression can increase CPU cost or require
coalescing to be usable.

This PR therefore adds measurement first: if the iPhone gets hot or drops FPS,
the next benchmark can tell whether the client is spending material time in
decode/processing, or whether it is mostly waiting on server/network update
delivery.

## Live Localhost VNC Smoke

Command shape:

```sh
NARU_LIVE_MAC_HOST=127.0.0.1 swift run VNCLiveBenchmark \
  --attempts 1 \
  --full-refresh-samples 0 \
  --continuous-update-samples 1 \
  --first-frame-profiles none \
  --stream-shape-samples 6 \
  --stream-shape-duration-seconds 6 \
  --stream-shape-profiles local-low-latency \
  --stream-shape-transport request-response \
  --ask-password
```

Result:

| Metric | Value |
| --- | ---: |
| Received updates | 6 / 6 |
| First frame | 2766 ms |
| All-update FPS | 5.87 |
| Content-frame FPS | 3.91 |
| Update avg / p50 / p95 / min / max | 139 / 25 / 487 / 10 / 487 ms |
| Receive total avg / p50 / p95 / min / max | 138 / 24 / 486 / 9 / 486 ms |
| Network read avg / p50 / p95 / min / max | 131 / 16 / 486 / 2 / 486 ms |
| Client processing avg / p50 / p95 / min / max | 7 / 7 / 15 / 0 / 15 ms |
| Renderer uploads partial / full | 4 / 0 |
| Slow samples >=250 ms | 2 / 6 |
| ContinuousUpdates probe | receive connection failed |

## Takeaway

The smoke run proves the new text report emits the schema v19 timing split and
the safety line explicitly documents that these are aggregate millisecond
summaries only.

For this target/run, client processing was low relative to update arrival time:
client processing p95 was 15 ms while network read p95 was 486 ms. That points
the next practical-usability work toward longer physical-device runs, profile
comparison, server update pacing, and transport behavior rather than assuming
the current bottleneck is local decode CPU.

## Synthetic Renderer Recheck

Command:

```sh
NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests
```

Result:

- Full framebuffer allocation and upload averaged about 2 ms monotonic time.
- Steady-state full upload averaged about 1 ms monotonic time.
- Small dirty-rectangle upload and same-frame upload gating stayed near zero at
  this benchmark scale.
- All 4 synthetic benchmark tests passed.

This keeps the prior conclusion intact: avoiding full uploads remains useful,
but this short smoke does not point to renderer upload as the dominant heat/FPS
source.

## Verification

- `swift test --filter RFBRawFramebufferDecoderTests --filter RFBFramePumpTests --filter BenchmarkStreamShapeSummaryTests`
- `swift test --filter FakeRFBServerIntegrationTests/testContinuousReceiveTimeoutReturnsIdleFrameAndKeepsConnectionUsable`
- `swift test`
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
- `git diff --check`
- Live smoke command above
