# 2026-06-05 Viewport Redraw Diagnostics v13

## Trigger

Physical iPhone feedback still reports hot-device, low-FPS, and unnatural
zoom/pan behavior. Existing v12 diagnostics can separate receive, app-frame
apply, and renderer-upload timing, but they cannot yet say whether local
viewport redraw scheduling is competing with touch handling during pinch/pan.

## Change

- Added `ViewportRedrawDiagnostics`, a safe aggregate value type for local
  viewer-side counters only.
- `MetalFramebufferHostingView` batches viewport diagnostics locally and flushes
  them at gesture boundaries instead of publishing `@Published` model state at
  touch/display-link cadence.
- Active-session diagnostic export is schema v13 and now includes:
  - `viewportInteractionCount`
  - `viewportIncomingFrameDeferredCount`
  - `viewportRedrawRequestCount`
  - `viewportRedrawFlushCount`
  - `viewportDecelerationFrameCount`
  - `viewportDisplayRefreshRateBucket`

## Privacy Boundary

The new fields are counts and a fixed frame-rate bucket. They do not include
coordinates, pixels, framebuffer dimensions, target identity, raw timestamps,
device model, raw refresh rate, or user content.

## Verification

- `swift test --filter DiagnosticExportTests --filter NaruRemoteAppSnapshotTests/testSessionStreamStatsBuildSafeDiagnosticPerformanceReport`
  - 19 tests passed.
- `swift test`
  - 637 tests passed, 10 skipped.
- `xcodegen generate --spec project.yml`
  - regenerated `NaruRemote.xcodeproj` after adding the new Core type.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - build succeeded.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - 4 benchmark tests passed.
  - Steady-state full-upload monotonic average: 0.000441-0.000478 seconds
    across the measured samples in this simulator run.
  - Small dirty-rect upload monotonic average: 0.000016-0.000021 seconds
    across the measured samples in this simulator run.
  - Same-frame upload-gate skip path completed at microsecond scale in the
    simulator run.
- Hermes PR review follow-up:
  - Replaced the viewport refresh-rate bucket's `+1` frame-count shim with a
    direct `framesPerSecond` bucketing helper.
  - Added boundary coverage for not-measured, 59.9fps, 60fps, and 120fps.

## Next Physical Check

Run a sustained physical iPhone session and export diagnostics after several
pinch/pan/trackpad interactions. High viewport redraw request counts with low
flush counts would point to local viewport scheduling; low renderer upload
buckets with poor delivered FPS would point back to stream pacing or server-side
frame production.
