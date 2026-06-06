# Helper Video Live Readiness Benchmark Summary

Date: 2026-06-06

## Scope

This run verifies the live benchmark path after adding the explicit
Screen Recording permission request CLI. It uses environment-sourced live VNC
credentials, checks the external helper-video process probes, and records a
short constrained-cellular VNC comparison so the next optimization unit can be
chosen from current evidence.

No host names, passwords, ports, endpoints, frame content, framebuffer
dimensions, byte counts, raw OS errors, stimulus command text, or stimulus
output are recorded here.

## Commands

```bash
NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark --environment-preflight --json
```

```bash
swift build --product NaruHelper

NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --continuous-update-samples 0 \
  --stream-shape-samples 0 \
  --visual-transport helper-video \
  --helper-video-probe external-helper-synthetic-encoded-tcp \
  --json
```

```bash
swift build --product NaruHelper

NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --continuous-update-samples 0 \
  --stream-shape-samples 0 \
  --visual-transport helper-video \
  --helper-video-probe external-helper-screen-capturekit-tcp \
  --json
```

```bash
NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic \
  --visual-transport vnc,helper-video \
  --helper-video-probe external-helper-synthetic-encoded-tcp \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --continuous-update-samples 0 \
  --stream-shape-samples 2 \
  --stream-shape-duration-seconds 3 \
  --json
```

## Results

- Environment preflight: runnable with `credentialStatus=environment` and no
  issue codes.
- `NaruHelper --video-capability`: current process context reports
  `permissionMissing`.
- `NaruHelper --video-request-screen-recording-permission`: current process
  context reports `notGranted`.
- External helper synthetic H.264 probe: `pass`, `healthy`, `fast`, and
  `smooth`.
- External helper ScreenCaptureKit probe: `fail` with
  `helper-video-permission-missing`, `helper-video-stream-unhealthy`,
  `helper-video-startup-failed`, `helper-video-sustained-stalled`, and
  `helper-video-fallback-observed`.
- Short constrained-cellular VNC run: report schema `67`, preset
  `sustained-v2-constrained-cellular-app-low-traffic`, visual transports
  `vnc` and `helper-video`, network condition `constrained-cellular`.
- VNC overall verdict: `fail`.
- Primary VNC issue: `first-frame-payload-read-failed`.
- Primary VNC constraint: `receivePath`.
- Best VNC app-low-traffic candidate in this short run:
  `zrle-compression-0-rgb565`.
- Best candidate aggregate: about `1.91` content FPS, about `524 ms` average
  update latency, and about `629 ms` p95 update latency.
- First useful VNC frame was about `9.3 s`; most first-frame receive time was
  payload-read time, while sustained updates were dominated by first-byte wait.
- Request cadence health: high content hit, p95 warning, recommended next probe
  `inspectUpdateWaitTiming`.
- Transport cadence diagnosis: request/response below target, recommended next
  action `tuneTransportCadence`.
- Helper-video comparison in the VNC run used the external synthetic encoded
  process path and reported `pass`; this is still not live ScreenCaptureKit
  frame capture.

## Interpretation

The live credential path is correctly configured and can be reused for ongoing
benchmark work. The current blocker for true helper-video capture is macOS
Screen Recording permission in the helper process context, not pairing,
credential, or external helper process launch.

The VNC path remains useful as a fallback, but the short constrained-cellular
run confirms it is still below the product target. Startup is dominated by
first-frame payload read even with the visible-glance first-frame request, and
sustained interaction is dominated by first-byte wait rather than client
decode/render cost. That keeps the next large unit pointed at live helper-video
capture/decode evidence instead of another small renderer-side VNC tweak.

## Next Work

- Grant or otherwise complete Screen Recording permission for the helper
  process context, then rerun `external-helper-screen-capturekit-tcp`.
- Once the permission gate opens, run a true helper-video live capture benchmark
  against the same constrained-cellular target.
- Keep VNC fallback tuning focused on receive-path cadence and first-frame
  startup weight; do not promote VNC defaults from this failing gate.
