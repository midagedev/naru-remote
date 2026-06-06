# Constrained-Cellular Bootstrap Traffic Gate Summary — 2026-06-06

This increment makes poor-network traffic a first-class benchmark target and
records the first schema v56 live run against a real VNC server through the
benchmark-local constrained-cellular proxy.

## What Changed

- Added `iphone-poor-network-traffic-v1` as a practical target.
- Added fixed gate issue codes:
  - `first-frame-warning`
  - `first-frame-failed`
  - `request-region-area-warning`
  - `request-region-area-failed`
- Added `--stream-shape-gate-preset
  sustained-v2-constrained-cellular-bootstrap`.
- Bumped `VNCLiveBenchmark` reports to schema v56.

The preset applies:

- `networkCondition`: `constrained-cellular`
- `streamShapePracticalTarget`: `iphone-poor-network-traffic-v1`
- `streamShapeProfiles`: `pixel-format-isolation`
- `streamShapeTransportModes`: `request-response`
- `streamShapeRequestRegions`: `viewport-phone-portrait`
- `streamShapeSamples`: 4
- `timeoutSeconds`: 30
- `idleTimeoutSeconds`: 5

## Verification Commands

```sh
swift test --filter BenchmarkStreamShapeSummaryTests
swift test --filter BenchmarkStreamShapeGatePresetTests
swift run VNCLiveBenchmark --help | rg -n "schema v56|constrained-cellular-bootstrap|iphone-poor-network-traffic|network-condition"
swift run VNCLiveBenchmark --environment-preflight --stream-shape-gate-preset sustained-v2-constrained-cellular-bootstrap --json
swift run VNCLiveBenchmark --stream-shape-gate-preset sustained-v2-constrained-cellular-bootstrap --json
```

## Live Result

Safe aggregate report fields:

- `schemaVersion`: 56
- `networkCondition`: `constrained-cellular`
- `streamShapeGatePreset`: `sustained-v2-constrained-cellular-bootstrap`
- `streamShapePracticalTarget`: `iphone-poor-network-traffic-v1`
- `streamShapeRequestRegions`: `viewport-phone-portrait`
- `streamShapeSamples`: 4

Per-profile gate summary:

| Profile | Startup | Samples | Gate Verdict | Primary Issue |
| --- | ---: | ---: | --- | --- |
| `local-low-latency` | timeout | 0/4 | fail | `probe-failed` |
| `local-low-latency-rgb565` | 30.250 s | 4/4 | fail | `first-frame-failed` |
| `zrle-compression-0` | timeout | 0/4 | fail | `probe-failed` |
| `zrle-compression-0-rgb565` | 30.281 s | 4/4 | fail | `first-frame-failed` |

Request/response aggregate health:

- `requestResponseUsableRunCount`: 2
- `requestResponseBlockedGateCount`: 4
- `averageRequestRegionAreaPermille`: 364 for each profile gate
- `averageContentFramesPerSecond`: 1.87
- `averageUpdateMilliseconds`: 470
- `maxP95UpdateMilliseconds`: 623
- `averageFirstByteWaitSharePermille`: 1000
- `networkReadDominantSubphase`: `first-byte-wait`

## Interpretation

RGB565 is a real bootstrap lever: both RGB565 candidates reached steady-state
samples under the constrained-cellular profile while the full-color candidates
timed out before the first stream sample. It is not enough for the poor-network
target, because a roughly 30 second first frame fails the startup gate.

The next large unit should test a first-visible-region startup path, or an
equivalent server-side resolution / initial-region strategy, before promoting
viewport-aware request-region or low-color defaults into production.

## Safety

The report and this artifact contain only fixed profile/preset/target labels,
aggregate timing summaries, aggregate counts, aggregate permille ratios, and
fixed issue/triage labels. They do not contain host identity, credentials, port
values, proxy ports, upstream hosts, byte counts, framebuffer dimensions,
coordinates, pixels, cursor pixels, raw payloads, command text, command output,
draft text, marked text, or IME state.
