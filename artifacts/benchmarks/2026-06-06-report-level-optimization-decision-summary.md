# Report-Level Optimization Decision Summary

Target: `iphone-sustained-usability-v2`

Purpose: make one sustained benchmark report choose the next large
optimization unit instead of requiring manual inspection across every
profile/transport run.

## Change

- `VNCLiveBenchmark` schema v41.
- `streamShapeProfileGates` now include:
  - `primaryIssueCode`
  - `primaryConstraint`
  - `recommendedNextProbe`
  - `primaryConstraintCounts`
  - `recommendedNextProbeCounts`
- Reports now include top-level `streamShapeOptimizationDecision` with fixed
  gate counts, fixed triage label counts, and one primary next-probe route.

## Decision Order

1. Read `streamShapeOptimizationDecision.primaryConstraint`.
2. Use `streamShapeOptimizationDecision.recommendedNextProbe` to select the
   next large PR unit.
3. Use `streamShapeRecommendation` only after the blocking constraint is known
   to be profile/cadence related or after local decode/render constraints are
   addressed.

## Privacy Boundary

The decision fields are fixed labels and aggregate counts only. They do not
add host identity, credentials, port value, TCP errors, RFB errors,
framebuffer dimensions, coordinates, pixels, cursor pixels, byte counts, raw
payloads, raw FPS, raw timings, draft text, marked text, or IME state.

## Verification

- `BenchmarkStreamShapeSummaryTests` cover gate-level triage aggregation and
  report-level optimization decision routing.
- `VNCLiveBenchmark --help` text identifies schema v41 gate reporting.
