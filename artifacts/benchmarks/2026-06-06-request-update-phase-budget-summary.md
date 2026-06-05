# Request/update phase budget live sweep — 2026-06-06

This artifact records the first schema v49 phase-budget run for the sustained
v2 request/response pacing sweep. The raw JSON was written to `/tmp` and is not
committed.

## Command

```bash
swift build --product VNCLiveStimulusWindow

NARU_LIVE_MAC_HOST=127.0.0.1 \
NARU_LIVE_STIMULUS_COMMAND='.build/debug/VNCLiveStimulusWindow --duration "$NARU_LIVE_STIMULUS_DURATION_SECONDS"' \
swift run VNCLiveBenchmark \
  --ask-password \
  --stream-shape-gate-preset sustained-v2-zrle-pacing-sweep \
  --json > /tmp/naru-phase-budget-v49.json
```

Credential entry used the hidden password prompt. The report did not emit host
identity, password, server name, framebuffer dimensions, coordinates, pixels,
cursor pixels, byte counts, raw TCP/RFB errors, raw payloads, stimulus command
output, draft text, marked text, IME state, or per-sample raw timings.

## Safe Result Summary

- `schemaVersion`: 49
- `streamShapeGatePreset`: `sustained-v2-zrle-pacing-sweep`
- `streamShapeProfiles`: `zrle-compression-0-clipboard`
- `streamShapeTransportModes`: `request-response`
- `streamShapePacingWindows`: `zero-content-delay`,
  `app-balanced-30hz`, `stimulus-aligned-12hz`

Request cadence health:

- `sampleStatus`: `high-content-hit`
- `latencyStatus`: `p95-failed`
- `recommendedNextProbe`: `inspectUpdateWaitTiming`
- `dominantPhase`: `network-read`
- `slowDominantPhase`: `network-read`
- `averageContentFramesPerSecond`: 4.76
- `averageUpdateMilliseconds`: 142
- `maxP95UpdateMilliseconds`: 505
- hit-rate permille average:
  - received/request: 986
  - content/request: 819
  - content/response: 831
  - unanswered/request: 14
- request/response gate counts:
  - blocked/total: 3/3
  - usable runs/aggregate count: 15/3
- primary constraints:
  - `contentCadence`: 3
  - `receivePath`: 10
  - `clientDecode`: 2

Order-neutral recommendation:

- profile: `zrle-compression-0-clipboard`
- pacing window: `zero-content-delay`
- average update: 125 ms
- p95 update: 505 ms
- content FPS: 6.52
- renderer full upload permille: 0

## Aggregate Phase Budget

| pacing window | usable | avg update | max p95 | content fps | dominant | slow dominant | network/client/request-loop share |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| `zero-content-delay` | 5/5 | 125 ms | 505 ms | 6.52 | `network-read` | `network-read` | 913 / 81 / 5 |
| `app-balanced-30hz` | 5/5 | 137 ms | 501 ms | 4.74 | `network-read` | `network-read` | 962 / 29 / 9 |
| `stimulus-aligned-12hz` | 5/5 | 163 ms | 459 ms | 3.04 | `network-read` | `network-read` | 910 / 83 / 7 |

## Interpretation

The new phase budget rules out local decode/render as the primary blocker for
this run. Across all pacing windows, measured time is dominated by
`network-read`; request-loop overhead is only 5-9 permille, and client
processing stays secondary.

The earlier v48 conclusion still holds: slowing request pacing can lower p95
only by collapsing visible content FPS. `zero-content-delay` remains the best
current candidate by average update latency and content FPS, but it still misses
the sustained v2 practical target because max p95 stays just above 500 ms and
content FPS remains below 8.

Next large unit: inspect and reduce request/response update-wait/read tail in
the VNC transport path. Do not spend the next PR on another pacing-delay sweep
or a production default change.
