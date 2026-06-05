# 2026-06-06 Controlled Stimulus Cadence Target

Target: `iphone-sustained-usability-v2`

## Purpose

The sustained v2 live gates compare measured content-frame FPS against a
controlled dynamic-content stimulus. Recent request/response-only runs still
showed content FPS far below target, but the report did not state the stimulus
cadence, making it too easy to confuse a server/transport cadence problem with
a weak benchmark stimulus.

This increment records the configured stimulus cadence in schema v44 and passes
it to the repo-native `VNCLiveStimulusWindow`.

## Implementation

- `VNCLiveBenchmark` now reports:
  - `streamShapeStimulusFrameIntervalSeconds`
  - `streamShapeStimulusExpectedFramesPerSecond`
- The external stimulus child receives
  `NARU_LIVE_STIMULUS_FRAME_INTERVAL_SECONDS`.
- `VNCLiveStimulusWindow` uses that environment value unless an explicit
  `--frame-interval` argument overrides it.
- The sustained v2 presets keep the controlled stimulus at 12 Hz.
- Production app defaults are unchanged.

## Interpretation

For the v2 gate, a 12 Hz controlled stimulus and an 8fps pass target means the
benchmark is asking Naru to deliver at least about two thirds of the intended
visible motion cadence. If a future run reports expected stimulus FPS near 12
while measured content FPS remains near 2, the next large unit should inspect
server transport cadence, request/response profile behavior, or sample hit-rate
instead of treating renderer upload or stimulus generation as the primary
suspect.

## Verification

- `swift test --filter BenchmarkStreamShapeStimulusEnvironmentTests`
- Short redacted localhost smoke with explicit 0.0833s stimulus interval:
  - `schemaVersion`: 44
  - `streamShapeStimulusFrameIntervalSeconds`: 0.0833
  - `streamShapeStimulusExpectedFramesPerSecond`: about 12
  - `continuousUpdatesProbe.status`: `not-tested`

## Safe Reporting

This artifact records only fixed target labels and configured aggregate
cadence. It does not store host identity, credentials, port values, raw TCP/RFB
errors, framebuffer dimensions, coordinates, pixels, cursor pixels, byte
counts, raw payloads, raw FPS, raw timings, stimulus command text, command
output, draft text, marked text, IME state, or full diagnostic payloads.
