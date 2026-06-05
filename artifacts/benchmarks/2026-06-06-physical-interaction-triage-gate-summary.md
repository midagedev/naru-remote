# Physical Interaction Triage Gate — 2026-06-06

## Goal

Make physical iPhone reports actionable before the next streaming-default
change. The current practical target already requires sustained v2 benchmark
gates plus a physical iPhone hand-feel/thermal pass; this increment makes the
app diagnostic JSON choose the next large work unit from the same safe signals.

## Diagnostic Surface

Diagnostic collection schema v29 extends `sustainedSessionAssessment` with:

- `primaryIssueCode`: the highest-priority fixed issue code, omitted when the
  measured session passes.
- `primaryConstraint`: a fixed group label such as `thermal`,
  `viewportInteraction`, `clientDecode`, `rendererUpload`, `contentCadence`, or
  `composeInput`.
- `recommendedNextProbe`: a fixed next-step label such as
  `runPowerSaverThermalPass`, `runViewportInteractionTrace`,
  `compareEncodingProfileGate`, or `inspectComposeRoute`.
- `physicalGateVerdict`: `pass` only when no sustained-session issue code is
  present; otherwise `blocked`, even when the detailed assessment `verdict` is
  only `warning`.

The priority order favors real-device hand-feel and heat: thermal pressure is
first, viewport interaction pressure is next, then local decode/apply/render
pressure, stream cadence, adaptive pacing, Compose input, and sample-size
problems. The `physicalGateVerdict` is intentionally stricter than the detailed
assessment verdict because the promotion ladder requires a fully green 10 minute
physical iPhone run before changing production transport, encoding, pacing, or
interaction defaults.

## Safety

The triage fields are derived only from existing fixed issue-code labels. They
do not export raw FPS, raw timings, host identity, dimensions, coordinates,
pixels, cursor pixels, byte counts, raw payloads, draft text, marked text, IME
state, device identifiers, or credential material.

## Verification

- `swift test --filter DiagnosticExportTests`
- Full package and iPhone simulator build should remain the merge gate for this
  PR before folding into `main`.
