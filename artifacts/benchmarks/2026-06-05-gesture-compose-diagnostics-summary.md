# Gesture / Compose Diagnostics Follow-up

Date: 2026-06-05

Physical-device report: zooming and panning still felt choppy, and Compose input
still did not feel dependable in keyboard-accessory use.

## Change

- Added safe aggregate viewport gesture diagnostics to diagnostic JSON v14:
  - gesture sample count
  - gesture long-frame count
  - maximum gesture callback interval bucket
- Kept raw gesture timestamps, coordinates, framebuffer pixels, host details, and
  compose text out of diagnostic exports.
- Show actionable Compose send status in compact keyboard-accessory mode while
  hiding the default ready copy to preserve screen space.
- Removed per-touch renderer viewport resets from the compositor-driven
  pinch/pan hot path; the renderer stays at the stable aspect-fit baseline while
  the `MTKView` layer transform handles local navigation.

## Verification

- `swift test --filter ViewportRedrawDiagnosticsTests --filter RemoteInputDockSyncPolicyTests --filter NaruRemoteAppSnapshotTests --filter DiagnosticExportTests`
- `swift test`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build`
- `xcrun devicectl list devices`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS,id=00008130-000C15D80C43001C' build` failed before compile because signing needs a development team.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## Residual Risk

This improves the next diagnostic report and trims touch-path state churn, but it
still does not replace an installed physical iPhone run. Installing/running on
the connected iPhone needs a development team/provisioning profile in the Xcode
project.
