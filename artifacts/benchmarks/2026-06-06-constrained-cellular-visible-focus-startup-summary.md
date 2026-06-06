# Constrained-Cellular Visible-Focus Startup Summary

This increment adds a benchmark-only first-frame request mode for poor-network
startup traffic work. It keeps production startup unchanged.

## Change

- Added `--stream-shape-first-frame-request visible-focus`.
- Added `--stream-shape-gate-preset
  sustained-v2-constrained-cellular-visible-focus-startup`.
- Bumped `VNCLiveBenchmark` reports to schema v60.
- The new mode requests a smaller fixed central focus area for the first
  non-incremental frame only. Sustained incremental requests continue to use the
  existing `viewport-phone-portrait` request region and fallback policy.
- Reports emit only fixed labels, framebuffer-relative first-frame request area
  permille, existing aggregate timing summaries, and fixed gate issue labels.

## Verification

```bash
swift test --filter BenchmarkStreamShapeFirstFrameRequestModeTests
swift test --filter BenchmarkStreamShapeRequestRegionTests
swift test --filter BenchmarkStreamShapeGatePresetTests
swift test --filter BenchmarkStreamShapeSummaryTests
swift test --filter BenchmarkStreamShapeFirstFrameTimingTextTests
swift run VNCLiveBenchmark --help | rg -n "schema v60|visible-focus|visible-focus-startup"
swift build --product VNCLiveStimulusWindow
NARU_LIVE_MAC_HOST=... \
NARU_LIVE_STIMULUS_COMMAND='.build/debug/VNCLiveStimulusWindow --duration "$NARU_LIVE_STIMULUS_DURATION_SECONDS"' \
swift run VNCLiveBenchmark \
  --stream-shape-gate-preset sustained-v2-constrained-cellular-visible-focus-startup \
  --json \
  --ask-password
```

The live command was run against the local private VNC target through the
benchmark-local `constrained-cellular` conditioning proxy. The password was
entered through the prompt and is not included in the command or artifact.

## Live Result

- `schemaVersion`: 60
- `networkCondition`: `constrained-cellular`
- `streamShapeGatePreset`:
  `sustained-v2-constrained-cellular-visible-focus-startup`
- `streamShapeFirstFrameRequestMode`: `visible-focus`
- `streamShapePracticalTarget`: `iphone-poor-network-traffic-v1`
- `firstFrameRequestAreaPermille`: 192 for every profile probe
- `requestRegionAreaPermille`: 364 for every profile probe
- Full-color candidates still failed first-frame startup with
  `stream-first-frame-read-timeout`.
- RGB565 candidates reached stream samples and downgraded the startup blocker
  from fail to warning:

| profile | usable | first frame | first-frame receive total/network/first-byte/payload/client | first-frame first-byte/payload split | content FPS | avg update | max p95 update | sustained dominant |
| --- | ---: | ---: | --- | --- | ---: | ---: | ---: | --- |
| `local-low-latency-rgb565` | 1/1 | about 16.3 s | 16299 / 15405 / 946 / 14459 / 894 ms | 61 / 939 permille | 2.19 | 457 ms | 623 ms | first-byte wait |
| `zrle-compression-0-rgb565` | 1/1 | about 16.4 s | 16425 / 15536 / 955 / 14581 / 889 ms | 61 / 939 permille | 2.04 | 491 ms | 625 ms | first-byte wait |

Report-level result:

- `streamShapeOptimizationDecision.verdict`: `fail`
- `requestResponseUsableRunCount`: 2
- `requestResponseFailureLabelCounts`: `stream-first-frame-read-timeout` x2
- `streamShapeRequestCadenceHealth.sampleStatus`: `high-content-hit`
- `streamShapeRequestCadenceHealth.latencyStatus`: `p95-warning`
- `streamShapeRequestCadenceHealth.recommendedNextProbe`:
  `inspectUpdateWaitTiming`

## Interpretation

`visible-focus` proves that the startup track is traffic/payload-pressure
sensitive: dropping the first-frame area from the earlier visible-core 300
permille to 192 permille moved successful RGB565 startup from just above the
20 s fail band to roughly 16.3-16.4 s.

It is not a production-default candidate yet. The overall gate still fails
because full-color candidates time out and the sustained stream remains far
below the practical target. Sustained content samples have high hit-rate but are
first-byte-wait dominated, with p95 update latency still around 623-625 ms.

Next useful work should keep these as two separate tracks:

- Startup traffic: design a staged first-useful-paint path that can show a
  small useful region quickly, then recover the full visible region without
  making pan/zoom feel broken.
- Sustained traffic/cadence: inspect request/update wait timing and server
  update production under constrained cellular; another first-frame area tweak
  will not fix the steady 2 fps class stream.
