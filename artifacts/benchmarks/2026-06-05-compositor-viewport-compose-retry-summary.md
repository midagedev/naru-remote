# 2026-06-05 Compositor Viewport + Compose Retry Summary

## Trigger

Physical iPhone feedback still reported unnatural, stuttering zoom/pan and
Compose input that did not reliably land on the remote Mac.

## Research Refresh

- [Apple `UIView.transform`](https://developer.apple.com/documentation/uikit/uiview/transform)
  applies transforms relative to the view bounds center and can be animated by
  Core Animation. That makes it a better touch-hot-path fit for local
  viewport-only motion than forcing a Metal redraw for every pinch/pan sample.
- [Apple `MTKView`](https://developer.apple.com/documentation/metalkit/mtkview/)
  supports draw-notification mode with `isPaused = true` and
  `enableSetNeedsDisplay = true`, where redraws happen when the app invalidates
  the view. Naru keeps this event-driven path for incoming remote frames.
- [Apple `CADisplayLink.preferredFrameRateRange`](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange)
  notes that actual callback cadence depends on hardware, power, thermal, and
  accessibility policy. Diagnostics should record refresh-rate buckets without
  assuming the app always gets the preferred maximum.
- [RFC 6143](https://www.rfc-editor.org/rfc/rfc6143) keeps RFB framebuffer
  updates request-driven and exposes clipboard/paste behavior through
  protocol/server capabilities. A paste command leaving the device is not the
  same as end-to-end remote app confirmation.

## Findings

- The previous renderer-projection path reduced SwiftUI churn, but still kept a
  viewport redraw display link and `MTKView.draw()` path in the local gesture
  pipeline. On physical iPhone this can still compete with touch tracking,
  remote frame upload, and thermal budget.
- The view transform matrix was doing manual center translations even though
  UIKit already scales `UIView.transform` around the layer anchor point. That
  could make the pan/zoom feel less natural than a simple center-scale plus
  clamped pan.
- Compose cleared the local draft after the clipboard set and paste command
  were delivered, even though Naru cannot yet confirm that the target app
  actually inserted the text. If the remote paste missed, the user's composed
  Korean/CJK text disappeared locally too.

## Changes

- `MetalFramebufferHostingView` now keeps `MetalFramebufferRenderer` drawing at
  the stable aspect-fit baseline and applies local zoom/pan/deceleration to the
  embedded `MTKView` layer with implicit animations disabled.
- Removed the dedicated viewport redraw display link and synchronous
  gesture-time `MTKView.draw()` path. Incoming remote frames still redraw via
  `setNeedsDisplay()`, with the latest deferred frame flushed when the gesture
  settles.
- Reapply the compositor transform in `layoutSubviews()` so rotation or size
  changes keep the same zoom/pan state visually aligned.
- Viewport diagnostics still report interaction/deferred-frame/deceleration
  counts and refresh-rate buckets, but redraw request/flush counts should fall
  toward zero on this compositor path.
- `ComposeDraft.markPasteDispatched` now preserves text for unconfirmed paste
  dispatch. The Send button remains retryable, and diagnostics still export
  only the safe boolean `hasComposeDraftText`, never the draft content.

## Verification

- Focused viewport/Compose suite:
  - `swift test --filter ViewportTransformTests --filter SessionViewportViewGeometryTests --filter MetalFramebufferRendererTests --filter ComposeDraftTests --filter NaruRemoteAppModelTests/testModelSendsComposedTextThroughActiveRFBTextClientAfterConnect --filter RemoteInputDockSyncPolicyTests`
  - Result: passed, 60 tests, 0 failures.
- Live Mac VNC connect-path smoke:
  - `NARU_LIVE_MAC_HOST=127.0.0.1 NARU_LIVE_MAC_PORT=5900 NARU_LIVE_MAC_PASSWORD='[redacted]' swift test --filter FakeRFBServerKitTests.LiveMacRFBSmokeTests/testStreamingSessionMirrorsConnectButtonPathAgainstRealMac`
  - Result: passed; connectSession about 1.27s, firstFramePump about 3.12s
    against the configured local macOS Screen Sharing endpoint.
- Physical iPhone availability:
  - `xcrun xctrace list devices` detected the connected iPhone.
  - Direct device build/install was blocked by missing Xcode signing team.
- Full package tests:
  - `swift test`
  - Result: passed, 637 tests, 10 skipped, 0 failures.
- Synthetic frame pipeline benchmark:
  - `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - Result: passed, 4 benchmarks, 0 failures.
  - Approximate monotonic-time averages in this run: full allocation/upload
    about 2.4ms, steady-state full upload about 0.44ms, small dirty rect about
    0.016-0.021ms, same-frame upload-gate skip at microsecond scale.
- Project generation:
  - `xcodegen generate --spec project.yml`
  - Result: passed.
- Generic iOS build without signing:
  - `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - Result: passed.
- iPhone simulator build:
  - `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: passed.
- Focused active-session UI screenshot tests:
  - `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveWidescreen_dark -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveWidescreen_light -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveKeyboard_dark -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveKeyboard_light -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveTrackpadCursor_dark -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveTrackpadCursor_light`
  - Result: passed; 4 discovered UI tests ran, 0 failures. The active
    widescreen tests refreshed both the stream and keyboard captures.
- Visual inspection:
  - Reviewed refreshed dark active-session, keyboard, and trackpad-cursor PNGs.
    The fake stream area is visible, the compact input dock stays above the
    keyboard, and the cursor overlay is visible without obvious overlap.

## Remaining Risk

- Simulator and host-shell tests cannot prove finger-to-glass latency, thermal
  behavior, or actual Korean/CJK insertion in the focused remote Mac app.
- If a server accepts the clipboard but the target app misses the paste command,
  Naru now keeps the draft retryable, but the next step is an explicit
  end-to-end remote-text confirmation path or a safer manual verification
  protocol for physical-device runs.
