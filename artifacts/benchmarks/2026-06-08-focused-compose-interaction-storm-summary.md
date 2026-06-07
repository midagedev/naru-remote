# Focused Compose Interaction Storm Summary

Date: 2026-06-08 KST

## Reproduced Symptom

Physical iPhone feedback reported that after a real connection attached, the
app could accept one Korean/CJK Compose input step and then feel frozen: the
keyboard stayed visually present but further typing did not reliably reach the
focused editor. Earlier simulator gates covered cursor pressure and framebuffer
floods, but they did not reproduce the full live-session shell pressure where
connection quality, helper/readiness status, and stale send status can also
publish app-model chrome changes while UIKit is composing marked text.

## Design Decision

Focused Compose is now treated as a UIKit-owned input transaction:

- `UITextView` keeps owning the active IME/editor identity while focused.
- `RemoteInputDockEquatableHost` continues to keep the focused editor render
  state stable.
- `FocusedComposeStatusLineState` now exposes fixed focused copy instead of
  reflecting dynamic helper/send/quality state while focus is active.
- Dynamic send/helper status resumes after focus leaves the editor.
- `SessionFrameStore` remains the frame-delivery boundary; same-size frame
  pressure should not invalidate Compose.

This is intentionally an architecture boundary, not a coefficient tweak. The
focused keyboard/editor stack must not resize, remount, or get a new sibling
identity because a previous `Remote app confirmation unavailable` result
cleared, helper readiness changed, or connection quality republished during a
live stream.

## New Regression Gate

The app now has a dedicated XCUITest-only model publish storm hook:

- `NARU_TEST_MODEL_PUBLISH_STORM=1`
- Active-session fixture only
- Mutates connection-quality chrome every 6 ms for 900 samples
- Runs together with the existing trackpad cursor storm and framebuffer flood

`ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringFullInteractionStorm`
starts an active session, focuses compact Compose, types two Korean input
steps, and asserts that the editor value advances while the iOS keyboard stays
mounted under all three storms.

## Verification

```text
swift test --filter RemoteInputDockRenderStateTests --filter RemoteInputDockSyncPolicyTests --filter SessionFrameStoreTests
```

Result: passed, 81 selected tests.

```text
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringFullInteractionStorm
```

Result: passed, 1 UI test. The focused active-session Compose editor accepted
the second Korean input step while framebuffer flood, cursor storm, and
app-model chrome churn were all active.

## References

- Apple `UIViewRepresentable.updateUIView(_:context:)` documentation:
  https://developer.apple.com/documentation/swiftui/uiviewrepresentable/updateuiview(_:context:)
- Apple `UITextInput.markedTextRange` documentation:
  https://developer.apple.com/documentation/uikit/uitextinput/markedtextrange
- Apple SwiftUI `View.equatable()` documentation:
  https://developer.apple.com/documentation/swiftui/view/equatable()

## Residual Risk

This simulator gate is stronger than the previous reproduction, but it is not
a replacement for physical iPhone validation. The next product-grade gate still
needs a real iPhone retest against a live Mac session, and the broader visual
smoothness goal still depends on unblocking true helper-video
ScreenCaptureKit/VideoToolbox capture. This change closes the focused Compose
freeze class under deterministic UI pressure; it does not by itself raise the
current VNC visual stream from the roughly 2fps live-readiness blocker to the
10fps target.

## Privacy

This artifact records fixed test names, aggregate pass/fail evidence, public
Apple documentation links, and architectural decisions only. It does not
include host identity, credentials, helper endpoints, physical device
identifiers, framebuffer pixels, pointer coordinates, raw logs, raw Compose
text, marked-text contents, or IME internals.
