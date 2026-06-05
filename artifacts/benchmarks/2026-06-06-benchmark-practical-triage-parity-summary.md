# Benchmark Practical Triage Parity Summary

Target: `iphone-sustained-usability-v2`

Purpose: move sustained iPhone optimization work into larger units by making
live benchmark gates and physical-device diagnostics use the same triage
surface.

## Change

- `VNCLiveBenchmark` schema v40.
- Each stream-shape `practicalAssessment` now derives:
  - `primaryIssueCode`
  - `primaryConstraint`
  - `recommendedNextProbe`
- The labels reuse the diagnostic JSON v28 sustained-session catalogs so a
  benchmark artifact and a physical iPhone diagnostic export can both route the
  next PR toward the same broad unit.

## Large-Unit Routing

- `contentCadence` -> run the sustained v2 profile gate.
- `receivePath` -> inspect server or transport cadence.
- `clientDecode` -> compare encoding profile gates.
- `rendererUpload` -> inspect the local render pipeline.
- `adaptivePacing` -> compare adaptive pacing behavior.
- `sampleSize` -> collect a longer physical-device run.

## Privacy Boundary

The new fields are fixed labels derived from existing safe benchmark issue
codes. They do not add host identity, credentials, port value, TCP errors, RFB
errors, framebuffer dimensions, coordinates, pixels, cursor pixels, byte
counts, raw payloads, raw FPS, raw timings, draft text, marked text, or IME
state.

## Verification

- `BenchmarkStreamShapeSummaryTests` cover pass, content-cadence,
  receive-path, renderer-upload, legacy decode, and mismatched decoded triage
  field behavior.
- `VNCLiveBenchmark --help` text identifies schema v40 gate reporting.
