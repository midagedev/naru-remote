# 2026-06-05 Trackpad Redraw + Renderer Upload Timing Summary

## Trigger

Physical-device report: zooming/panning still felt unnatural and choppy, and
Compose input was not reliable enough for sustained iPhone use.

## Research Refresh

- [RFC 6143](https://www.rfc-editor.org/rfc/rfc6143) keeps normal framebuffer
  updates request-driven and defines `PointerEvent` as pointer movement plus
  button state. Trackpad movement should therefore keep the server frame/cursor
  path flowing; it should not be treated as a local viewport gesture unless the
  viewport is actually moving.
- RFC 6143 also notes the Cursor pseudo-encoding lets the viewer draw the
  pointer locally to improve perceived performance on slow links. Deferring
  cursor-only or low-cost frame publication during ordinary trackpad movement
  works against that goal.
- [Apple's Metal frame-rate guidance](https://developer-mdn.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html)
  treats 60fps as the usual iOS target and 30fps as the lower real-time floor.
  A gesture-time incoming-frame throttle at 15fps is therefore too low for a
  direct-manipulation viewport.
- [Apple's Metal command-buffer guidance](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/CommandBuffers.html)
  warns that too much CPU/GPU synchronization can stall. Naru keeps redraws
  display-link-coalesced and records upload timing instead of logging raw frame
  data.

## Findings

- `MetalFramebufferHostingView` called `beginViewportTransformGesture()` for
  every trackpad drag, even at fit scale. That suspended pending texture uploads
  and told the app model to defer streamed frame publication, so normal mouse
  movement could make the remote/server cursor appear to jump.
- Gesture-time incoming-frame redraws were capped at `1/15s`. Even though local
  reprojection used a display link, remote frame/cursor updates could visually
  arrive at a choppy cadence during interaction.
- Zoomed trackpad auto-pan was still conservative after the previous damped
  follow-pan change. It reduced jumps, but the viewport lagged behind cursor
  movement on phone-sized viewports.
- Compose send enablement and payload reads could still rely on SwiftUI state
  that lagged behind the active UIKit `UITextView`, especially while Korean/CJK
  marked text was being edited.
- Existing diagnostics reported renderer upload strategy counts, but not actual
  successful Metal upload elapsed-time buckets. Hot-device reports could not
  separate app frame-apply pressure from renderer upload pressure.

## Changes

- Trackpad drag now owns viewport-interaction state only when the current
  framebuffer transform is pannable. Unzoomed trackpad cursor movement keeps
  streamed frame/server-cursor publication live.
- Gesture-time incoming-frame redraw pacing changed from 15fps to 30fps.
- Zoomed trackpad auto-pan now applies a larger damped portion of the reveal
  delta and allows a larger per-sample catch-up step.
- Compose reads the active `UITextView` text directly for send-button disabled
  state and for the final send payload after marked text is committed.
- Renderer upload timing is now measured on successful Metal uploads and
  exported only as aggregate sample count plus average/max
  `notMeasured|subFrame|interactive|lagging|stalled` buckets in diagnostics
  schema v12.

## Privacy Boundary

Diagnostics and artifacts do not include raw milliseconds, raw timing samples,
framebuffer dimensions, coordinates, pixels, byte counts, cursor pixels, target
identity, device power state, or raw errors. Raw upload timing is memory-only and
bucketed before export.

## Verification

- Focused gesture/diagnostic/Compose suite:
  - `swift test --filter DiagnosticExportTests --filter NaruRemoteAppSnapshotTests/testSessionStreamStatsBuildSafeDiagnosticPerformanceReport --filter MetalFramebufferRendererTests/testSuccessfulUploadReportsTimingSample --filter PointerGestureResolverTests --filter TrackpadModeModelTests/testTrackpadDragUsesZoomedTransformAndReturnsAutoPan --filter RemoteInputDockSyncPolicyTests --filter ViewportGestureRedrawThrottleTests`
  - Result: passed, 42 tests, 0 failures.
- Full package tests:
  - `swift test`
  - Result: passed, 629 tests, 10 skipped, 0 failures.
- Synthetic frame pipeline benchmark:
  - `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - Result: passed, 4 benchmarks, 0 failures.
  - Approximate monotonic-time averages: full allocation/upload 2.4ms,
    steady-state full upload 0.46ms, small dirty-rect upload 0.018ms, same-frame
    upload-gate skip 0.003ms.
- iPhone simulator build:
  - `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: passed.
- Active-session focused UI screenshot tests:
  - `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveWidescreen_dark -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveWidescreen_light -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveTrackpadCursor_dark -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveTrackpadCursor_light`
  - Result: passed, 4 UI tests, 0 failures.

## Remaining Risk

- Physical iPhone hand feel still requires retest. Simulator and unit tests
  cannot prove finger-to-glass latency, thermal throttling, or real display
  scheduling under sustained VNC load.
- Compose remote paste success still depends on the target VNC server's
  clipboard support. If a server falls back to legacy `ClientCutText`, non-Latin
  text may remain unreliable even though the local UIKit compose field now reads
  its current text more robustly.
