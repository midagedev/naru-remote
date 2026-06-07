# 2026-06-08 Helper-Video Live Gate Runner Summary

## Purpose

The current 10fps readiness gate still shows VNC below the product target from
receive-path first-byte wait, while helper-video synthetic and sustained
synthetic H.264 pass. The next usable-session milestone is true helper-video
capture/decode, but that gate is blocked by macOS Screen Recording permission.

This increment adds a single command:

```text
scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

The command chains Screen Recording watch, helper readiness sweep, and app
bootstrap smoke into one privacy-safe report.

## Design

- If Screen Recording is not granted, report
  `blockedByScreenRecordingPermission`.
- Skip helper readiness and app bootstrap work while permission is missing.
- Once Screen Recording is granted, continue through helper screen capture
  readiness and the ScreenCaptureKit app-model H.264 decode smoke.
- Route a fully passing gate to the physical iPhone helper-video gate.

## Verification

```text
scripts/run-naru-live-benchmark.sh helper-video-live-gate-self-test | jq '.status, .blockedSummary.overallGateState, .readySummary.overallGateState'
```

Result: passed, with `blockedByScreenRecordingPermission` and
`readyForPhysicalIPhoneGate` summary fixtures.

```text
NARU_HELPER_SCREEN_RECORDING_WATCH_MAX_POLLS=2 \
NARU_HELPER_SCREEN_RECORDING_WATCH_INTERVAL_SECONDS=1 \
scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

Result: current live helper remains blocked at Screen Recording:

- `watchStatus`: `timedOut`
- `finalPermissionStatus`: `missing`
- `finalAvailability`: `permissionMissing`
- `overallGateState`: `blockedByScreenRecordingPermission`
- `recommendedPrimaryAction`: `grant-helper-video-app-screen-recording-permission`
- readiness subreport: `skipped`
- app bootstrap subreport: `skipped`

## Next Gate

Grant Screen Recording to the `NaruHelperDev` app bundle, quit/relaunch the
helper, then rerun `helper-video-live-gate`. A granted run should proceed to
helper screen capture and app decode smoke before the physical iPhone gate.

## Safety

The runner emits only fixed status, issue, action, and transport labels plus
existing safe helper capability/subreports. It does not emit helper executable
paths, endpoints, credentials, raw OS errors, pixels, dimensions, byte counts,
physical device identifiers, raw XCTest output, or exact helper timings.
