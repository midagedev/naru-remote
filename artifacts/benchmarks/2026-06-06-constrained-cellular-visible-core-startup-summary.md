# Constrained-Cellular Visible-Core Startup Summary - 2026-06-06

This increment tests a narrower benchmark-only first-frame startup request for
poor-network iPhone use. It keeps production startup unchanged and keeps
sustained stream requests on the existing viewport policy.

## What Changed

- Added `--stream-shape-first-frame-request visible-core`.
- Added `--stream-shape-gate-preset
  sustained-v2-constrained-cellular-visible-core-startup`.
- Bumped `VNCLiveBenchmark` reports to schema v58.
- Added `firstFrameRequestAreaPermille` to profile probes, aggregates, and
  gates.
- Poor-network traffic gates now judge the larger of sustained request area and
  first-frame request area.

The visible-core preset keeps the schema v57 constrained-cellular shape but
sets:

- `streamShapeFirstFrameRequestMode`: `visible-core`
- `streamShapeRequestRegions`: `viewport-phone-portrait`
- `networkCondition`: `constrained-cellular`
- `streamShapePracticalTarget`: `iphone-poor-network-traffic-v1`

## Verification Commands

```sh
swift test --filter BenchmarkStreamShapeFirstFrameRequestModeTests
swift test --filter BenchmarkStreamShapeRequestRegionTests
swift test --filter BenchmarkStreamShapeGatePresetTests
swift test --filter BenchmarkStreamShapeSummaryTests
swift run VNCLiveBenchmark --help | rg -n "schema v58|visible-core|first-frame request-area|visible-core-startup"
swift test
swift run VNCLiveBenchmark --stream-shape-gate-preset sustained-v2-constrained-cellular-visible-core-startup --json
```

## Live Result

Safe aggregate report fields:

- `schemaVersion`: 58
- `networkCondition`: `constrained-cellular`
- `streamShapeGatePreset`: `sustained-v2-constrained-cellular-visible-core-startup`
- `streamShapePracticalTarget`: `iphone-poor-network-traffic-v1`
- `streamShapeFirstFrameRequestMode`: `visible-core`
- `streamShapeRequestRegions`: `viewport-phone-portrait`
- `requestRegionAreaPermille`: 364 for every profile probe
- `firstFrameRequestAreaPermille`: 300 for every profile probe

Per-profile result:

| Profile | Startup | Samples | Steady Avg / P95 | Content FPS | Gate Verdict | Primary Issue |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| `local-low-latency` | timeout | 0/4 | n/a | n/a | fail | `probe-failed` |
| `local-low-latency-rgb565` | 20.643 s | 4/4 | 493 / 611 ms | 2.03 | fail | `first-frame-failed` |
| `zrle-compression-0` | timeout | 0/4 | n/a | n/a | fail | `probe-failed` |
| `zrle-compression-0-rgb565` | 20.717 s | 4/4 | 434 / 609 ms | 1.68 | fail | `first-frame-failed` |

Request/response aggregate health:

- `requestResponseUsableRunCount`: 2
- `requestResponseBlockedGateCount`: 4
- `averageContentFramesPerSecond`: 1.85
- `averageUpdateMilliseconds`: 464
- `maxP95UpdateMilliseconds`: 611
- `averageFirstByteWaitSharePermille`: 1000
- `averagePayloadReadSharePermille`: 0
- `networkReadDominantSubphase`: `first-byte-wait`
- `recommendedNextProbe`: `inspectUpdateWaitTiming`

Compared with the v57 visible-startup artifact:

- First-frame request area dropped from 364 to 300 permille.
- RGB565 startup improved from about 21.61-21.63 s to about 20.64-20.72 s.
- Full-color profiles still timed out before stream samples.
- The run still fails the poor-network target because startup remains above the
  20 s gate and steady content cadence is only about 1.7-2.0 fps.

## Interpretation

Visible-core startup reduces first-frame traffic and gives a small additional
startup win, but the gain is not large enough to make the benchmark practical.
The next large unit should keep traffic as an explicit target while focusing on
server/update-wait cadence, lower startup pixel pressure, or a staged startup
path that can show useful content before the current first-byte wait dominates.

## Safety

The report and this artifact contain only fixed profile/preset/target/mode
labels, aggregate timing summaries, aggregate counts, aggregate permille ratios,
and fixed issue/triage labels. They do not contain host identity, credentials,
port values, proxy ports, upstream hosts, byte counts, framebuffer dimensions,
coordinates, pixels, cursor pixels, raw payloads, command text, command output,
draft text, marked text, or IME state.
