# 2026-06-06 Live Sustained v2 Core Baseline

Target: `iphone-sustained-usability-v2`

## Purpose

This artifact records the first completed live `sustained-v2-core` gate after
the environment preflight could route to `run-live-gate`. It fixes the next
larger work unit around evidence from a real VNC session instead of another
isolated simulator or diagnostic-only increment.

## Setup Readiness

Environment preflight schema v2 reported:

- `canRunLiveBenchmark`: true
- `setupActionLabels`: `run-live-gate`
- `hostStatus`: `configured`
- `credentialStatus`: `promptRequested`
- `stimulusCommandStatus`: `configured`

The credential was entered through the hidden password prompt. No password,
host value, port value, or stimulus command text is stored in this artifact.

## Live Gate Result

The live gate completed with:

- `schemaVersion`: 43
- `streamShapeGatePreset`: `sustained-v2-core`
- `streamShapePracticalTarget`: `iphone-sustained-usability-v2`
- `streamShapeOptimizationDecision.verdict`: `fail`
- `streamShapeOptimizationDecision.primaryIssueCode`: `probe-failed`
- `streamShapeOptimizationDecision.primaryConstraint`: `receivePath`
- `streamShapeOptimizationDecision.recommendedNextProbe`:
  `inspectServerTransportCadence`
- failed gates: 8 of 8

Transport/cadence diagnosis:

- `recommendedTransportMode`: `request-response`
- `recommendedNextAction`: `inspectContinuousUpdatesConnection`
- ContinuousUpdates status: `failed-before-samples`
- ContinuousUpdates blocked gates: 4 of 4
- ContinuousUpdates failure label:
  `stream-continuous-updates-continuous-updates-not-confirmed`
- request/response status: `below-target`
- request/response blocked gates: 4 of 4

Request/response profile signal:

- strongest order-neutral request/response candidate label:
  `zrle-compression-0`
- renderer full-upload pressure was not the primary blocker
- request/response still did not satisfy the sustained v2 gate

## Interpretation

This is not benchmark-green and does not authorize a production default change.
The next larger implementation unit should inspect why the local Screen
Sharing-style target does not confirm ContinuousUpdates and should preserve
request/response as the usable fallback while that path is investigated.

After the ContinuousUpdates boundary is understood, the next candidate
comparison should stay inside request/response labels first, with
`zrle-compression-0` as the strongest current signal, and should rerun the same
gate before any physical iPhone promotion.

## Verification

- Built `VNCLiveStimulusWindow`.
- Ran live environment preflight with fixed setup labels.
- Ran `VNCLiveBenchmark --stream-shape-gate-preset sustained-v2-core
  --ask-password --json` against the redacted local VNC target.

## Safe Reporting

This artifact records only fixed target names, fixed status labels, fixed
issue/action labels, aggregate gate counts, and fixed profile/transport labels.
It does not store host identity, credentials, port values, raw TCP/RFB errors,
framebuffer dimensions, coordinates, pixels, cursor pixels, byte counts, raw
payloads, raw FPS, raw timings, stimulus command text, command output, draft
text, marked text, IME state, or full diagnostic payloads.
