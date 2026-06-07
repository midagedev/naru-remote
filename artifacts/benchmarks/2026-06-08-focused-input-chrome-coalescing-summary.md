# Focused Input Chrome Coalescing Summary - 2026-06-08

## Reproduction

Physical feedback still reported that Compose could accept one Korean syllable
and then appear to stop responding after a real connection. The existing
simulator Compose suite was rerun first to avoid guessing:

```text
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' \
  test -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests
```

Result: passed, 8 tests. This means the lightweight simulator fixtures already
protect editor identity, framebuffer flood, cursor storm, model publish storm,
and helper-video health churn, but they do not reproduce the full physical
connection pressure.

## Research

- RFC 6143 says an incremental `FramebufferUpdateRequest` can wait
  indefinitely before the server sends an update, and fast clients may regulate
  request rate to avoid excessive traffic:
  https://www.rfc-editor.org/rfc/rfc6143#section-7.5.3
- The maintained rfbproto text also warns that multiple outstanding update
  requests are weakly correlated with resulting updates, which supports keeping
  VNC visual requests conservative instead of turning the frame pump into an
  unbounded request backlog:
  https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst
- Apple frames UI hangs around the main run loop/main thread and UIKit as the
  event-handling infrastructure, so Compose responsiveness has to reduce
  MainActor/SwiftUI publish pressure during local IME ownership instead of only
  optimizing the network reader:
  https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app
  and https://developer.apple.com/documentation/uikit

## Design

Focused Compose is now treated as a local input transaction. While the editor is
first responder:

- connection-quality chrome publishes are coalesced to the latest bucket;
- non-critical helper-video health chrome publishes are coalesced to the latest
  health sample;
- leaving Compose focus flushes the latest coalesced values immediately;
- helper-video fallback remains immediate because it changes the functional
  visual transport path, not just chrome.

This does not change RFB request cadence, pointer/key event dispatch, helper
video decoding, or visual fallback decisions. It only prevents telemetry/status
publish churn from forcing extra MainActor work while UIKit owns IME input.

## Verification

```text
swift test --filter NaruRemoteAppTests.SessionFrameDeliveryPriorityModelTests
```

Result: passed, including focused-input coalescing tests for connection quality
and helper-video health/fallback.

```text
swift test --filter 'NaruRemoteAppTests.NaruRemoteAppModelTests/test.*HelperVideo|NaruRemoteAppTests.NaruRemoteAppModelTests/test.*helperVideo|NaruRemoteAppTests.HelperVideoStreamSessionRunnerTests|NaruRemoteAppTests.SessionFrameDeliveryPriorityModelTests'
```

Result: passed, 45 tests. This keeps the focused-input coalescer covered
alongside the helper-video app-model and session-runner fallback paths.

```text
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' \
  test -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeSurvivesHelperVideoHealthStorm
```

Result: passed. The existing strongest simulator Compose storm still preserves
the same `UITextView` instance, accepts the second Korean syllable, and keeps
the keyboard visible.

```text
swift test
```

Result: passed, 1257 tests, 14 skipped.

```text
NARU_HELPER_SCREEN_RECORDING_WATCH_MAX_POLLS=2 \
NARU_HELPER_SCREEN_RECORDING_WATCH_INTERVAL_SECONDS=1 \
scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

Result: safe gate JSON reported `overallGateState` =
`blockedByScreenRecordingPermission`. The helper-video capture path was skipped
before collecting frames because Screen Recording permission is still missing.
The physical iPhone preflight saw a connected device, but build signing remains
blocked by missing Xcode account / iOS provisioning profile labels.

## Remaining Gate

This is a product-side mitigation for MainActor pressure during focused local
input. The true physical gate remains a signed iPhone run against the live Mac
connection, plus helper-video Screen Recording permission so the visual path can
move away from low-FPS VNC request/response.

## Safety

No host identity, credentials, command text, draft text, marked text, IME state,
keysyms, pointer coordinates, pixels, dimensions, byte counts, raw timings,
helper endpoints, pairing material, or physical device identifiers are emitted
by this artifact.
