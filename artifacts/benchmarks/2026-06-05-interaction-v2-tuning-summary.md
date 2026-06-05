# Interaction v2 Tuning Summary - 2026-06-05

Target: `iphone-sustained-usability-v2`

Scope:
- Zoomed trackpad cursor-follow pan tuning.
- Gesture hot-path viewport state publication boundary.
- Marked-text Compose Send stabilization.

Safe changes:
- Increased central zoomed trackpad follow-pan coupling while compensating
  cursor sensitivity so visible cursor travel remains finger-paced.
- Kept visible viewport motion on the UIKit/Core Animation path and deferred
  SwiftUI/PiP viewport-state publication until gesture end.
- Increased the marked-text Compose Send stabilization snapshot window from 20
  to 30 bounded reads; the fast path for no marked text remains unchanged.

Verification completed in this PR:
- `swift test --filter PointerGestureResolverTests`
- `swift test --filter TrackpadModeModelTests/testTrackpadDragUsesZoomedTransformAndReturnsAutoPan`
- `swift test --filter RemoteInputDockSyncPolicyTests/testComposeSendStabilizationWindowCoversDelayedIMECommit`
- `swift test` (824 tests, 10 skipped)
- `xcodegen generate --spec project.yml`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

Residual gate:
- T390 remains open until a 10 minute physical iPhone hand-feel/thermal pass
  and sustained v2 stream comparison are recorded. That pass must also check
  whether the longer marked-text Compose Send stabilization window adds
  noticeable send latency. This artifact does not claim physical-device pass
  status.

Privacy:
- This artifact intentionally contains only fixed target names, safe tuning
  labels, and planned verification names. It contains no host identity,
  credentials, framebuffer dimensions, coordinates, pixels, cursor pixels, byte
  counts, raw samples, raw payloads, user-entered text, hidden preflight
  contents, or raw error text.
