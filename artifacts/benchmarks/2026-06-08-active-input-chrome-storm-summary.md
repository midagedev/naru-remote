# Active Input Chrome Storm Summary - 2026-06-08

## Trigger

Physical iPhone testing still reported that a live connection could accept one
Korean syllable in Compose and then feel frozen. The previous simulator
fixtures covered frame floods, cursor storms, model-published quality changes,
helper-video health churn, and first-frame layout transitions, but they did not
cover a bottom safe-area accessory appearing above the keyboard while UIKit
owned an active IME transaction.

## Research Inputs

- RFC 6143 describes RFB framebuffer updates as client-request driven: the
  server sends updates in response to explicit `FramebufferUpdateRequest`
  messages, incremental responses can wait indefinitely, and clients may
  regulate request rate to avoid excessive traffic.
  Source: https://www.rfc-editor.org/rfc/rfc6143
- RFC 6143 also makes `SetEncodings` a preference hint, not a guarantee. The
  server may still send raw pixel data, so VNC tuning cannot promise a
  Chrome-Remote-Desktop-like video cadence on every macOS Screen Sharing
  target.
  Source: https://www.rfc-editor.org/rfc/rfc6143
- Apple responsiveness guidance frames smooth interaction as splitting data
  preparation from UI updates so the main thread only performs the view work
  needed for drawing.
  Source: https://developer.apple.com/documentation/xcode/improving-app-responsiveness
- UIKit owns the window/view/event infrastructure and main run loop for iOS
  interaction. For Naru, active text composition must therefore minimize
  SwiftUI layout churn around the focused `UITextView`.
  Source: https://developer.apple.com/documentation/uikit
- VideoToolbox is the Apple framework for hardware-accelerated encode/decode.
  It is relevant to the helper-video H.264 path, not to pure RFB rectangle
  decode by itself.
  Source: https://developer.apple.com/documentation/videotoolbox
- ScreenCaptureKit is the macOS capture foundation for the helper-video path,
  so the helper app's Screen Recording permission is a real product gate before
  true live H.264 benchmarking.
  Source: https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos

## Reproduction

Added an XCUITest hook:

```text
NARU_TEST_INCOMING_CLIPBOARD_CHROME_STORM=1
```

The hook waits for Compose first-responder focus, then repeatedly publishes
remote clipboard reviews while the existing frame, cursor, model, and
helper-video storms are also running. This drives the exact missing pressure:
an incoming clipboard banner can mount inside the bottom `safeAreaInset` above
the system keyboard during Korean/CJK text composition.

Before the product change, the new test failed:

```text
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeDefersIncomingClipboardChromeDuringFullStorm \
  test
```

Result: failed. The accessibility assertion observed
`naru.input.incomingClipboard.banner` after the first Korean syllable while
the editor was still first responder.

## Design Decision

Treat focused Compose as an input island, not as normal app chrome:

- while Compose is focused, the pending remote clipboard review remains in the
  model but is not rendered above the keyboard;
- the focused live-session status line stays mounted with fixed text;
- the existing equatable input host continues to freeze model-mirrored Compose
  fields while UIKit owns IME focus;
- when focus leaves, the deferred incoming clipboard review becomes visible
  again and can be accepted or dismissed normally.

This is broader than a visual hide flag: `RemoteInputAccessoryChromeState`
centralizes the bottom accessory chrome contract, making the rule testable
without relying on SwiftUI body details.

## Live Benchmark Context

The live benchmark preflight was rerun with credentials supplied through the
environment. It reported:

```json
{
  "canRunLiveBenchmark": false,
  "credentialStatus": "environment",
  "helperVideoScreenCapturePermissionStatus": "missing",
  "issueCodes": ["helper-video-permission-missing"]
}
```

The VNC 10fps cadence sweep from this thread still pointed away from iPhone
renderer upload as the dominant FPS blocker: the best VNC profile stayed near
2 content FPS with first-byte wait dominating, and Tight-first profiles failed
before usable incremental samples. That keeps the visual-transport conclusion
unchanged: pure VNC remains the control/fallback path, while practical
Chrome-Remote-Desktop-like visual smoothness needs the helper-video
ScreenCaptureKit + VideoToolbox path after the permission gate is cleared.

## Verification

```text
swift test --filter RemoteInputDockRenderStateTests
```

Result: passed, 10 tests. The new unit coverage verifies focused accessory
chrome defers incoming clipboard review rendering but does not discard the
pending review.

```text
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeDefersIncomingClipboardChromeDuringFullStorm \
  test
```

Result after implementation: passed. The same focused editor instance accepted
`입` then `력`, the keyboard stayed visible, and the incoming clipboard banner
remained deferred while focused.

```text
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests \
  test
```

Result: passed, 10 tests.

## Safety

This artifact does not store hostnames, passwords, target fingerprints,
framebuffer pixels, cursor pixels, raw dimensions, raw byte counts, command
text, draft text beyond synthetic fixture strings, marked text, helper
endpoints, pairing material, or physical device identifiers.
