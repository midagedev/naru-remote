# Launchctl Live Benchmark Runner Summary

Date: 2026-06-07

## Scope

This run verifies `scripts/run-naru-live-benchmark.sh`, a local development
wrapper that imports live benchmark and helper values from `launchctl` without
printing those values. It keeps repeated live checks on the same safe command
shapes while the helper app bundle still waits for macOS Screen Recording
approval.

No host names, passwords, ports, helper executable paths, endpoints, frame
content, framebuffer dimensions, byte counts, raw OS errors, stimulus command
text, or exact helper timings are recorded here.

## Commands

```bash
scripts/run-naru-live-benchmark.sh --help
scripts/run-naru-live-benchmark.sh preflight
scripts/run-naru-live-benchmark.sh helper-capability
scripts/run-naru-live-benchmark.sh request-screen-recording
scripts/run-naru-live-benchmark.sh helper-synthetic-probe
scripts/run-naru-live-benchmark.sh helper-screen-probe
scripts/run-naru-live-benchmark.sh short-live-comparison
```

## Results

- Wrapper help path: exits successfully and documents the fixed modes.
- Preflight: schema `6`, `canRunLiveBenchmark=false`,
  `hostStatus=configured`, `portStatus=configured`,
  `credentialStatus=environment`.
- Preflight helper state: `helperVideoScreenCapturePermissionStatus=missing`,
  external helper capability `status=permissionMissing`,
  `processKind=appBundle`, `grantHint=grantAppBundle`.
- Preflight setup action:
  `grant-helper-video-app-screen-recording-permission`.
- Helper capability wrapper: schema `2`,
  `screenRecordingPermission=missing`, `availability=permissionMissing`,
  `captureAPI=screenCaptureKit`, safe failure
  `helperVideo.permissionMissing`.
- Permission request wrapper: schema `2`, `requestResult=notGranted`,
  `screenRecordingPermission=missing`, `availability=permissionMissing`.
- Helper synthetic probe-only: schema `1`,
  `helperVideoProbeMode=external-helper-synthetic-encoded-tcp`, helper-video
  `streamState=healthy`, `verdict=pass`, `startupBand=fast`,
  `sustainedUpdateBand=smooth`, `decodePressure=low`,
  `fallbackCountBucket=none`, no issue codes.
- Helper ScreenCaptureKit probe-only: schema `1`,
  `helperVideoProbeMode=external-helper-screen-capturekit-tcp`, helper-video
  `streamState=failed`, `verdict=fail`, `startupBand=failed`,
  `sustainedUpdateBand=stalled`, `decodePressure=notMeasured`,
  `fallbackCountBucket=one`.
- Helper ScreenCaptureKit probe-only issue codes:
  `helper-video-permission-missing`, `helper-video-stream-unhealthy`,
  `helper-video-startup-failed`, `helper-video-sustained-stalled`,
  `helper-video-fallback-observed`.
- Short live comparison: schema `67`,
  `networkCondition=constrained-cellular`, preset
  `sustained-v2-constrained-cellular-app-low-traffic`, practical target
  `iphone-poor-network-traffic-v1`, first-frame request
  `visible-glance`, request region `viewport-phone-portrait`.
- Short live comparison decision: `verdict=fail`,
  `primaryIssueCode=first-frame-payload-read-failed`,
  `primaryConstraint=receivePath`, recommended next probe
  `compareEncodingProfileGate`.
- Short live comparison transport cadence:
  `requestResponseStatus=below-target`, `continuousUpdatesStatus=not-tested`,
  recommended transport `request-response`, recommended next action
  `tuneTransportCadence`.
- Short live comparison candidate gates:
  `local-low-latency-rgb565` and `zrle-compression-0-rgb565` both failed with
  `first-frame-payload-read-failed` and `receivePath`. Both received all
  requested samples; `local-low-latency-rgb565` had `750` content sample
  permille while `zrle-compression-0-rgb565` had `1000`.
- Short live comparison helper-video side:
  `external-helper-synthetic-encoded-tcp` remained `pass`, `healthy`, `fast`,
  `smooth`, `low` decode pressure, and no fallback.

## Interpretation

The live password and helper path can now be reused through the launchctl-backed
wrapper without repeating long environment prefixes. The wrapper confirms the
current live credential references are present, but true ScreenCaptureKit helper
video remains blocked until `NaruHelperDev` receives Screen Recording approval
in macOS System Settings.

While that permission is pending, the VNC fallback path still fails the poor
network target on the receive path. The next large non-permission unit should
stay focused on startup payload-read / transport cadence behavior for the
viewport-aware constrained-cellular VNC fallback.
