# Input-Aware Frame Application Pacing Summary

Date: 2026-06-08 KST

## Question

Can the viewer protect Compose input, zoom/pan, and trackpad sampling before
content frames enter the MainActor frame-application path?

## Reproduction Target

The remaining physical-device report is that a real connection can make
gestures feel delayed and Korean Compose can accept one character before the
keyboard/input path appears frozen. Prior work already coalesced viewport-store
delivery, but repeated content frames could still reach app-model frame
application at visual cadence while input owned the session.

## Decision

Repeated content frame application now follows the same service priority as
frame-store delivery:

- ordinary visual playback: 60fps-class floor
- viewport navigation: 20fps-class floor
- focused Compose: 10fps-class floor
- empty/control updates: immediate

The frame-application queue still coalesces backlog to the initial frame,
newest content frame, and newest cursor/liveness update. After a pacing sleep,
the worker replaces a stale dequeued content frame with the newest pending
content frame when one exists.

## Verification

- `swift test --filter NaruRemoteAppModelTests/testSessionFrameApplicationWorkerPacingUsesInputAwareCadence`
- `swift test --filter NaruRemoteAppModelTests/testSessionStreamFrameApplicationQueueReplacesStaleDequeuedContentAfterPacingSleep`
- `swift test --filter NaruRemoteAppModelTests/testComposeFocusPacesFrameApplicationBeforeMainActorWork`
- `swift test --filter SessionFrameDeliveryPriorityModelTests`
- `swift test --filter SessionFrameStoreTests`
- `swift test --filter NaruRemoteAppModelTests` passed 153 tests.
- `swift test` passed 1247 tests, with 14 skipped benchmark tests.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests`
  passed 6 UI tests.

## Residual Gate

This is a local responsiveness isolation increment for the VNC fallback path.
Physical helper-video validation is still blocked until the iOS app can be
installed with a development provisioning profile and the macOS helper has
Screen Recording permission.
