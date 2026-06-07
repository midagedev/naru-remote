# Remote Desktop 10fps CLI Preset

## Change

Added `VNCLiveBenchmark --stream-shape-gate-preset remote-desktop-10fps`.
The preset reproduces the fixed VNC gate used by
`scripts/run-naru-live-benchmark.sh glance-025-10fps-duration-probe`:

- constrained-cellular network conditioning
- request/response transport only
- `viewport-phone-portrait` request region
- `visible-glance` first-frame request
- `0.25` visible-glance scale
- `local-low-latency-rgb565` profile
- one fixed-order iteration
- 12 second duration-only stream-shape run
- `iphone-remote-desktop-10fps-v1` practical target

## Verification

```bash
swift test --filter BenchmarkStreamShapeGatePresetTests
swift run VNCLiveBenchmark --help | rg "remote-desktop-10fps|stream-shape-gate-preset"
swift run VNCLiveBenchmark --environment-preflight --stream-shape-gate-preset remote-desktop-10fps --json
swift test
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
swift run VNCLiveBenchmark --stream-shape-gate-preset remote-desktop-10fps --json
```

Results:

- Focused gate-preset tests passed.
- `VNCLiveBenchmark --help` lists `remote-desktop-10fps`.
- Direct preflight parsed the preset and reported the expected external
  stimulus requirement when live environment values were not imported into the
  child process.
- Full `swift test` passed: 1165 tests, 13 skipped, 0 failures.
- Live readiness completed. Helper-video synthetic remained `pass`; true
  ScreenCaptureKit helper-video still failed with fixed
  `helper-video-permission-missing` labels.
- Live VNC 10fps readiness stayed below target: `1.738` content FPS,
  `575` ms average update, `1045` ms p95 update, primary constraint
  `receivePath`, and decision `fail`.
- A direct live preset run emitted `streamShapeGatePreset:
  remote-desktop-10fps`, confirming the preset label reaches the report. That
  run failed before usable stream samples with fixed label
  `stream-incremental-not-connected`, so it is parser/report-shape evidence,
  not VNC smoothness evidence.

## Interpretation

The 10fps product bar is now available both through the launchctl wrapper and
as a first-class CLI preset. Current live VNC evidence still does not meet the
10fps target, so VNC remains a control/input/fallback path until a future
encoding/cadence change proves a step-change. Helper-video remains the primary
smoothness candidate once Screen Recording permission and physical iPhone gates
are clear.

## Privacy

This artifact records only fixed labels and aggregate benchmark values. It does
not include host identity, credentials, ports, helper paths, command text,
framebuffer dimensions, coordinates, pixels, byte counts, or raw OS/TCP/RFB
errors.
