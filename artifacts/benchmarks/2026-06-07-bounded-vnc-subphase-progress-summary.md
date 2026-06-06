# Bounded VNC Subphase Progress Summary - 2026-06-07

## Goal

When `bounded-vnc-profile-drilldown` timed out inside `benchmark-running`, add a
privacy-safe progress hook from `VNCLiveBenchmark` back to the launchctl runner
so timeout JSON can report the last benchmark subphase without printing host,
credential, port, executable path, command output, raw errors, dimensions,
coordinates, pixels, or byte counts.

## Change

`VNCLiveBenchmark` now accepts `--safe-progress-label-file PATH`. During normal
benchmark execution it writes only fixed subphase labels and safe catalog
profile labels to that file. The launchctl runner owns a temp file and reads it
only when a bounded VNC profile sweep/drilldown fails or times out.

Safe subphase labels:

- `benchmark-starting`
- `configuration-loaded`
- `first-frame-profiles`
- `idle-probe`
- `stream-shape-profile`
- `continuous-updates-probe`
- `visual-transport-comparison`
- `report-rendering`
- `benchmark-complete`

While validating the new progress hook, the live progress file showed
`profileLabel=local-low-latency` even though the runner had requested
`tight-first`. Root cause: the bounded runner passed
`--stream-shape-gate-preset sustained-v2-core`, and that preset reapplied its
own profile selection after CLI parsing. The bounded sweep/drilldown now spell
out the sustained-v2-compatible options directly and reject caller overrides for
those managed dimensions.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
swift build --product VNCLiveBenchmark
swift run --quiet VNCLiveBenchmark --help | rg "safe-progress-label-file"

tmp_progress="$(mktemp /tmp/naru-progress-smoke.XXXXXX)"
swift run --quiet VNCLiveBenchmark \
  --environment-preflight \
  --safe-progress-label-file "$tmp_progress" \
  --json >/dev/null
cat "$tmp_progress"
rm -f "$tmp_progress"

scripts/run-naru-live-benchmark.sh bounded-vnc-profile-drilldown \
  -- --stream-shape-gate-preset sustained-v2-core

scripts/run-naru-live-benchmark.sh bounded-vnc-profile-drilldown \
  -- --definitely-invalid-option \
  | jq -e '.mode == "bounded-vnc-profile-drilldown"
    and .status == "completed"
    and (.profiles | length == 3)
    and all(.profiles[];
      .status == "failed"
      and .safeFailureCode == "benchmarkStep.boundedVNCProfileDrilldown.failed"
      and .lastPhaseLabel == "benchmark-running"
      and (.lastBenchmarkSubphaseLabel? | not))'
```

Live drilldown after the preset override fix:

```json
{"mode":"bounded-vnc-profile-drilldown","status":"completed","profiles":[{"profileLabel":"tight-first","profileOrdinal":1,"status":"passed","safeFailureCode":null,"lastPhaseLabel":null,"lastBenchmarkSubphaseLabel":null,"lastBenchmarkProfileLabel":null,"reportStatus":"content-update","reportVerdict":"warning"},{"profileLabel":"zrle-compression-0","profileOrdinal":2,"status":"passed","safeFailureCode":null,"lastPhaseLabel":null,"lastBenchmarkSubphaseLabel":null,"lastBenchmarkProfileLabel":null,"reportStatus":"empty-update","reportVerdict":"fail"},{"profileLabel":"adaptive-good-full","profileOrdinal":3,"status":"passed","safeFailureCode":null,"lastPhaseLabel":null,"lastBenchmarkSubphaseLabel":null,"lastBenchmarkProfileLabel":null,"reportStatus":"content-update","reportVerdict":"warning"}]}
```

Live all-profile bounded sweep after the preset override fix:

```json
{"schemaVersion":67,"streamShapeProfiles":"tight-first,zrle-compression-0,adaptive-good-full","streamShapeProfileIterations":1,"streamShapeTransportModes":"request-response","streamShapeProbeStatus":"content-update","streamShapeProbeVerdict":"warning","profiles":[{"label":"tight-first","status":"content-update","verdict":"warning"},{"label":"zrle-compression-0","status":"empty-update","verdict":"fail"},{"label":"adaptive-good-full","status":"content-update","verdict":"warning"}]}
```

## Interpretation

The previous all-timeout bounded drilldown was not valid profile-candidate
evidence because the runner's preset flag replaced the intended profile set.
After removing that preset override, the bounded VNC profile sweep completes.
`tight-first` and `adaptive-good-full` reach content updates with warning
verdicts; `zrle-compression-0` reaches only empty updates and fails the current
target. The next practical work should inspect the warning causes for
`tight-first` and `adaptive-good-full` and decide whether one can become the
next iPhone sustained-session candidate.
