# Helper Live Gate Physical Preflight Summary - 2026-06-08

## Change

`helper-video-live-gate` now collects `physical-device-preflight` even when
Screen Recording permission is missing and true ScreenCaptureKit helper-video
capture work is skipped.

## Current Live Result

- Overall gate: `blockedByScreenRecordingPermission`
- Blocked labels:
  - `screen-recording-permission-gate-blocked`
  - `physical-iphone-gate-blocked`
- Recommended primary action:
  `grant-helper-video-app-screen-recording-permission`
- Additional setup action labels:
  - `grant-helper-video-app-screen-recording-permission`
  - `quit-and-relaunch-helper-after-permission-change`
  - `rerun-screen-recording-watch`
  - `rerun-helper-video-live-gate`
  - `add-xcode-account`
  - `create-ios-development-provisioning-profile`

## Physical Preflight State

- Device discovery: `connected`
- Device selection source: `environment`
- Device ID resolution: `environmentXcodebuildUDID`
- Code signing identity: `available`
- Development team: `environment`
- Xcode account: `missing`
- Provisioning profile: `missing`
- Build check: `failed`

## Verification

- `scripts/run-naru-live-benchmark.sh helper-video-live-gate-self-test`
- `scripts/run-naru-live-benchmark.sh helper-video-live-gate`

## Privacy

This artifact uses fixed labels only. It does not contain helper paths,
endpoints, credentials, host identity, device IDs, device names, account names,
provisioning profile names, raw xcodebuild logs, raw OS errors, pixels,
dimensions, byte counts, exact timings, pointer coordinates, or text payloads.
