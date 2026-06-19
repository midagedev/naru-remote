# Simulator Input/Viewport Gate Baseline Summary

Date: 2026-06-15 KST

## Purpose

Record the current local simulator evidence after the helper-video runner fix
and physical iPad smoke recovery. This is a baseline, not a performance
promotion result.

## Command

```bash
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

## Safe Result

- `mode`: `simulator-input-viewport-gate`
- `status`: `passed`
- phone destination label: iPhone simulator
- pad destination label: iPad simulator
- device coverage labels: `iphone-simulator`, `ipad-simulator`
- benchmark iterations: `3`
- benchmark samples: `1000`
- all four substeps reported `passed`

## Interpretation

The current simulator gate does not reproduce the earlier first-character
Compose freeze or obvious viewport hot-path regression. This does not prove the
physical iPhone experience is smooth, and it does not change the VNC 10fps
readiness result. It only means the next performance work should focus on
live/physical visual transport evidence rather than assuming an immediate
simulator-only input regression.

The gate took noticeably long in this local run. Future work should prefer a
smaller targeted gate first when iterating on one axis, then run the full
`simulator-input-viewport-gate` before promoting changes.

## PR Policy

No PR should be created from this artifact alone. It records baseline evidence
only and does not show a clear FPS, latency, traffic, thermal, or input
responsiveness improvement.

## Safety

This artifact records only fixed status labels, command shape, and aggregate
counts. It does not include raw device identifiers, screenshots, hostnames,
credentials, endpoints, exact per-event timings, frame payloads, pixels,
dimensions, coordinates, composed text, clipboard contents, or byte counts.
