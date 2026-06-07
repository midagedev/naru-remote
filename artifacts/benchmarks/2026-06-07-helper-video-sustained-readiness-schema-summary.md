# Helper-Video Sustained Readiness Schema - 2026-06-07

## Goal

Make helper-video benchmark reports answer the product question directly:
after VNC is proven below the 10fps iPhone target, is the helper-video visual
path blocked by setup, transport, sustained cadence, decode pressure, or ready
for the next physical iPhone gate?

## Research Read

- RFB framebuffer updates are demand-driven by explicit client requests; the
  protocol intentionally adapts downward when the client or network is slow.
  This supports keeping VNC as control/input/fallback instead of treating more
  profile flips as the primary smoothness path.
- ScreenCaptureKit and VideoToolbox expose the capture/encode knobs that map to
  our helper-video path: capture frame interval, bounded queue depth, realtime
  compression, expected frame rate, keyframe interval, bitrate/rate limits, and
  hardware acceleration hints.

Primary sources:

- RFB protocol: https://raw.githubusercontent.com/rfbproto/rfbproto/master/rfbproto.rst
- Apple ScreenCaptureKit queue depth: https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth
- Apple VideoToolbox live streaming encoder settings: https://developer.apple.com/documentation/videotoolbox/encoding-video-for-live-streaming
- Apple VideoToolbox compression properties: https://developer.apple.com/documentation/videotoolbox/compression-properties

## Changes

- `BenchmarkHelperVideoReport` is now schema v2.
- Added fixed-catalog `readinessState`:
  - `disabled`
  - `permissionBlocked`
  - `transportBlocked`
  - `startupBlocked`
  - `sustainedDegraded`
  - `decodeBlocked`
  - `readyForTrueCaptureGate`
  - `readyForPhysicalGate`
- Added fixed-catalog `recommendedAction` so live dashboards can route directly
  to setup, transport inspection, sustained-cadence inspection, true capture
  benchmark, or physical iPhone gate.
- `remote-desktop-10fps-readiness` now treats sustained synthetic helper-video
  as a required gate between synthetic smoke and physical iPhone promotion.

## Live Evidence

- `scripts/run-naru-live-benchmark.sh helper-sustained-synthetic-probe`
  reported schema v2 helper-video `verdict=pass`,
  `readinessState=readyForPhysicalGate`, `recommendedAction=run-physical-iphone-helper-video-gate`,
  and empty issue codes.
- `scripts/run-naru-live-benchmark.sh helper-readiness-sweep` reported
  sustained synthetic helper-video pass, while true ScreenCaptureKit remained
  `permissionBlocked` with `grant-helper-video-app-screen-recording-permission`.
- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness` reported
  `blockedByHelperScreenCapture`; VNC still failed the 10fps product gate with
  about `1.56` content FPS, `537` ms average update, `917` ms p95 update,
  `626` ms first-byte wait p95, and receive-path dominance. This keeps VNC as
  the fallback/control path while true helper-video capture is the next
  smoothness gate.

## Verification

- `swift test --filter BenchmarkHelperVideoReportTests`
- `swift test --filter BenchmarkVisualTransportComparisonReportTests`
- `swift test --filter BenchmarkLiveEnvironmentPreflightTests`
- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh remote-desktop-readiness-summary-self-test | jq empty`
- `scripts/run-naru-live-benchmark.sh helper-sustained-synthetic-probe | jq ...`
- `scripts/run-naru-live-benchmark.sh helper-readiness-sweep | jq ...`
- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness | jq ...`

## Privacy Boundary

The schema adds only fixed labels. It does not emit endpoints, helper paths,
credentials, tokens, frame payloads, pixels, dimensions, byte counts, exact
per-frame timings, cursor coordinates, Compose text, marked text, or IME state.
