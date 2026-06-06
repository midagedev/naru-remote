# Constrained-Cellular Visible Startup Summary — 2026-06-06

This increment tests first-visible-region startup as the next poor-network
traffic lever after the schema v56 full-frame bootstrap baseline. It keeps
production startup unchanged and adds a benchmark-only opt-in path.

## What Changed

- Added `RFBFramePumpConfiguration.initialRequestRegion`, defaulting to `nil`
  so existing callers still request a full first frame.
- Added `--stream-shape-first-frame-request full|match-request-region`.
- Added `--stream-shape-gate-preset
  sustained-v2-constrained-cellular-visible-startup`.
- Bumped `VNCLiveBenchmark` reports to schema v57.

The visible-startup preset keeps the schema v56 constrained-cellular shape but
sets:

- `streamShapeFirstFrameRequestMode`: `match-request-region`
- `streamShapeRequestRegions`: `viewport-phone-portrait`
- `networkCondition`: `constrained-cellular`
- `streamShapePracticalTarget`: `iphone-poor-network-traffic-v1`

Protocol basis: RFC 6143 §7.5.3 defines `FramebufferUpdateRequest` as an
interest rectangle plus an incremental flag; a non-incremental request asks for
the complete contents of the specified area.

## Verification Commands

```sh
swift test --filter RFBFramePumpTests
swift test --filter FakeRFBServerEncodingTests
swift test --filter BenchmarkStreamShapeFirstFrameRequestModeTests
swift test --filter BenchmarkStreamShapeGatePresetTests
swift test
swift run VNCLiveBenchmark --help | rg -n "schema v57|first-frame-request|visible-startup|constrained-cellular"
swift run VNCLiveBenchmark --stream-shape-gate-preset sustained-v2-constrained-cellular-visible-startup --json
```

## Live Result

Safe aggregate report fields:

- `schemaVersion`: 57
- `networkCondition`: `constrained-cellular`
- `streamShapeGatePreset`: `sustained-v2-constrained-cellular-visible-startup`
- `streamShapePracticalTarget`: `iphone-poor-network-traffic-v1`
- `streamShapeFirstFrameRequestMode`: `match-request-region`
- `streamShapeRequestRegions`: `viewport-phone-portrait`
- `requestRegionAreaPermille`: 364 for every profile probe

Per-profile result:

| Profile | Startup | Samples | Steady Avg / P95 | Content FPS | Gate Verdict | Primary Issue |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| `local-low-latency` | timeout | 0/4 | n/a | n/a | fail | `probe-failed` |
| `local-low-latency-rgb565` | 21.629 s | 4/4 | 364 / 578 ms | 2.75 | fail | `first-frame-failed` |
| `zrle-compression-0` | timeout | 0/4 | n/a | n/a | fail | `probe-failed` |
| `zrle-compression-0-rgb565` | 21.606 s | 4/4 | 553 / 1312 ms | 0.86 | fail | `first-frame-failed` |

Request/response aggregate health:

- `requestResponseUsableRunCount`: 2
- `requestResponseBlockedGateCount`: 4
- `averageContentFramesPerSecond`: 1.80
- `averageUpdateMilliseconds`: 459
- `maxP95UpdateMilliseconds`: 1312
- `averageFirstByteWaitSharePermille`: 866
- `averagePayloadReadSharePermille`: 134
- `networkReadDominantSubphase`: `first-byte-wait`

Compared with the v56 full-frame bootstrap artifact:

- RGB565 startup improved from about 30.25-30.28 s to about 21.61-21.63 s.
- Full-color profiles still timed out before stream samples.
- The run still fails the poor-network target because startup remains above the
  20 s gate and the ZRLE RGB565 tail regressed to a 1312 ms p95 update.

## Interpretation

First-visible-region startup is a real traffic/startup lever: the RGB565 first
frame improves by roughly 8.6 seconds under the same constrained-cellular
benchmark shape. It is not production-ready. The next large unit should keep
traffic as a first-class goal but either reduce the startup region further,
lower the initial pixel format/remote resolution more aggressively, or inspect
server update-wait timing so the full-color profiles stop timing out.

## Safety

The report and this artifact contain only fixed profile/preset/target/mode
labels, aggregate timing summaries, aggregate counts, aggregate permille ratios,
and fixed issue/triage labels. They do not contain host identity, credentials,
port values, proxy ports, upstream hosts, byte counts, framebuffer dimensions,
coordinates, pixels, cursor pixels, raw payloads, command text, command output,
draft text, marked text, or IME state.
