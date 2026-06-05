# Request Pacing Window Sweep Summary

Date: 2026-06-06 KST

Purpose: compare fixed request/response pacing windows without changing
production defaults. The prior v47 zero-delay health report showed high content
hit-rate with a p95 update tail, so this run holds the ZRLE profile constant and
changes only the benchmark pacing window.

Command shape:

```bash
NARU_LIVE_MAC_HOST=127.0.0.1 \
NARU_LIVE_STIMULUS_COMMAND='.build/debug/VNCLiveStimulusWindow --duration "$NARU_LIVE_STIMULUS_DURATION_SECONDS"' \
swift run VNCLiveBenchmark \
  --ask-password \
  --stream-shape-gate-preset sustained-v2-zrle-pacing-sweep \
  --json
```

Raw JSON was written to `/tmp/naru-pacing-window-sweep-v48.json` and was not
committed. The committed summary below contains only fixed labels and aggregate
metrics.

## Implementation

- Added `sustained-v2-zrle-pacing-sweep`.
- Bumped `VNCLiveBenchmark` report schema to v48.
- Added fixed pacing-window labels to stream-shape probes, aggregates, gates,
  and recommendations.
- The sweep keeps `zrle-compression-0-clipboard` constant, uses
  request/response transport only, skips the standalone ContinuousUpdates probe,
  and rotates 5 iterations across:
  - `zero-content-delay`
  - `app-balanced-30hz`
  - `stimulus-aligned-12hz`

## Live Result

- `schemaVersion`: 48
- `streamShapeGatePreset`: `sustained-v2-zrle-pacing-sweep`
- `streamShapeProfiles`: `zrle-compression-0-clipboard`
- `streamShapeTransportModes`: `request-response`
- `continuousUpdatesProbe.status`: `not-tested`
- `streamShapeRequestCadenceHealth.sampleStatus`: `high-content-hit`
- `streamShapeRequestCadenceHealth.latencyStatus`: `p95-failed`
- `streamShapeRequestCadenceHealth.recommendedNextProbe`:
  `tuneRequestPacingWindow`

| pacing window | usable runs | avg content fps | avg update ms | max p95 update ms | content/request permille | content/response permille | max client p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `zero-content-delay` | 5/5 | 6.46 | 128 | 507 | 858 | 870 | 15 |
| `app-balanced-30hz` | 5/5 | 4.56 | 147 | 506 | 854 | 864 | 140 |
| `stimulus-aligned-12hz` | 5/5 | 3.00 | 162 | 464 | 728 | 743 | 146 |

Order-neutral recommendation:

- profile: `zrle-compression-0-clipboard`
- pacing window: `zero-content-delay`
- reason: lowest average update latency across order-neutral request/response
  runs
- avg update/max p95: 128/507 ms
- avg content fps: 6.46
- renderer full-upload permille: 0

## Interpretation

- Slowing request pacing did not rescue the sustained v2 target.
  `stimulus-aligned-12hz` reduced max p95 below the hard-fail threshold but
  collapsed content FPS to about 3fps.
- `app-balanced-30hz` kept hit-rate high but introduced client-decode pressure
  in this run and still missed the target.
- `zero-content-delay` remains the best of these three benchmark windows, but it
  still fails the v2 target because max p95 update stays just above 500 ms and
  average content FPS remains below 8fps.
- The next large unit should inspect update-wait/read-tail timing within the
  request/response path rather than promote a slower pacing window or change
  app defaults.

## Verification

- `swift test --filter BenchmarkStreamShapeSummaryTests`
- `swift test --filter BenchmarkStreamShapePacingPolicyTests`
- `swift test --filter BenchmarkStreamShapeGatePresetTests`
- `swift run VNCLiveBenchmark --help | rg -n "schema v48|sustained-v2-zrle-pacing-sweep|fixed request pacing windows|stream-shape-gate-preset"`
- Redacted live `sustained-v2-zrle-pacing-sweep` run above.
