# Launchctl Glance Scale Sweep Runner Summary - 2026-06-07

## Scope

Add `scripts/run-naru-live-benchmark.sh glance-scale-sweep`, a fixed
launchctl-backed candidate sweep for the benchmark-only first-frame
visible-glance scales `0.45`, `0.35`, and `0.25`.

The mode imports live VNC/helper values from environment/`launchctl`, rejects
extra arguments, builds `VNCLiveBenchmark` once, and runs all three candidates
under the same short constrained-cellular app-low-traffic shape with external
synthetic helper-video comparison.

No host names, passwords, ports, helper executable paths, endpoints, command
lines, raw stdout/stderr, raw TCP/RFB errors, frame content, framebuffer
dimensions, coordinates, pixels, byte counts, stimulus command text, draft
text, marked text, IME state, or exact helper timings are recorded here.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help
scripts/run-naru-live-benchmark.sh glance-scale-sweep -- --stream-shape-samples 1
scripts/run-naru-live-benchmark.sh glance-scale-sweep
```

The extra-argument check rejects overrides so the sweep remains repeatable.

## Current Live Result

All three scale samples completed.

| Scale permille | Overall decision | Primary issue | Primary constraint | Helper synthetic | `local-low-latency-rgb565` | `zrle-compression-0-rgb565` | First-frame request area |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 450 | `fail` | `first-frame-payload-read-failed` | `receivePath` | `pass` | `fail` | `fail` | `61` permille |
| 350 | `fail` | `first-frame-payload-read-failed` | `receivePath` | `pass` | `fail` | `fail` | `37` permille |
| 250 | `fail` | `first-frame-payload-read-failed` | `receivePath` | `pass` | `warning` | `fail` | `19` permille |

For all three samples, the app-low-traffic profile gates reported
`1000/1000/1000` received/content/content-response sample permille.

## Interpretation

`0.25` remains the best poor-network startup traffic candidate because it
shrinks first-frame request area to `19` permille and improves
`local-low-latency-rgb565` from failure to warning. It is still not a production
default: `zrle-compression-0-rgb565` remains failed, the overall primary
constraint remains the receive path, and the physical iPhone gate still needs
to verify readability, zoom/pan hand-feel, Compose input, thermal behavior, and
fallback smoothness.
