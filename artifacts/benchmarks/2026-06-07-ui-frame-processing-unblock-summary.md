# UI Frame Processing Unblock Summary - 2026-06-07

## Scope

Physical iPhone testing reported a critical usability failure: immediately
after a real VNC connection started, gestures and keyboard input stopped
responding. This patch treats that as a UI executor isolation bug until further
device evidence proves otherwise.

No host names, credentials, frame contents, screenshots, pixels, coordinates,
draft text, IME state, device IDs, helper paths, raw network errors, or raw OS
errors are recorded here.

## Changes

- Run the VNC frame stream in a detached worker instead of a `Task {}` that
  inherits `NaruRemoteAppModel`'s `@MainActor`.
- Keep blocking `connectSession`, `RFBFramePump.nextFrame`, decode waits, and
  pacing sleeps off MainActor; hop back only for current-session checks,
  framebuffer publication, diagnostics, and stream stats.
- Stop forwarding ordinary foreground VNC frames into `PiPLayerHost`; PiP
  sample-buffer conversion now runs only while PiP watch is preparing, active,
  or stale.
- Move profile preview thumbnail sampling into a utility detached task before
  publishing/saving the thumbnail.
- Make `HelperVideoStreamSessionRunner` non-MainActor and wrap the renderer in
  an explicit main-actor box so helper-video start/network/result handling does
  not inherit the app chrome executor.

## Verification

```bash
swift test --filter HelperVideoStreamSessionRunnerTests
swift test --filter NaruRemoteAppModelTests
swift test --filter PiPWatchSampleBufferRendererTests
swift test --filter HelperVideoH264SampleBufferRendererTests
bash -n scripts/run-naru-live-benchmark.sh
```

All commands above passed locally.

## Residual Risk

This is a structural freeze mitigation, not final physical-device proof. The
next physical iPhone run should specifically verify that gestures, zoom/pan,
trackpad cursor movement, Compose typing, and reconnect remain responsive while
the VNC stream is receiving frames. If freeze persists, the next likely suspects
are Metal texture upload cadence, SwiftUI invalidation from framebuffer
publication, or synchronous AVSampleBuffer work inside the active helper-video
renderer.
