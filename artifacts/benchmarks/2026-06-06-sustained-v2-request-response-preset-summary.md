# 2026-06-06 Sustained v2 Request/Response Preset Summary

Target: `iphone-sustained-usability-v2`

## Purpose

The completed live `sustained-v2-core` baseline showed two different blockers
in one report: ContinuousUpdates is not confirmed by the current local VNC
target, and request/response remains below the sustained v2 target. This
increment adds a larger-unit benchmark preset that keeps the same controlled
stimulus and core profile matrix while isolating request/response transport.

## Implementation

- Added `sustained-v2-request-response` to
  `BenchmarkStreamShapeGatePreset`.
- The new preset uses the same profile matrix, iterations, pacing, pressure,
  viewport-interaction, stimulus, duration, preflight, target, and timeout
  shape as `sustained-v2-core`.
- The only shape difference is `streamShapeTransportModes = request-response`.
- Production app defaults are unchanged.

## Why This Helps

- Use `sustained-v2-core` when checking whether both transports can graduate.
- Use `sustained-v2-request-response` when ContinuousUpdates is already known
  to be blocked and the next question is which request/response profile or
  cadence candidate should move toward physical iPhone testing.
- Keep ContinuousUpdates investigation separate instead of allowing an
  unsupported extension path to obscure request/response candidate comparisons.

## Verification

- `swift test --filter BenchmarkStreamShapeGatePresetTests`
- `swift run VNCLiveBenchmark --environment-preflight
  --stream-shape-gate-preset sustained-v2-request-response --ask-password
  --json`
- `swift run VNCLiveBenchmark
  --stream-shape-gate-preset sustained-v2-request-response --ask-password
  --json`

## First Live Request/Response Gate

The first completed live run with the new preset reported:

- `schemaVersion`: 43
- `streamShapeGatePreset`: `sustained-v2-request-response`
- `streamShapeTransportModes`: `request-response`
- `streamShapeOptimizationDecision.verdict`: `fail`
- failed gates: 4 of 4
- `streamShapeOptimizationDecision.primaryIssueCode`:
  `client-processing-failed`
- `streamShapeOptimizationDecision.primaryConstraint`: `clientDecode`
- `streamShapeOptimizationDecision.recommendedNextProbe`:
  `compareEncodingProfileGate`
- `streamShapeTransportCadenceDiagnosis.continuousUpdatesStatus`:
  `not-tested`
- `streamShapeTransportCadenceDiagnosis.requestResponseStatus`:
  `below-target`
- `streamShapeTransportCadenceDiagnosis.recommendedNextAction`:
  `compareRequestResponseEncodingProfiles`
- order-neutral request/response recommendation label:
  `adaptive-good-full`

This confirms the new preset removes the known ContinuousUpdates blocker from
request/response candidate comparison. It is still not benchmark-green and does
not authorize any production default change.

## Safe Reporting

This artifact records only fixed preset, profile, transport, and target labels.
It does not store host identity, credentials, port values, raw TCP/RFB errors,
framebuffer dimensions, coordinates, pixels, cursor pixels, byte counts, raw
payloads, raw FPS, raw timings, stimulus command text, command output, draft
text, marked text, IME state, or full diagnostic payloads.
