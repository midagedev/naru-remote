# Helper Video Readiness Surface Summary - 2026-06-07

Purpose: keep moving the sustained iPhone remote-desktop goal after the
10fps gate again proved that the VNC visual path is server/update-cadence
limited, while the helper-video smoothness path is still blocked by setup
gates outside the VNC frame loop.

## Current Live Gate

Command:

```bash
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

Result:

- `overallGateState=blockedByHelperScreenCapture`
- `recommendedPrimaryAction=grant-helper-video-app-screen-recording-permission`
- physical iPhone discovery is connected, but local install remains blocked by
  `xcode-account-missing` and `ios-provisioning-profile-missing`
- synthetic helper-video and sustained synthetic helper-video pass with
  `codec=h264`, `codecProfile=high`, `startupBand=fast`,
  `sustainedUpdateBand=smooth`, `frameRateBucket=upTo30`, and
  `decodePressure=low`
- true ScreenCaptureKit helper-video still fails with
  `helper-video-permission-missing`
- VNC 10fps product verdict still fails with `contentFramesPerSecond=1.83`,
  `averageUpdateMilliseconds=520`, `p95UpdateMilliseconds=633`,
  `firstByteWaitP95Milliseconds=632`, `payloadReadP95Milliseconds=0`, and
  `clientProcessingP95Milliseconds=4`

Interpretation: VNC remains control/input/fallback. It is not the smooth visual
transport candidate for the iPhone sustained-session target until the server
update cadence changes. The app should help users and testers see the helper
video gate directly instead of hiding it behind benchmark-only JSON.

## Product Slice

This slice adds a connection-grid helper-video readiness badge derived only
from safe profile state and fixed helper-video catalog values:

- `VNC only`
- `Video setup`
- `Checking video`
- `Helper video`
- `Screen Recording`
- `Video off`
- `Video revoked`
- `Private only`
- `Helper offline`
- `VNC fallback`
- `Video failed`

The slice also preserves an existing `ConnectionProfile.helperVideo`
configuration during profile edits that come from the current profile editor.
Without this, editing a saved profile could silently remove the opt-in helper
video smoothness candidate.

## Focused Compose Isolation Slice

The same branch also closes a concrete post-send Compose freeze repro:

- starting point: focused Compose has a previous send result such as
  `Paste command sent; remote app confirmation unavailable.`
- user types the next Korean syllable
- `updateComposeDraftText` clears the stale `latestInjectionAttempt`
- before the fix, that status clear invalidated the focused dock render state
  and could disturb the `UITextView` IME chain before the second key

The fix treats all model-mirrored fields as advisory while UIKit owns Compose
focus. Send/helper status is removed from the focused editor host and rendered
in a sibling focused-status line, so status can update without recreating or
rewriting the `UITextView` bridge.

## Verification

```bash
swift test --filter RemoteInputDockRenderStateTests
swift test --filter RemoteInputDockSyncPolicyTests
swift test --filter NaruRemoteAppSnapshotTests
swift test --filter ProfileEditDeleteTests/testEditProfilePreservesExistingHelperVideoConfiguration
swift test --filter ProfileEditDeleteTests
swift test --filter HelperVideoStreamSessionRunnerTests
swift test --filter NaruRemoteAppModelTests/testStoredHelperVideoProfileInitializesPrivateNetworkStateWhenLoadingProfiles
swift test --filter NaruRemoteAppModelTests/testDisableAndRevokeHelperVideoPersistThroughProfileReload
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests test
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:NaruRemoteUITests/NaruRemoteLaunchUITests test
scripts/run-naru-live-benchmark.sh helper-readiness-sweep
scripts/run-naru-live-benchmark.sh physical-device-preflight
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

## Privacy Boundary

The grid badge and artifact use only fixed labels, aggregate benchmark values,
and setup action labels. They must not expose helper endpoints, helper paths,
pairing secrets, pairing fingerprints, hostnames, physical device IDs,
provisioning profile names, team identifiers, pixels, dimensions, byte counts,
coordinates, exact per-frame timings, raw OS errors, Compose text, clipboard
contents, or access-unit payloads.
