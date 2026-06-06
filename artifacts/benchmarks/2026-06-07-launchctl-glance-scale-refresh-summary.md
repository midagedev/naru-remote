# Launchctl Glance Scale Refresh Summary

Date: 2026-06-07

## Scope

This run refreshes the constrained-cellular app-low-traffic startup glance
scale evidence using the launchctl-backed live benchmark runner. It compares
the existing benchmark-only `visible-glance` override at `0.35` and `0.25`
while true ScreenCaptureKit helper-video remains blocked by macOS Screen
Recording permission.

No host names, passwords, ports, helper executable paths, endpoints, frame
content, framebuffer dimensions, byte counts, raw OS errors, stimulus command
text, or exact helper timings are recorded here.

## Commands

```bash
scripts/run-naru-live-benchmark.sh short-live-comparison -- \
  --stream-shape-first-frame-visible-glance-scale 0.35

scripts/run-naru-live-benchmark.sh short-live-comparison -- \
  --stream-shape-first-frame-visible-glance-scale 0.25
```

Both commands use the same short constrained-cellular app-low-traffic shape:
`networkCondition=constrained-cellular`, preset
`sustained-v2-constrained-cellular-app-low-traffic`, request region
`viewport-phone-portrait`, first-frame request mode `visible-glance`, and
external synthetic helper-video for the helper side.

## Results

### Scale 0.35

- Report schema: `67`.
- First-frame visible-glance scale: `350` permille.
- Overall decision: `fail`.
- Primary issue: `first-frame-payload-read-failed`.
- Primary constraint: `receivePath`.
- Recommended next probe: `compareEncodingProfileGate`.
- Transport cadence: request/response `below-target`, ContinuousUpdates
  `not-tested`, recommended next action `tuneTransportCadence`.
- `local-low-latency-rgb565`: `fail`,
  `first-frame-payload-read-failed`, first-frame request area `37` permille,
  received/content/content-response sample permille `1000/1000/1000`.
- `zrle-compression-0-rgb565`: `fail`,
  `first-frame-payload-read-failed`, first-frame request area `37` permille,
  received/content/content-response sample permille `1000/1000/1000`.
- Helper-video external synthetic side: `pass`, `healthy`, no issue codes.

### Scale 0.25

- Report schema: `67`.
- First-frame visible-glance scale: `250` permille.
- Overall decision: `fail` with one failing gate and one warning gate.
- Primary issue: `first-frame-payload-read-failed`.
- Primary constraint: `receivePath`.
- Recommended next probe: `compareEncodingProfileGate`.
- Transport cadence: request/response `below-target`, ContinuousUpdates
  `not-tested`, recommended next action `tuneTransportCadence`.
- `local-low-latency-rgb565`: `warning`,
  `first-frame-payload-read-warning`, first-frame request area `19` permille,
  received/content/content-response sample permille `1000/1000/1000`.
- `zrle-compression-0-rgb565`: `fail`,
  `first-frame-payload-read-failed`, first-frame request area `19` permille,
  received/content/content-response sample permille `1000/750/750`.
- Helper-video external synthetic side: `pass`, `healthy`, no issue codes.

## Interpretation

The refreshed live evidence again points toward `0.25` as the better poor
network startup candidate: it cuts the first-frame request area from `37` to
`19` permille and improves `local-low-latency-rgb565` from failure to warning.
It does not make the full app-low-traffic gate green because
`zrle-compression-0-rgb565` still fails and the overall primary constraint
remains the VNC receive path.

Do not promote `0.25` to a production default from this benchmark alone. The
existing sustained-usability contract requires a physical iPhone pass for
startup readability, zoom/pan hand-feel, Compose input, thermal behavior, and
fallback smoothness before changing defaults. Until then, keep `0.25` as a
benchmark/physical-gate candidate and keep helper-video ScreenCaptureKit setup
as the higher-leverage route for sustained traffic reduction.
