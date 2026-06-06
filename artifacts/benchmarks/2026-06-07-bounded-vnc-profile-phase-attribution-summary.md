# Bounded VNC Profile Phase Attribution Summary - 2026-06-07

## Goal

Improve the launchctl-backed `bounded-vnc-profile-sweep` runner so a guarded
failure tells us which fixed runner phase was active when the bounded check
stopped. This keeps live tuning actionable without printing host identity,
credentials, command output, raw TCP/RFB errors, coordinates, dimensions,
pixels, byte counts, stimulus text, or screenshots.

## Change

The runner now builds `VNCLiveBenchmark` in a separate guarded `swift-build`
phase, resolves the built executable locally, then runs the bounded candidate
sweep in a separate `benchmark-running` phase. If either step fails or times
out, the fixed failure JSON includes `lastPhaseLabel`.

After review, executable resolution uses SwiftPM's `--show-bin-path` and then
falls back to local debug-product paths without printing those paths.

Allowed labels:

- `runner-starting`
- `swift-build`
- `benchmark-running`
- `unknown`

Success output remains the benchmark's own JSON report.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh

scripts/run-naru-live-benchmark.sh bounded-vnc-profile-sweep \
  -- --definitely-invalid-option \
  | jq -e '.mode == "bounded-vnc-profile-sweep"
    and .status == "failed"
    and .safeFailureCode == "benchmarkStep.boundedVNCProfileSweep.failed"
    and .lastPhaseLabel == "benchmark-running"'

scripts/run-naru-live-benchmark.sh bounded-vnc-profile-sweep \
  | jq -c '{schemaVersion, mode, status, safeFailureCode, lastPhaseLabel}'
```

Live safe-field result:

```json
{"schemaVersion":1,"mode":"bounded-vnc-profile-sweep","status":"failed","safeFailureCode":"benchmarkStep.boundedVNCProfileSweep.timedOut","lastPhaseLabel":"benchmark-running"}
```

## Interpretation

The current live target is no longer stuck in SwiftPM setup for this bounded
runner. The latest guarded failure reaches benchmark execution and then exceeds
the wall-clock guard, so the next useful optimization work should instrument
or reduce benchmark runtime inside the VNC stream path rather than spend more
time on runner startup.
