# 2026-06-06 Sustained v2 ZRLE Zero-Delay Cadence

Target: `iphone-sustained-usability-v2`

## Purpose

The v45 ZRLE isolation run showed that pure ZRLE and cursor-only ZRLE reduce
client/tile tail, but every candidate still misses the 8fps steady-stream
target. This increment tests the next request/response cadence hypothesis:
whether removing the benchmark's post-content request delay is enough to reach
the sustained target.

## Implementation

- Added `sustained-v2-zrle-zero-delay` to
  `--stream-shape-gate-preset`.
- The preset reuses the sustained v2 ZRLE isolation shape:
  `zrle-isolation`, request/response only, 5 rotated iterations, controlled
  12Hz stimulus, app client-pressure pacing, steady-stream viewport mode, and
  skipped standalone ContinuousUpdates probe.
- The only cadence change is `streamShapeFrameIntervalSeconds = 0`, so the
  benchmark requests the next incremental frame immediately after a
  content-bearing response unless app pressure logic applies.
- `VNCLiveBenchmark` report schema is now v46 because the report can emit the
  new fixed preset label.
- Transport/cadence diagnosis now routes mixed request/response failures to
  encoding-profile comparison only when client-decode constraints dominate
  receive-path constraints; receive-path-majority runs route to
  `tuneTransportCadence`.
- Production app defaults are unchanged.

## Verification

- `swift test --filter BenchmarkStreamShapeGatePresetTests`
- `swift test --filter BenchmarkStreamShapeSummaryTests`
- `swift run VNCLiveBenchmark --help | rg -n "sustained-v2-zrle-zero-delay|schema v46|zero post-content"`
- Redacted live `sustained-v2-zrle-zero-delay` run:
  - `schemaVersion`: 46
  - `streamShapeGatePreset`: `sustained-v2-zrle-zero-delay`
  - `streamShapeProfiles`: `zrle-isolation`
  - `streamShapeTransportModes`: `request-response`
  - `streamShapeFrameIntervalSeconds`: 0
  - `continuousUpdatesProbe.status`: `not-tested`
  - `streamShapeStimulusExpectedFramesPerSecond`: 12
  - `streamShapeTransportCadenceDiagnosis.recommendedNextAction`:
    `tuneTransportCadence`
  - `streamShapeOptimizationDecision.recommendedNextProbe`:
    `compareEncodingProfileGate`
  - order-neutral request/response recommendation:
    `zrle-compression-0-clipboard`

Safe aggregate profile result:

| profile | verdict | primary constraint | main issues | usable/run | avg content FPS | avg update | max p95 update | max client p95 | max ZRLE p95 | full upload |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | fail | clientDecode | content-fps-warning, p95-update-warning, p95-update-failed, client-processing-failed, very-slow-update, adaptive-pressure-warning, adaptive-pressure-failed | 5/5 | 6.09 | 128 ms | 507 ms | 138 ms | 135 ms | 0 permille |
| `zrle-compression-0` | fail | receivePath | content-fps-warning, p95-update-warning, p95-update-failed | 5/5 | 6.90 | 118 ms | 502 ms | 12 ms | 11 ms | 0 permille |
| `zrle-compression-0-cursor` | fail | receivePath | content-fps-warning, p95-update-warning, p95-update-failed | 5/5 | 7.09 | 116 ms | 508 ms | 12 ms | 12 ms | 0 permille |
| `zrle-compression-0-clipboard` | fail | receivePath | content-fps-warning, p95-update-warning, p95-update-failed | 5/5 | 7.02 | 116 ms | 502 ms | 13 ms | 13 ms | 0 permille |
| `zrle-compression-0-cursor-clipboard` | fail | clientDecode | content-fps-warning, p95-update-warning, p95-update-failed, client-processing-failed, adaptive-pressure-warning | 5/5 | 6.67 | 118 ms | 510 ms | 135 ms | 132 ms | 0 permille |

## Interpretation

- Zero post-content delay improves the best ZRLE candidates from the v45
  6.4-6.5fps band into roughly the 6.9-7.1fps band, but it still does not reach
  the 8fps steady-stream target.
- Max p95 update remains around 500 ms, so removing benchmark-side
  post-content delay is not enough.
- Pure ZRLE/cursor-only/clipboard-only keep client and ZRLE tile p95 low;
  `local-low-latency` and cursor+clipboard still show client/tile tail.
- Renderer full-upload pressure remains 0 permille.
- The next large unit should tune or inspect request/response cadence beyond
  post-content delay, especially update wait behavior, request region
  assumptions, and sample hit-rate under the current macOS Screen Sharing
  server.

## Safe Reporting

This artifact records only fixed target, preset, mode, profile, verdict, issue,
action, and aggregate metric labels. It does not store host identity,
credentials, port values, raw TCP/RFB errors, framebuffer dimensions,
coordinates, pixels, cursor pixels, byte counts, raw payloads, raw timings,
stimulus command text, command output, draft text, marked text, IME state, or
full diagnostic payloads.
