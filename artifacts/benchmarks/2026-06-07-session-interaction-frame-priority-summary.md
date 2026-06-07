# Session Interaction Frame Priority Summary - 2026-06-07

## Scope

Physical feedback still described live-session navigation and input as
half-beat late while the VNC path remains below the iPhone 10fps product gate.
This pass generalizes the prior Compose-only frame delivery protection into a
session interaction policy.

No host names, credentials, helper executable paths, endpoints, live stimulus
command text, raw OS errors, frame contents, pixels, dimensions, byte counts,
device IDs, draft text, marked text, keysyms, pointer coordinates, or clipboard
contents are recorded here.

## Current Gate State

Fresh local gated checks:

```bash
scripts/run-naru-live-benchmark.sh physical-device-preflight
NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip \
NARU_HELPER_SCREEN_RECORDING_WATCH_MAX_POLLS=1 \
NARU_HELPER_SCREEN_RECORDING_WATCH_INTERVAL_SECONDS=0 \
scripts/run-naru-live-benchmark.sh screen-recording-watch
scripts/run-naru-live-benchmark.sh helper-readiness-sweep
```

Results:

- Physical iPhone discovery: `connected`
- Physical build gate: `failed`
- Physical blockers: `xcode-account-missing`,
  `ios-provisioning-profile-missing`
- Helper-video synthetic probe: `pass`
- Helper-video sustained synthetic probe: `pass`
- True ScreenCaptureKit helper-video gate: `permissionMissing`
- Screen Recording setup actions:
  `grant-helper-video-app-screen-recording-permission`,
  `quit-and-relaunch-helper-after-permission-change`,
  `rerun-screen-recording-watch`

## Design Decision

While true helper-video capture is still permission-blocked, the foreground VNC
fallback must remain responsive to local input. The frame store now exposes an
`interactiveInput` delivery priority instead of a Compose-specific state.

The app model keeps this priority active for:

- Compose focus
- Active viewport zoom/pan gestures
- Short transient leases after direct-key taps, hardware-key events,
  Compose quick keys, pointer taps/clicks/scrolls/drags, and trackpad gestures

Transient leases expire automatically. Persistent reasons such as Compose focus
or an active viewport gesture keep the input-friendly cadence alive after the
transient lease expires.

## Changes

- Renamed the frame delivery priority to `interactiveInput`.
- Kept normal steady VNC frame delivery at `16` ms.
- Kept interaction-priority steady VNC frame delivery at `50` ms.
- Added a `150` ms transient interaction priority lease in `NaruRemoteAppModel`.
- Wired viewport gesture active state into the same priority policy.
- Marked direct, hardware, Compose quick-key, pointer, scroll, drag, and
  trackpad gesture paths as transient interaction activity.

## Verification

```bash
swift test --filter SessionFrameStoreTests
swift test --filter SessionFrameDeliveryPriorityModelTests
swift test
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test \
  -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringFramebufferAndCursorStorm
```

All commands passed locally. The focused UI test typed a two-step Korean
composition sequence while the active-session framebuffer/cursor storm fixture
was running, and verified the Compose field accepted the completed text without
the keyboard disappearing after the first character. The exact draft text is not
recorded in this artifact.

## Remaining Gates

This is not a 10fps VNC success claim. The next product gate still requires:

1. Grant Screen Recording to the helper app bundle.
2. Quit and relaunch the helper after permission changes.
3. Rerun `screen-recording-watch`, `helper-readiness-sweep`, and
   `helper-screen-app-bootstrap-benchmark`.
4. Resolve physical iPhone provisioning so T030/T031 can collect real-device
   sustained helper-video evidence.
