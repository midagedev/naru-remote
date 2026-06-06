# Bounded VNC Profile Drilldown Summary - 2026-06-07

## Goal

After `bounded-vnc-profile-sweep` showed a guarded timeout in the
`benchmark-running` phase, split the fixed candidate set into per-profile
guarded runs. The intent is to distinguish a single bad encoding candidate from
a broader VNC benchmark/runtime bottleneck while continuing to keep host,
credential, port, path, command output, raw errors, dimensions, coordinates,
pixels, and byte counts out of logs.

## Change

Added `scripts/run-naru-live-benchmark.sh bounded-vnc-profile-drilldown`.
The mode:

- imports live credentials only from the current shell or `launchctl`;
- builds `VNCLiveBenchmark` once in `swift-build`;
- runs `tight-first`, `zrle-compression-0`, and `adaptive-good-full` as
  separate `benchmark-running` profile entries;
- uses a 20 second wall-clock guard per profile;
- emits catalog-only `profileLabel`, `profileOrdinal`, `safeFailureCode`, and
  `lastPhaseLabel` on failures;
- passes successful benchmark JSON through under a per-profile `report` field.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh

scripts/run-naru-live-benchmark.sh --help \
  | rg "bounded-vnc-profile-drilldown"

scripts/run-naru-live-benchmark.sh bounded-vnc-profile-drilldown \
  -- --stream-shape-profiles tight-first \
  >/tmp/naru-drilldown-guard.out \
  2>/tmp/naru-drilldown-guard.err
exit_code=$?
test "$exit_code" -eq 2
rg "manages --stream-shape-profiles internally" /tmp/naru-drilldown-guard.err

scripts/run-naru-live-benchmark.sh bounded-vnc-profile-drilldown \
  -- --definitely-invalid-option \
  | jq -e '.mode == "bounded-vnc-profile-drilldown"
    and .status == "completed"
    and (.profiles | length == 3)
    and all(.profiles[];
      .mode == "bounded-vnc-profile-drilldown-profile"
      and .status == "failed"
      and .safeFailureCode == "benchmarkStep.boundedVNCProfileDrilldown.failed"
      and .lastPhaseLabel == "benchmark-running")'
```

Live safe-field result:

```json
{"mode":"bounded-vnc-profile-drilldown","status":"completed","profiles":[{"profileLabel":"tight-first","profileOrdinal":1,"status":"failed","safeFailureCode":"benchmarkStep.boundedVNCProfileDrilldown.timedOut","lastPhaseLabel":"benchmark-running","reportStatus":null,"reportVerdict":null},{"profileLabel":"zrle-compression-0","profileOrdinal":2,"status":"failed","safeFailureCode":"benchmarkStep.boundedVNCProfileDrilldown.timedOut","lastPhaseLabel":"benchmark-running","reportStatus":null,"reportVerdict":null},{"profileLabel":"adaptive-good-full","profileOrdinal":3,"status":"failed","safeFailureCode":"benchmarkStep.boundedVNCProfileDrilldown.timedOut","lastPhaseLabel":"benchmark-running","reportStatus":null,"reportVerdict":null}]}
```

## Interpretation

All three fixed VNC candidates time out even when isolated to one profile with a
20 second wall-clock guard. The evidence no longer points to one encoding
profile being uniquely slow. The next practical optimization step should make
the benchmark report safe subphase progress inside `benchmark-running` or add a
shorter stream-only probe that can tell whether timeout is dominated by TCP/RFB
connect, security/auth, first framebuffer update, idle probe, or stream-shape
sample collection.

## Follow-Up Correction

See
`artifacts/benchmarks/2026-06-07-bounded-vnc-subphase-progress-summary.md`.
The all-timeout result above was collected before discovering that
`--stream-shape-gate-preset sustained-v2-core` reapplied its own profile
selection after CLI parsing. After removing that preset override, the bounded
drilldown runs the intended fixed candidates and completes.
