# Tight-First Cursor Candidate Summary - 2026-06-07

## Goal

The current best VNC benchmark candidate is `tight-first`, but the app's
trackpad mode needs server cursor support for a natural real-cursor path. This
run checks whether adding the RFB Cursor pseudo-encoding to the Tight candidate
keeps sustained-stream performance good enough to consider a later app opt-in.

## Change

Added two benchmark profile labels:

- `tight-first-cursor`
- `tight-first-cursor-clipboard`

Both use the same Tight preference as `tight-first`:

- Tight enabled
- Tight quality level 8
- compression level 1

`tight-first-cursor` additionally requests the Cursor pseudo-encoding.
`tight-first-cursor-clipboard` requests Cursor and ExtendedClipboard, but the
bounded runner intentionally compares only `tight-first` and
`tight-first-cursor` after a live check showed the clipboard variant increasing
client-processing pressure.

Added `scripts/run-naru-live-benchmark.sh bounded-vnc-tight-cursor-stability`.
The mode imports live host/password only from the current shell or `launchctl`,
builds `VNCLiveBenchmark` once, compares `tight-first` and
`tight-first-cursor`, runs three order-rotated iterations, keeps two
stream-shape samples per profile run, rejects caller overrides for managed
benchmark dimensions, and emits only privacy-safe benchmark JSON or fixed
runner failure labels.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help \
  | rg "bounded-vnc-tight-cursor-stability"
swift test --filter BenchmarkStreamShapeProfileSelectionTests
swift run --quiet VNCLiveBenchmark --help \
  | rg "tight-first-cursor|stream-shape-profiles"
scripts/run-naru-live-benchmark.sh bounded-vnc-tight-cursor-stability
```

Live safe-field result:

```json
{"schemaVersion":67,"streamShapeProfiles":"tight-first,tight-first-cursor","streamShapeProfileIterations":3,"streamShapeProfileOrderMode":"rotate","streamShapeOptimizationDecision":{"verdict":"warning","passGateCount":0,"warningGateCount":2,"failGateCount":0,"primaryConstraint":"sampleSize","primaryIssueCode":"insufficient-content-samples","recommendedNextProbe":"collectLongerPhysicalRun"},"streamShapeTransportCadenceDiagnosis":{"recommendedTransportMode":"request-response","requestResponseStatus":"below-target","recommendedNextAction":"tuneTransportCadence"},"streamShapeOrderNeutralRecommendation":{"label":"tight-first-cursor","averageUpdateMilliseconds":24,"p95UpdateMilliseconds":32,"contentFramesPerSecond":22.473632486469455,"contentResponsePermille":1000,"rendererFullUploadPermille":0,"usableRunCount":3},"profileGates":[{"label":"tight-first","verdict":"warning","passRunCount":0,"warningRunCount":3,"failRunCount":0,"primaryConstraint":"sampleSize","primaryIssueCode":"insufficient-content-samples","averageContentResponsePermille":1000},{"label":"tight-first-cursor","verdict":"warning","passRunCount":0,"warningRunCount":3,"failRunCount":0,"primaryConstraint":"sampleSize","primaryIssueCode":"insufficient-content-samples","averageContentResponsePermille":1000}],"profileAggregates":[{"label":"tight-first","averageContentFramesPerSecond":15.090308331587401,"averageUpdateMilliseconds":47,"maxP95UpdateMilliseconds":120,"maxClientProcessingP95Milliseconds":2,"averageFirstByteWaitSharePermille":1000,"averageRendererFullUploadPermille":0},{"label":"tight-first-cursor","averageContentFramesPerSecond":22.473632486469455,"averageUpdateMilliseconds":24,"maxP95UpdateMilliseconds":32,"maxClientProcessingP95Milliseconds":1,"averageFirstByteWaitSharePermille":1000,"averageRendererFullUploadPermille":0}]}
```

## Clipboard Variant Check

A live ad hoc comparison of `tight-first` vs `tight-first-cursor-clipboard`
showed the clipboard variant should not be used as the next app candidate:

- `tight-first`: warning overall, 5/6 content samples, 11.40 content FPS,
  63 ms average update, 206 ms max p95 update, 4 ms client-processing p95.
- `tight-first-cursor-clipboard`: fail overall, 3/4 content samples,
  9.13 content FPS, 71 ms average update, 172 ms max p95 update, 146 ms
  client-processing p95.

## Interpretation

`tight-first-cursor` is the best current VNC benchmark candidate for a future
trackpad-friendly app opt-in. It preserves server cursor support, keeps 0
permille renderer full-upload pressure, and beats plain `tight-first` in this
bounded runner. It still does not pass the sustained target because the runner
uses only two samples per profile run, so the next step is a longer physical or
bounded sustained run before any default promotion.

Do not include ExtendedClipboard in the Tight app candidate yet; the current
live result points at client-processing pressure.

## Privacy

This artifact contains only benchmark schema labels, fixed profile labels,
aggregate verdicts, permille ratios, and aggregate timing values. It does not
include host identity, credentials, ports, executable paths, command lines, raw
stdout/stderr, TCP/RFB errors, request coordinates, dimensions, pixels, byte
counts, stimulus command text, draft text, marked text, or IME state.
