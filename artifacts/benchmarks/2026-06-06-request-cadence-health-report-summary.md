# Request Cadence Health Report - 2026-06-06

Target: `iphone-sustained-usability-v2`

## Purpose

The v46 zero-delay ZRLE gate showed that removing post-content request delay
improved the strongest request/response candidates but did not reach the 8fps
steady-stream target. This increment adds a report layer that separates
request-response hit-rate health from aggregate update tail latency before the
next cadence/default change.

## Implementation

- Bumped `VNCLiveBenchmark` report schema to v47.
- Added top-level `streamShapeRequestCadenceHealth`.
- The health report is derived only from existing request/response
  `streamShapeProfileAggregates` and `streamShapeProfileGates`.
- It reports fixed labels for:
  - `sampleStatus`
  - `latencyStatus`
  - `recommendedNextProbe`
- It also reports aggregate request/response gate counts, usable run counts,
  hit-rate permille means, update millisecond summaries, content FPS, fixed
  primary-constraint counts, and fixed failure-label counts.
- Production app defaults are unchanged.

## Verification

- `swift test --filter BenchmarkStreamShapeSummaryTests`
- `swift build --product VNCLiveStimulusWindow`
- `swift run VNCLiveBenchmark --help | rg -n "schema v47|sustained-v2-zrle-zero-delay|request/response-only ZRLE|zero post-content"`
- Redacted live `sustained-v2-zrle-zero-delay` run:
  - `schemaVersion`: 47
  - `streamShapeGatePreset`: `sustained-v2-zrle-zero-delay`
  - `streamShapeProfiles`: `zrle-isolation`
  - `streamShapeTransportModes`: `request-response`
  - `streamShapeFrameIntervalSeconds`: 0
  - `continuousUpdatesProbe.status`: `not-tested`
  - `streamShapeStimulusExpectedFramesPerSecond`: 12
  - `streamShapeTransportCadenceDiagnosis.recommendedNextAction`:
    `tuneTransportCadence`
  - `streamShapeRequestCadenceHealth.sampleStatus`: `high-content-hit`
  - `streamShapeRequestCadenceHealth.latencyStatus`: `p95-failed`
  - `streamShapeRequestCadenceHealth.recommendedNextProbe`:
    `tuneRequestPacingWindow`

Safe request cadence aggregate:

| field | value |
| --- | ---: |
| request-response gates blocked / total | 5 / 5 |
| request-response usable runs | 24 |
| average received/request permille | 989 |
| average content/request permille | 857 |
| average content/response permille | 867 |
| average unanswered/request permille | 11 |
| average update | 120 ms |
| max p95 update | 511 ms |
| average content FPS | 6.66 |
| receivePath constraint count | 21 |
| clientDecode constraint count | 4 |

Safe aggregate profile result:

| profile | verdict | primary constraint | usable/run | avg content FPS | avg update | max p95 update | max client p95 | max ZRLE p95 | received/request | content/response | unanswered | full upload |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | fail | clientDecode | 5/5 | 5.97 | 129 ms | 502 ms | 159 ms | 152 ms | 986 | 842 | 14 | 0 |
| `zrle-compression-0` | fail | receivePath | 4/5 | 6.47 | 121 ms | 511 ms | 142 ms | 140 ms | 994 | 857 | 7 | 0 |
| `zrle-compression-0-cursor` | fail | receivePath | 5/5 | 6.93 | 118 ms | 504 ms | 11 ms | 11 ms | 990 | 876 | 10 | 0 |
| `zrle-compression-0-clipboard` | fail | receivePath | 5/5 | 7.08 | 115 ms | 503 ms | 13 ms | 12 ms | 988 | 883 | 12 | 0 |
| `zrle-compression-0-cursor-clipboard` | fail | clientDecode | 5/5 | 6.84 | 118 ms | 499 ms | 142 ms | 139 ms | 987 | 876 | 13 | 0 |

Order-neutral request/response recommendation:

- `zrle-compression-0-clipboard`
- Average content FPS: 7.08
- Average update / max p95 update: 115 / 503 ms
- Content/response permille: 883
- Renderer full-upload permille: 0

## Interpretation

- The current request/response path is receiving responses with content most of
  the time: unanswered/request is only 11 permille and content/response is 867
  permille across usable request-response runs.
- The remaining broad blocker is p95 update tail, not empty responses or
  unanswered waits.
- The next large unit should tune or instrument the request pacing window and
  update-wait timing. Production defaults should not change yet because every
  gate still fails, max p95 update remains over target, and one
  `zrle-compression-0` run failed with the fixed `stream-connect-read-timeout`
  label.

## Safe Reporting

This artifact records only fixed target, preset, mode, profile, verdict, issue,
action, aggregate count, aggregate permille, aggregate FPS, and aggregate
millisecond labels. It does not store host identity, credentials, port values,
raw TCP/RFB errors, framebuffer dimensions, coordinates, pixels, cursor pixels,
byte counts, raw payloads, raw timings, stimulus command text, command output,
draft text, marked text, IME state, or full diagnostic payloads.
