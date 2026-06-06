# Launchctl Request Pipeline Sweep Summary - 2026-06-07

## Goal

Make the existing benchmark-only request/response pipeline-depth experiment
repeatable from the launchctl-backed live runner, using the same redaction rules
as other live benchmark entry points.

## Runner Change

`scripts/run-naru-live-benchmark.sh request-pipeline-sweep` now imports the live
target and credential from `launchctl`, then runs the constrained-cellular
app-low-traffic VNC shape at request pipeline depths `1`, `2`, and `3`.

The mode owns `--stream-shape-request-pipeline-depth` internally and rejects
that flag in extra arguments so each report remains an actual depth sweep.

## Live Result

Safe reduced summary from the first runner pass:

| Depth | Transport status | Sample status | Latency status | Content FPS | Avg update ms | Max p95 update ms | Max first-byte p95 ms | Max payload p95 ms |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | below-target | high-content-hit | p95-failed | 1.48 | 547 | 1055 | 616 | 449 |
| 2 | below-target | high-content-hit | p95-warning | 1.62 | 561 | 978 | 619 | 445 |
| 3 | below-target | high-content-hit | p95-failed | 1.97 | 570 | 1014 | 584 | 445 |

## Interpretation

- No tested depth clears the poor-network target.
- Increasing outstanding request depth does not remove the receive tail in this
  constrained-cellular shape.
- Depth `3` improved short-run content FPS versus this run's depth `1`, but it
  still kept a failed p95 tail and higher average update latency.
- Request pipelining should remain benchmark-only. It is not ready for a
  production app default or low-traffic profile promotion.

## Verification

- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh --help`
- `scripts/run-naru-live-benchmark.sh request-pipeline-sweep -- --stream-shape-request-pipeline-depth 2`
  - Result: rejected with the fixed internal-flag guard.
- `scripts/run-naru-live-benchmark.sh request-pipeline-sweep | jq ...`
  - Result: valid JSON array with depth `1`, `2`, and `3` reports.

No hostnames, passwords, helper executable paths, endpoints, frame payloads,
byte counts, dimensions, coordinates, cursor pixels, raw OS errors, stimulus
commands, or framebuffer pixels are stored in this artifact.
