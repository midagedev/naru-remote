# Trackpad Cursor Store + Compose Pressure Gate - 2026-06-07

## Goal

Reproduce the physical-iPhone report where an active VNC session becomes
unresponsive after connection: zoomed trackpad movement keeps publishing cursor
state while the focused compact Compose editor should still accept Korean/CJK
IME input.

## Reproduction Gate

- Unit pressure: `TrackpadModeModelTests/testContinuousTrackpadCursorMirrorDoesNotInvalidateAppModel`.
- UI pressure: `ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringTrackpadCursorStorm`.
- Test hook: `NARU_TEST_TRACKPAD_CURSOR_STORM=1` drives 300 trackpad
  drag-changed samples at an 8 ms cadence on an active-session fixture while the
  UI test types into the Compose editor.

## Design Decision

Continuous trackpad cursor mirror publication is no longer an
`NaruRemoteAppModel.@Published` field. The app model keeps immediate resolver
state for the UIKit/Metal hot path, while the slower SwiftUI cursor overlay
observes `TrackpadCursorStore` locally through the viewport bridge.

This makes the boundary explicit:

- UIKit/Metal owns visible finger-paced cursor and viewport movement.
- `NaruRemoteAppModel` owns session/control state, but does not invalidate the
  whole app shell for every cursor mirror sample.
- SwiftUI observes a viewport-local cursor mirror only where the overlay needs
  it, so focused compact Compose keeps the same UIKit editor identity during
  cursor and frame churn.

## Privacy

The gate is deterministic and fixture-only. It does not export host identity,
framebuffer dimensions, pixels, cursor coordinates, raw draft text, marked text,
or IME state.

## Verification

- `swift test --filter TrackpadModeModelTests`
- `swift test --filter RemoteInputDockRenderStateTests`
- `swift test --filter SessionFrameStoreTests`
- `xcodegen generate --spec project.yml`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringTrackpadCursorStorm test`

