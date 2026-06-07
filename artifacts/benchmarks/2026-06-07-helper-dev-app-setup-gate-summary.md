# Helper Dev App Setup Gate Summary - 2026-06-07

## Goal

Remove one setup ambiguity from the true ScreenCaptureKit helper-video gate:
the helper used for permission checks should be the stable app-bundle wrapper,
and setup evidence should be collected without printing helper paths or raw
install output.

## Change

Added `scripts/run-naru-live-benchmark.sh helper-dev-app-setup`.

The mode:

- builds and installs the local `NaruHelperDev` app wrapper;
- sets launchctl `NARU_HELPER_EXECUTABLE` for future GUI-launched shells;
- runs the helper Screen Recording permission request;
- optionally opens macOS Screen Recording settings;
- emits one privacy-safe JSON object with fixed install/signing/env labels,
  helper capability JSON, fixed issue codes, and setup action labels.

## Evidence

- `bash -n scripts/run-naru-live-benchmark.sh` passed.
- `NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip scripts/run-naru-live-benchmark.sh helper-dev-app-setup`
  emitted schema `1` JSON with:
  - `installStatus=passed`
  - `codeSigningStatus=appleDevelopment`
  - `launchctlEnvStatus=set`
  - `helperProcessKind=appBundle`
  - `screenRecordingPermission=missing`
  - setup action `grant-helper-video-app-screen-recording-permission`
- `scripts/run-naru-live-benchmark.sh helper-readiness-sweep` after setup
  emitted:
  - `processKind=appBundle`
  - synthetic helper-video `pass`
  - sustained synthetic helper-video `pass`
  - ScreenCaptureKit helper-video `fail` while Screen Recording remains missing

## Current Read

The helper setup gate now points at the correct app-bundle identity and is
ready for the user to grant Screen Recording in macOS settings. It does not
complete T031 by itself; true ScreenCaptureKit capture still needs permission,
then a passing `helper-screen-probe` and physical iPhone verification.

## Privacy Boundary

This artifact intentionally omits helper executable paths, app paths,
launchctl values, team identifiers, signing identity names, raw install logs,
host identity, endpoints, credentials, physical device identifiers, pixels,
byte counts, exact timings, Compose text, marked text, and IME state.
