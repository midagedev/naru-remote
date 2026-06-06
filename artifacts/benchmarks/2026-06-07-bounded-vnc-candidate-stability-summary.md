# Bounded VNC Candidate Stability Summary - 2026-06-07

## Goal

After the corrected bounded profile sweep completed, measure the two non-failing
warning candidates across repeated order-rotated runs. A single one-sample run
can be noisy, so this runner checks whether either `tight-first` or
`adaptive-good-full` is stable enough to promote toward the sustained iPhone
session path.

## Change

Added `scripts/run-naru-live-benchmark.sh bounded-vnc-candidate-stability`.
The mode:

- imports live host/password only from the current shell or `launchctl`;
- builds `VNCLiveBenchmark` once;
- compares `tight-first` and `adaptive-good-full`;
- runs 3 order-rotated iterations;
- uses 2 stream-shape samples per profile run;
- keeps the same bounded sustained-v2-compatible request/response shape;
- rejects caller overrides for managed benchmark dimensions, including
  `--network-condition`, `--stream-shape-gate-preset`,
  `--stream-shape-profiles`, `--visual-transport`, and
  `--safe-progress-label-file`;
- rejects compatibility/help overrides that would change the fixed evidence
  surface, including `--stream-shape-viewport-interaction-pause-seconds`,
  `--help`, and `-h`;
- emits mode-specific fixed timeout/failure JSON if the wall-clock guard fires.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh

scripts/run-naru-live-benchmark.sh --help \
  | rg "bounded-vnc-candidate-stability"

scripts/run-naru-live-benchmark.sh bounded-vnc-candidate-stability \
  -- --stream-shape-profiles tight-first

scripts/run-naru-live-benchmark.sh bounded-vnc-candidate-stability \
  -- --definitely-invalid-option \
  | jq -e '.mode == "bounded-vnc-candidate-stability"
    and .status == "failed"
    and .safeFailureCode == "benchmarkStep.boundedVNCCandidateStability.failed"
    and .lastPhaseLabel == "benchmark-running"'
```

Live safe-field result:

```json
{"schemaVersion":67,"streamShapeProfiles":"tight-first,adaptive-good-full","streamShapeProfileIterations":3,"streamShapeProfileOrderMode":"rotate","streamShapeOptimizationDecision":{"blockedGateCount":2,"disabledGateCount":0,"failGateCount":2,"failureLabelCounts":[],"gateCount":2,"passGateCount":0,"primaryConstraint":"clientDecode","primaryConstraintCounts":[{"count":2,"label":"sampleSize"},{"count":2,"label":"contentCadence"},{"count":2,"label":"clientDecode"}],"primaryIssueCode":"client-processing-failed","recommendedNextProbe":"compareEncodingProfileGate","recommendedNextProbeCounts":[{"count":2,"label":"collectLongerPhysicalRun"},{"count":2,"label":"runSustainedV2ProfileGate"},{"count":2,"label":"compareEncodingProfileGate"}],"targetName":"iphone-sustained-usability-v2","verdict":"fail","warningGateCount":0},"streamShapeRecommendation":{"averageUpdateMilliseconds":19,"contentFramesPerSecond":25,"contentResponsePermille":1000,"contentSamplePermille":1000,"contentUpdateSamples":2,"label":"tight-first","p95UpdateMilliseconds":22,"pacingWindow":"single","reason":"lowest-average-update-latency-among-request-response-profiles","receivedSamples":2,"rendererFullUploadPermille":0,"requestRegion":"full","runCount":1,"slowUpdateSamples":0,"transportMode":"request-response","usableRunCount":1},"streamShapeOrderNeutralRecommendation":{"averageUpdateMilliseconds":43,"contentFramesPerSecond":14.132294300413852,"contentResponsePermille":833,"contentSamplePermille":833,"contentUpdateSamples":5,"label":"tight-first","p95UpdateMilliseconds":164,"pacingWindow":"single","reason":"lowest-average-update-latency-across-order-neutral-request-response-runs","receivedSamples":6,"rendererFullUploadPermille":0,"requestRegion":"full","runCount":3,"slowUpdateSamples":0,"transportMode":"request-response","usableRunCount":3},"profileGates":[{"label":"tight-first","verdict":"fail","passRunCount":0,"warningRunCount":2,"failRunCount":1,"issueCodes":["insufficient-content-samples","client-processing-failed"],"primaryIssueCode":"client-processing-failed","primaryConstraint":"clientDecode","recommendedNextProbe":"compareEncodingProfileGate","averageReceivedSamplePermille":1000,"averageContentSamplePermille":833,"averageContentResponsePermille":833},{"label":"adaptive-good-full","verdict":"fail","passRunCount":0,"warningRunCount":1,"failRunCount":2,"issueCodes":["insufficient-content-samples","content-fps-warning","content-fps-failed","average-update-warning","average-update-failed","p95-update-warning","p95-update-failed","client-processing-failed"],"primaryIssueCode":"client-processing-failed","primaryConstraint":"clientDecode","recommendedNextProbe":"compareEncodingProfileGate","averageReceivedSamplePermille":1000,"averageContentSamplePermille":833,"averageContentResponsePermille":833}],"profileProbes":[{"label":"tight-first","iterationOrdinal":1,"orderOrdinal":1,"status":"content-update","verdict":"fail","issueCodes":["insufficient-content-samples","client-processing-failed"],"contentFPS":9.132420091324201,"firstFrameMS":2706},{"label":"adaptive-good-full","iterationOrdinal":1,"orderOrdinal":2,"status":"content-update","verdict":"fail","issueCodes":["insufficient-content-samples","content-fps-failed","average-update-failed","p95-update-failed","client-processing-failed"],"contentFPS":2.557544757033248,"firstFrameMS":3185},{"label":"adaptive-good-full","iterationOrdinal":2,"orderOrdinal":1,"status":"content-update","verdict":"warning","issueCodes":["insufficient-content-samples","content-fps-warning"],"contentFPS":7.462686567164178,"firstFrameMS":3160},{"label":"tight-first","iterationOrdinal":2,"orderOrdinal":2,"status":"mixed-updates","verdict":"warning","issueCodes":["insufficient-content-samples"],"contentFPS":8.264462809917356,"firstFrameMS":2699},{"label":"tight-first","iterationOrdinal":3,"orderOrdinal":1,"status":"content-update","verdict":"warning","issueCodes":["insufficient-content-samples"],"contentFPS":25,"firstFrameMS":2692},{"label":"adaptive-good-full","iterationOrdinal":3,"orderOrdinal":2,"status":"mixed-updates","verdict":"fail","issueCodes":["insufficient-content-samples","content-fps-failed","average-update-warning","p95-update-warning"],"contentFPS":1.76678445229682,"firstFrameMS":3180}]}
```

## Interpretation

Neither candidate is ready for promotion. `tight-first` is the better current
candidate because it has the order-neutral recommendation, two warnings, one
fail, and a higher content cadence than `adaptive-good-full`; however it still
has zero pass runs and a `clientDecode` primary constraint. `adaptive-good-full`
is less stable in this run and fails two of three iterations.

The next practical optimization step should keep `tight-first` as the working
candidate and reduce the `clientDecode` / content cadence pressure before
changing production defaults.
