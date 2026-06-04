# Pinch / Compose Follow-up

Date: 2026-06-05

Physical-device report: zooming and panning still felt unnatural and choppy, and
Compose input was not reliable enough for sustained iPhone use.

## Change

- Added a pure `ViewportTransform.pinched(...)` helper that combines scale with
  pinch-centroid translation, so two-finger pinch/drag motion moves the viewport
  with the fingers instead of only changing scale.
- Updated the Metal-hosted pinch recognizer to remember the previous centroid and
  feed centroid delta through the shared viewport transform.
- Preserved pannable crop-fill baseline offsets when the pinch scale is clamped
  to the live-session minimum zoom floor.
- Hardened Compose text snapshot resolution:
  - send-button enablement can fall back to active marked text when the
    `UITextView` committed snapshot is briefly empty
  - send commit can preserve the pre-commit current draft when UIKit reports a
    committed string that dropped the marked segment

## Verification

- `swift test --filter ViewportTransformTests --filter RemoteInputDockSyncPolicyTests`
- `swift test`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build`

## Residual Risk

This is still not a substitute for a physical iPhone retest against the user's
Mac VNC target. It narrows two concrete causes of unnatural movement and IME
text loss, but full Photos-grade navigation may still require moving the
viewport host to a `UIScrollView`-style physics surface.
