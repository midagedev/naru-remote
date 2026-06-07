# Compose Input Island Summary - 2026-06-07

## Goal

Reproduce and close the active-session Compose freeze class where Korean input
accepts the first syllable and then the compact input surface appears to stop
responding while a remote session is active.

## Finding

`RemoteInputDockView` already keeps UIKit marked text local, but the surrounding
`RemoteInputDockEquatableHost` still treated the model-mirrored Compose draft
as part of the render identity. During a live session, a local edit can flow:

1. `UITextView` accepts the syllable.
2. The debounced local text mirror updates `NaruRemoteAppModel`.
3. The app snapshot derives new Compose/helper status from that same text.
4. The equatable host sees a new render state and updates the UIKit bridge while
   the keyboard still owns first responder.

That is exactly the wrong boundary for multilingual input: while the editor is
focused, UIKit must remain the owner of the in-flight text surface. The model
can still receive debounced mirrors for diagnostics/send readiness, but those
mirrors must not invalidate the editor.

## Change

- `RemoteInputDockRenderState` now carries `isComposeFieldFocused`.
- While Compose is focused and Direct mode is inactive, render-state equality
  ignores model-mirrored `initialText` and helper-status changes.
- Send-result status still invalidates the dock while focused, so users can see
  confirmation/failure after tapping Send.
- Added an active-session compact Compose XCUITest fixture path that types
  `입` then `력` against the live-session dock, not only the pre-connect profile
  detail form.

## Evidence

- `swift test --filter RemoteInputDockRenderStateTests` passed.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination
  'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'
  -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests test`
  passed both the active-session compact Compose test and the existing profile
  detail Compose test.

## Residual Risk

This fixes one concrete UIKit invalidation path. Physical iPhone verification is
still required because the reported freeze happened on-device during a real VNC
session, where frame traffic, keyboard cadence, thermal pressure, and touch
delivery differ from simulator fixtures.
