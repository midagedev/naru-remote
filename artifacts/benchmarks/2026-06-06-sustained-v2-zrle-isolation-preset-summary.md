# 2026-06-06 Sustained v2 ZRLE Isolation Preset

Target: `iphone-sustained-usability-v2`

## Purpose

The steady-stream gate is now separate from active zoom/pan hand-feel. The next
large unit is request/response profile isolation: decide whether the default
profile's tail is still the main blocker, or whether the remaining gap is
mostly server/update cadence.

This increment adds a standard preset so future runs do not have to hand-build
the same long command shape:

- controlled 12Hz external stimulus
- 10 second measured window per probe
- 5 rotated iterations
- request/response transport only
- `zrle-isolation` profile set
- standalone ContinuousUpdates probe skipped
- steady-stream viewport mode

## Implementation

- Added `sustained-v2-zrle-isolation` to
  `--stream-shape-gate-preset`.
- The preset reuses the sustained v2 gate shape and selects
  `--stream-shape-profiles zrle-isolation`.
- The preset uses request/response only and reports
  `continuousUpdatesProbe.status = not-tested`.
- `VNCLiveBenchmark` report schema is now v45 because the report can emit the
  new fixed preset label.
- Production app defaults are unchanged.

## Verification

- `swift test --filter BenchmarkStreamShapeGatePresetTests`
- `swift run VNCLiveBenchmark --help | rg -n "sustained-v2-zrle-isolation|schema v45|request/response-only ZRLE"`
- Redacted live `sustained-v2-zrle-isolation` run:
  - `schemaVersion`: 45
  - `streamShapeGatePreset`: `sustained-v2-zrle-isolation`
  - `streamShapeProfiles`: `zrle-isolation`
  - `streamShapeTransportModes`: `request-response`
  - `continuousUpdatesProbe.status`: `not-tested`
  - `streamShapeStimulusExpectedFramesPerSecond`: 12
  - `streamShapeTransportCadenceDiagnosis.recommendedNextAction`:
    `compareRequestResponseEncodingProfiles`
  - `streamShapeOptimizationDecision.recommendedNextProbe`:
    `inspectServerTransportCadence`
  - order-neutral request/response recommendation:
    `zrle-compression-0-clipboard`

Safe aggregate profile result:

| profile | verdict | primary constraint | main issues | usable/run | avg content FPS | avg update | max p95 update | max client p95 | max ZRLE p95 | full upload |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | fail | clientDecode | content-fps-warning, p95-update-warning, p95-update-failed, client-processing-failed, very-slow-update, adaptive-pressure-warning, adaptive-pressure-failed | 5/5 | 5.66 | 127 ms | 504 ms | 105 ms | 103 ms | 0 permille |
| `zrle-compression-0` | warning | receivePath | content-fps-warning, p95-update-warning | 5/5 | 6.52 | 107 ms | 493 ms | 13 ms | 13 ms | 0 permille |
| `zrle-compression-0-cursor` | warning | receivePath | content-fps-warning, p95-update-warning | 5/5 | 6.42 | 108 ms | 485 ms | 12 ms | 11 ms | 0 permille |
| `zrle-compression-0-clipboard` | fail | receivePath | probe-failed, content-fps-warning, p95-update-warning | 4/5 | 6.45 | 107 ms | 483 ms | 9 ms | 10 ms | 0 permille |
| `zrle-compression-0-cursor-clipboard` | fail | clientDecode | content-fps-warning, p95-update-warning, p95-update-failed, client-processing-failed, adaptive-pressure-warning, adaptive-pressure-failed | 5/5 | 5.72 | 115 ms | 504 ms | 152 ms | 146 ms | 0 permille |

## Interpretation

The preset makes the current split clear:

- Pure ZRLE compression 0 and cursor-only ZRLE remove the large client/tile
  tail seen in the default label.
- All profiles still miss the 8fps steady-stream content target and remain near
  the 480-504 ms max p95 update band.
- Renderer full-upload pressure is not the current blocker.
- The next larger unit should inspect server/request-response cadence and
  sample hit-rate before changing production defaults.

## Safe Reporting

This artifact records only fixed target, preset, mode, profile, verdict, issue,
action, and aggregate metric labels. It does not store host identity,
credentials, port values, raw TCP/RFB errors, framebuffer dimensions,
coordinates, pixels, cursor pixels, byte counts, raw payloads, raw timings,
stimulus command text, command output, draft text, marked text, IME state, or
full diagnostic payloads.
