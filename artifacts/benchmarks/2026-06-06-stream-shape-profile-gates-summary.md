# Stream Shape Profile Gates Summary - 2026-06-06

Target: `iphone-sustained-usability-v2`

Scope:
- `VNCLiveBenchmark` schema v37.
- Top-level `streamShapeProfileGates` summaries for larger multi-profile,
  multi-iteration sustained-stream runs.
- Safe profile/transport gate output before changing production request cadence,
  encoding defaults, startup preflight defaults, or viewport-interaction stream
  policy.

Safe changes:
- Added `BenchmarkStreamShapeProfileGateReport` to summarize each
  profile/transport pair.
- Each gate reports:
  - `targetName`
  - `verdict`
  - `runCount`
  - `passRunCount`
  - `warningRunCount`
  - `failRunCount`
  - `disabledRunCount`
  - `issueCodes`
  - aggregate hit-rate permille means
- Updated CLI text output so profile gates appear beside profile aggregates and
  recommendations.

Interpretation:
- Treat profile gates as the first decision screen for larger benchmark units.
- A `fail` gate means the profile should not become a production default until
  the fixed issue-code union is resolved.
- A `pass` gate only graduates a candidate to physical iPhone hand-feel and
  thermal verification; it is not sufficient by itself for a production default
  change.
- A `warning` gate needs an explicit product judgment in the benchmark artifact
  before it can be used as a candidate.
- Hit-rate means help decide whether the gate failed because requests went
  unanswered, the server mostly returned empty updates, or content-bearing
  updates were too slow.

Verification target:
- `swift test --filter BenchmarkStreamShapeSummaryTests`
- `swift build --product VNCLiveBenchmark`
- `git diff --check`
- `swift test`
- iPhone simulator app build before PR merge.

Live benchmark status:
- Not run in this increment. The output schema is intended to make the next
  redacted physical iPhone or localhost run easier to judge without manually
  scanning every probe.

Privacy:
- This artifact records only fixed field names, fixed target names, fixed
  verdicts, fixed issue-code names, aggregate run counts, aggregate permille
  ratios, and verification command names. It contains no host identity,
  credentials, framebuffer dimensions, coordinates, pixels, cursor pixels, byte
  counts, raw FPS, raw timings, raw samples, raw payloads, raw errors, external
  command text, command output, draft text, marked text, or IME state.
