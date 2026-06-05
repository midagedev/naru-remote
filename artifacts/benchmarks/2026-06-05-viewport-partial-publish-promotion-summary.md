# iPhone Viewport Partial Publish + ProMotion Summary

Date: 2026-06-05
Branch: codex/vnc-gesture-frame-budget

## Problem

Physical iPhone feedback still reported choppy zoom/pan and low apparent frame
rate. Code inspection found that `NaruRemoteAppModel.applyStreamFrame` deferred
all content frames while a local viewport interaction was active. That kept the
RFB request loop alive, but prevented the SwiftUI/Metal host from receiving
fresh small dirty-rect updates until the gesture ended.

## Changes

- Added `CADisableMinimumFrameDurationOnPhone=true` to the app plist and
  XcodeGen spec so ProMotion-class iPhones can use higher frame-rate animation
  hints.
- Added `ViewportInteractionFramePublishPolicy`.
- During pinch/pan/zoomed trackpad gestures:
  - partial dirty-rect updates can publish/request at 15 Hz;
  - full uploads remain coalesced at the existing conservative 4 Hz class and
    are flushed after the gesture settles.
- Aligned the Metal host's gesture-time incoming-frame redraw gate with the
  same 15 Hz partial dirty-rect cadence. This closes the gap where the app model
  could publish a small cursor/text update, but the renderer still admitted only
  the older 4 Hz interaction slot.
- Made viewport-interaction activation idempotent so repeated active signals do
  not reset the publish clock.
- Added a full-frame-only fallback: if a VNC server does not produce partial
  dirty rectangles during a long pinch/pan, full-frame refreshes can still pass
  at the conservative 4 Hz interval after gesture start.

## Verification

- `swift test --filter NaruRemoteAppModelTests/testViewportInteractionFramePublishPolicyPublishesOnlyBoundedPartialFrames --filter NaruRemoteAppModelTests/testModelKeepsFrameRequestsAliveWithViewportInteractionPacing --filter NaruRemoteAppModelTests/testViewportInteractionKeepsRequestsLiveAndFlushesLatestFrameAfterGesture --filter ViewportGestureRedrawThrottleTests --filter MetalFramebufferRendererTests/testSuspendedRendererAllowsOneThrottledUploadBypass`
  - Passed: 11 tests, 0 failures.
- `swift test --filter ViewportGestureRedrawThrottleTests --filter NaruRemoteAppModelTests/testViewportInteractionFramePublishPolicyPublishesOnlyBoundedPartialFrames --filter NaruRemoteAppModelTests/testModelKeepsFrameRequestsAliveWithViewportInteractionPacing`
  - Passed: 10 tests, 0 failures after aligning the renderer gate to the 15 Hz
    partial cadence and adding the bounded full-frame-only fallback.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - Passed: 4 tests, 0 failures.
  - Full framebuffer allocation/upload monotonic avg: about 2.46 ms.
  - Steady-state full upload monotonic avg: about 0.44 ms.
  - Small dirty-rect upload monotonic avg: about 0.017 ms.
  - Same-frame upload-gate skip: effectively zero monotonic time.
- `swift test`
  - Passed: 776 tests, 10 skipped, 0 failures.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Build succeeded.

## Research Notes

- RFC 6143 describes RFB updates as rectangle sequences and notes clients may
  regulate incremental update request rate to avoid excessive traffic:
  https://www.rfc-editor.org/rfc/rfc6143
- RFC 6143 also says pseudo-encodings are only safe after server-specific
  confirmation, which matches the app's conservative UTF-8 Compose policy:
  https://www.rfc-editor.org/rfc/rfc6143
- Apple recommends stable frame pacing for Metal drawables:
  https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html
- Apple documents `CADisplayLink.preferredFrameRateRange`; the app already uses
  it for deceleration display links, and the plist key now allows higher phone
  refresh ranges:
  https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange

## Residual Risk

The connected physical iPhone was visible to Xcode as offline during this run,
so manual device verification remains required for final UX confidence.
