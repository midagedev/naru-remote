# Screen Recording Watch Summary

Date: 2026-06-07 KST

## Scope

This artifact records the new launchctl-backed `screen-recording-watch` runner
for the helper-video ScreenCaptureKit permission gate.

The previous `screen-recording-setup` mode requested Screen Recording once,
opened System Settings, and rechecked capability immediately. That was useful
for setup, but it still forced a human to grant permission and then remember
which benchmark to rerun. The watch mode keeps the setup boundary explicit and
then polls the helper's safe capability labels until permission is granted or a
bounded poll budget expires.

## Command Shape

```bash
scripts/run-naru-live-benchmark.sh screen-recording-watch
```

For automation that must not open System Settings:

```bash
NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip \
NARU_HELPER_SCREEN_RECORDING_WATCH_MAX_POLLS=2 \
NARU_HELPER_SCREEN_RECORDING_WATCH_INTERVAL_SECONDS=0 \
scripts/run-naru-live-benchmark.sh screen-recording-watch
```

Fast regression:

```bash
scripts/run-naru-live-benchmark.sh screen-recording-watch-self-test | jq empty
```

## Current Live Result

Short non-interactive local run:

- `watchStatus`: `timedOut`
- `finalPermissionStatus`: `missing`
- `finalAvailability`: `permissionMissing`
- `pollsAttempted`: `2`
- `settingsOpenStatus`: `skipped`
- `issueCodes`: `helper-video-permission-missing`
- `setupActionLabels`:
  `grant-helper-video-app-screen-recording-permission`,
  `rerun-screen-recording-watch`

The self-test uses a fake helper that flips from `permissionMissing` to
`granted`. It verifies that the same runner emits:

- `watchStatus`: `granted`
- `finalPermissionStatus`: `granted`
- `finalAvailability`: `available`
- setup actions:
  `rerun-helper-readiness-sweep`,
  `run-true-helper-video-live-capture-benchmark`

## Interpretation

The current Mac remains blocked by Screen Recording permission for the stable
helper app bundle, but the live loop is now less brittle. After the user grants
Screen Recording, the watch command can detect the transition and tell the next
operator to rerun helper readiness and then run the true helper-video live
capture benchmark.

This does not attempt to grant macOS TCC permission programmatically. The
permission boundary remains user-controlled.

## Privacy

The watch report may include fixed status labels, fixed issue/action labels,
poll budget values, and helper safe capability JSON. It must not include helper
executable paths, helper endpoints, credentials, raw OS errors, pixels,
dimensions, byte counts, exact helper timings, hostnames, physical device IDs,
Compose text, marked text, keysyms, or clipboard contents.
