# Moderate Adaptive Pressure Pacing

Date: 2026-06-05

Purpose: respond to sustained iPhone heat / low-FPS reports by making adaptive
client-pressure pacing react before local work reaches the old severe 80 ms
stall threshold.

## Change

- Runtime adaptive pressure now has two activation paths:
  - severe local work: 80 ms or more for 3 consecutive content frames
  - sustained moderate local work: 34 ms or more for 8 consecutive content frames
- The runtime trigger considers the larger of receive-side client processing and
  app frame-apply timing.
- `VNCLiveBenchmark --stream-shape-client-pressure app` mirrors the benchmarkable
  client-processing side of the same severe/moderate trigger.
- Empty incremental updates still do not break a content-frame pressure streak,
  and transport idle timeouts still reset it.

## Rationale

The previous adaptive trigger caught obvious stalls but not a phone that kept
doing 34-79 ms of local work while continuing to request at 60 Hz-class cadence.
That range is already above the 30 fps frame budget, so sustained samples there
are a practical signal to use the existing temporary power-saver pacing floor.

## Verification

- `swift test --filter NaruRemoteAppModelTests/testSessionStreamPressurePacingState --filter BenchmarkStreamShapePacingPolicyTests`

## Privacy

No new raw timing, dimensions, coordinates, pixels, byte counts, host identity,
power state, or errors are exported. The app uses raw timing only in memory while
the stream is alive; diagnostics and benchmark reports keep the existing safe
aggregate fields.

## Residual Risk

This does not directly fix gesture smoothness or Compose input correctness. It
only reduces sustained local pressure once repeated moderate frame-processing
work is detected; physical iPhone validation remains required.
