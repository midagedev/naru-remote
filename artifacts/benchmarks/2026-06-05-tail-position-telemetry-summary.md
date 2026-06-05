# 2026-06-05 Tail Position Telemetry Summary

## Trigger

After T382 split single-spike cooldown from sustained pressure recovery, the
remaining question was where the 1000 ms-class tail appears. Prior benchmark
JSON preserved only aggregate tail counts, so a PR author could not tell
whether one very-slow sample was the first content update, a later recurring
decode/apply stall, or profile-order variance without inspecting local scratch
data.

## Change

`BenchmarkStreamShapeTailSummary` now reports optional safe ordinal aggregates:

- `firstSlowUpdateOrdinal`
- `firstSlowContentUpdateOrdinal`
- `firstVerySlowUpdateOrdinal`
- `firstVerySlowContentUpdateOrdinal`

`VNCLiveBenchmark` schema v30 includes those fields under `tailLatency`, and the
human report prints the first very-slow update/content ordinal when present.

The fields are one-based sequence numbers only. They do not export raw
per-frame samples, timestamps, host identity, credentials, framebuffer
dimensions, coordinates, pixels, cursor pixels, byte counts, or raw errors.

## Safe Aggregate Result

Command shape:

```bash
swift run VNCLiveBenchmark \
  --first-frame-profiles none \
  --stream-shape-profiles local-low-latency \
  --stream-shape-transport request-response \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 20 \
  --stream-shape-client-pressure app \
  --stream-shape-viewport-interaction app \
  --full-refresh-samples 0 \
  --timeout 8 \
  --idle-timeout 0.75 \
  --json
```

Safe aggregate output:

- schema: 30
- profile: `local-low-latency`
- verdict: `fail`
- issue codes: `content-fps-failed`, `client-processing-failed`,
  `very-slow-update`, `adaptive-pressure-warning`
- received/content samples: 38/36
- content FPS: 1.80
- update latency p50/p95/max: 155/391/2418 ms
- client-processing p50/p95/max: 5/166/2158 ms
- slow/very-slow samples: 14/1
- first slow update/content ordinal: 2/1
- first very-slow update/content ordinal: 2/1
- adaptive pressure permille: 395
- renderer full-upload permille: 0

## Interpretation

For this local macOS Screen Sharing target, the measured 2 second-class tail is
the first content update in the stream-shape run, not a later repeated stall.
That supports treating the next optimization unit as a cold first-content-frame
path investigation: initial ZRLE inflate/apply, initial texture/app publication,
or first post-full-refresh server update shape.

It does not close the practical baseline. Content FPS and client-processing
tail still fail the v1 target, and physical iPhone heat/hand-feel still needs
device validation.

## Verification

- `swift test --filter BenchmarkStreamShapeSummaryTests`
  - Result: passed, 21 tests, 0 failures.
- Live `VNCLiveBenchmark` 20 second `local-low-latency` run
  - Result: command succeeded, schema v30, first very-slow update/content
    ordinal reported as 2/1.
