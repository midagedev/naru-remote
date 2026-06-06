# Tight-First RGB565 Candidate Summary - 2026-06-07

## Goal

The previous bounded stability run kept `tight-first` as the best working
candidate but still reported `clientDecode` / content-cadence pressure. This
run adds a benchmark-only `tight-first-rgb565` profile to test whether keeping
the same Tight preference while requesting RGB565-in-32-bit pixels reduces that
pressure enough to justify further product work.

## Change

Added a `VNCLiveBenchmark` profile label:

- `tight-first-rgb565`
- same Tight preference as `tight-first`
- `RFBPixelFormat.rgb565In32LittleEndian`

The bounded candidate-stability runner now compares:

- `tight-first`
- `tight-first-rgb565`
- `adaptive-good-full`

It still builds `VNCLiveBenchmark` once, imports live host/password only from
the current shell or `launchctl`, uses three order-rotated iterations, keeps two
stream-shape samples per profile run, rejects caller overrides for managed
benchmark dimensions, and emits only privacy-safe benchmark JSON or fixed
runner failure labels.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help | rg "bounded-vnc-candidate-stability"
swift test --filter BenchmarkStreamShapeProfileSelectionTests
swift test --filter BenchmarkStreamShapeSummaryTests
scripts/run-naru-live-benchmark.sh bounded-vnc-candidate-stability
```

Live safe-field result:

```json
{"schemaVersion":67,"streamShapeProfiles":"tight-first,tight-first-rgb565,adaptive-good-full","streamShapeProfileIterations":3,"streamShapeProfileOrderMode":"rotate","streamShapeOptimizationDecision":{"verdict":"fail","passGateCount":0,"warningGateCount":1,"failGateCount":2,"primaryConstraint":"receivePath","primaryIssueCode":"average-update-failed","recommendedNextProbe":"inspectServerTransportCadence"},"streamShapeTransportCadenceDiagnosis":{"recommendedTransportMode":"request-response","requestResponseStatus":"below-target","recommendedNextAction":"tuneTransportCadence"},"streamShapeOrderNeutralRecommendation":{"label":"tight-first","averageUpdateMilliseconds":40,"p95UpdateMilliseconds":76,"contentFramesPerSecond":14.265770956891624,"contentResponsePermille":833,"rendererFullUploadPermille":0,"usableRunCount":3},"profileGates":[{"label":"tight-first","verdict":"warning","passRunCount":0,"warningRunCount":3,"failRunCount":0,"primaryConstraint":"contentCadence","primaryIssueCode":"content-fps-warning","averageContentResponsePermille":833},{"label":"tight-first-rgb565","verdict":"fail","passRunCount":0,"warningRunCount":2,"failRunCount":1,"primaryConstraint":"receivePath","primaryIssueCode":"average-update-failed","averageContentResponsePermille":833},{"label":"adaptive-good-full","verdict":"fail","passRunCount":0,"warningRunCount":2,"failRunCount":1,"primaryConstraint":"receivePath","primaryIssueCode":"average-update-failed","averageContentResponsePermille":667}],"profileAggregates":[{"label":"tight-first","averageContentFramesPerSecond":14.265770956891624,"averageUpdateMilliseconds":40,"maxP95UpdateMilliseconds":76,"maxClientProcessingP95Milliseconds":1,"averageClientProcessingSharePermille":17,"averageFirstByteWaitSharePermille":1000},{"label":"tight-first-rgb565","averageContentFramesPerSecond":13.194878976589889,"averageUpdateMilliseconds":107,"maxP95UpdateMilliseconds":473,"maxClientProcessingP95Milliseconds":12,"averageClientProcessingSharePermille":19,"averageFirstByteWaitSharePermille":995},{"label":"adaptive-good-full","averageContentFramesPerSecond":4.880438187867213,"averageUpdateMilliseconds":145,"maxP95UpdateMilliseconds":500,"maxClientProcessingP95Milliseconds":8,"averageClientProcessingSharePermille":21,"averageFirstByteWaitSharePermille":1000}]}
```

## Interpretation

Do not promote `tight-first-rgb565`. It did not reduce the sustained-session
gate enough and produced a worse update tail than full-color `tight-first`:

- `tight-first`: warning, 3 warning / 0 fail runs, 14.27 content FPS,
  40 ms average update, 76 ms max p95 update, 1 ms max client-processing p95.
- `tight-first-rgb565`: fail, 2 warning / 1 fail runs, 13.19 content FPS,
  107 ms average update, 473 ms max p95 update, 12 ms max
  client-processing p95.
- `adaptive-good-full`: fail, 2 warning / 1 fail runs, 4.88 content FPS,
  145 ms average update, 500 ms max p95 update.

The current best working VNC candidate remains `tight-first`, but this run
changes the next optimization target from pure pixel-format decode reduction to
request/response cadence and server first-byte wait. The transport cadence
diagnosis recommends `tuneTransportCadence`.

## Privacy

This artifact contains only benchmark schema labels, fixed profile labels,
aggregate verdicts, permille ratios, and aggregate timing values. It does not
include host identity, credentials, ports, executable paths, command lines, raw
stdout/stderr, TCP/RFB errors, request coordinates, dimensions, pixels, byte
counts, stimulus command text, draft text, marked text, or IME state.
