# Nonblocking RFB Input Enqueue Summary

Date: 2026-06-08 KST

## Problem Reproduced

Physical iPhone feedback reported that, immediately after a real VNC
connection, gestures could stop responding and Compose/keyboard input could
feel frozen after the first input.

The deterministic reproduction added in this pass is:

- First pointer tap enters the outbound pointer lane.
- The pointer write stalls long enough to trip the app-level timeout.
- A second pointer tap on the same active session must still be delivered.

Before the fix,
`DirectKeystrokeModeTests/testTimedOutPointerInputDoesNotPermanentlyDisableLaterPointerInput`
failed because the timed-out pointer path cleared the active pointer client and
coordinate space. The follow-up tap recorded zero pointer events.

## Design Change

User input is now treated as a UI-latency lane, not as a synchronous socket
completion lane:

- Pointer and key queues remain separated at the app-model level.
- Pointer-lane timeout clears only the queued pointer backlog and drag throttle
  state.
- Pointer-lane timeout no longer clears the active pointer client or remote
  coordinate space.
- `RFBNetworkClient.sendPointerEvent` and `sendKeyEvent` enqueue bytes to
  `NWConnection` and return without waiting for `contentProcessed`.
- A later send failure still tears down the stream through the normal
  connection-failure path, but transient back-pressure no longer freezes the UI
  or disables future input.

This preserves ordered click/key envelopes through the app-level lanes while
removing the most expensive UI coupling: waiting for Network.framework send
completion on each user input event.

## Verification

- Failed-before-fix reproduction:
  `swift test --filter DirectKeystrokeModeTests/testTimedOutPointerInputDoesNotPermanentlyDisableLaterPointerInput`
- Passed-after-fix reproduction:
  `swift test --filter DirectKeystrokeModeTests/testTimedOutPointerInputDoesNotPermanentlyDisableLaterPointerInput`
- Broader input/gesture coverage:
  `swift test --filter DirectKeystrokeModeTests`
- Trackpad model coverage:
  `swift test --filter TrackpadModeModelTests`
- Direct pointer mapping/serialization coverage:
  `swift test --filter PointerEventTapTests`
- Focused Compose render-isolation coverage:
  `swift test --filter RemoteInputDockRenderStateTests`
- Compose IME sync-policy coverage:
  `swift test --filter RemoteInputDockSyncPolicyTests`
- Full SwiftPM suite:
  `swift test` passed on final rerun with 1260 tests executed, 14 skipped.
- Xcode project refresh/build:
  `xcodegen generate --spec project.yml` and
  `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build`
  passed.

## Live Benchmark Snapshot

Live benchmark environment was rerun against the local Mac Screen Sharing target
using redacted environment credentials.

- `preflight`: host, port, and credential were configured; helper-video capture
  remained blocked only by Screen Recording permission with the single issue
  code `helper-video-permission-missing`.
- `helper-readiness-sweep`: external synthetic and sustained synthetic
  helper-video probes passed (`h264`, high profile, low decode pressure,
  smooth sustained band). The true ScreenCaptureKit probe failed only as
  `permissionBlocked`.
- `short-live-comparison`: the best VNC app-low-traffic candidate was
  `zrle-compression-0-rgb565` at roughly 2.19 content fps, with warning/fail
  pressure dominated by receive/first-byte wait rather than local input
  dispatch. This is below the 10 fps product target and confirms that this pass
  fixes input-lane freezing, not the remaining VNC frame-rate ceiling.
- `remote-desktop-readiness-summary-self-test`: passed; summary state remains
  `blockedByHelperScreenCapture`, with VNC 10 fps gate failing at about 1.9 fps
  in the self-test fixture and primary action
  `grant-helper-video-app-screen-recording-permission`.

## Residual Risk

This closes a concrete simulator reproduction for pointer capability loss after
a stalled write and removes `contentProcessed` from production pointer/key
latency. It still needs a physical iPhone retest against the live Mac VNC
session because the original report combined real network back-pressure,
physical keyboard/IME behavior, and live framebuffer pressure. VNC frame rate
also remains below the 10 fps product target on this live setup; practical
streaming smoothness is still gated on enabling and validating the true
helper-video ScreenCaptureKit path.

## Privacy

No raw text, marked text, keysyms, pointer coordinates, framebuffer pixels,
dimensions, byte counts, or host identifiers are recorded here.
