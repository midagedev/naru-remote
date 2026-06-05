# 2026-06-06 Request/Response Preset Skips Continuous Probe

Target: `iphone-sustained-usability-v2`

## Purpose

`sustained-v2-request-response` exists to compare request/response profile and
cadence candidates after ContinuousUpdates has already been routed to support
inspection. The first implementation limited stream-shape profile probes to
request/response, but the standalone `continuousUpdatesProbe` still ran and
reported a separate ContinuousUpdates failure in the same JSON.

This increment makes the request/response preset skip that standalone probe as
well.

## Implementation

- `--continuous-update-samples 0` is now accepted.
- A zero-sample standalone ContinuousUpdates probe reports fixed status
  `not-tested` without opening a ContinuousUpdates connection.
- `sustained-v2-request-response` sets `continuousUpdateSamples` to 0.
- `sustained-v2-core` and `sustained-v2-pixel-format` keep their existing
  ContinuousUpdates probe shape.
- Production app defaults are unchanged.

## Expected Report Shape

For `sustained-v2-request-response`:

- `streamShapeTransportModes`: `request-response`
- `continuousUpdateSamples`: 0
- `continuousUpdatesProbe.status`: `not-tested`
- `continuousUpdatesProbe.requestedSamples`: 0
- `streamShapeTransportCadenceDiagnosis.continuousUpdatesStatus`: `not-tested`

This keeps request/response candidate comparisons free of known
ContinuousUpdates blocker noise while preserving the full `sustained-v2-core`
promotion gate.

## Live Verification Result

The live request/response preset run after this change confirmed:

- `continuousUpdateSamples`: 0
- `continuousUpdatesProbe.status`: `not-tested`
- `continuousUpdatesProbe.requestedSamples`: 0
- `streamShapeTransportModes`: `request-response`
- `streamShapeTransportCadenceDiagnosis.continuousUpdatesStatus`:
  `not-tested`
- `streamShapeTransportCadenceDiagnosis.recommendedNextAction`:
  `compareRequestResponseEncodingProfiles`
- `streamShapeOptimizationDecision.verdict`: `fail`

The run is still not benchmark-green; it only proves the request/response-only
preset no longer performs the standalone ContinuousUpdates probe.

## Verification

- `swift test --filter BenchmarkStreamShapeGatePresetTests`
- `swift run VNCLiveBenchmark --environment-preflight
  --stream-shape-gate-preset sustained-v2-request-response --ask-password
  --json`
- `swift run VNCLiveBenchmark
  --stream-shape-gate-preset sustained-v2-request-response --ask-password
  --json`

## Safe Reporting

This artifact records only fixed preset, transport, probe-status, and target
labels. It does not store host identity, credentials, port values, raw TCP/RFB
errors, framebuffer dimensions, coordinates, pixels, cursor pixels, byte
counts, raw payloads, raw FPS, raw timings, stimulus command text, command
output, draft text, marked text, IME state, or full diagnostic payloads.
