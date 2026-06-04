# Renderer Viewport + Compose Diagnostics Summary

Date: 2026-06-04

## What changed

- Moved live zoom/pan projection from `MTKView.transform` into `MetalFramebufferRenderer` draw geometry.
- Gesture redraws now reproject the current texture immediately while suspending pending framebuffer uploads.
- Incoming VNC frames that arrive during a local viewport gesture are deferred and flushed after the gesture settles.
- Compose diagnostics now classify the draft payload as `ascii`, `latin1`, or `utf8ExtensionRequired` without exporting text.

## Rationale

- Apple documents `MTKView` as supporting explicit `draw()` workflows in addition to `setNeedsDisplay()`-driven redraws. The renderer now uses explicit redraws only for local viewport movement and avoids upload work in that path.
- RFC 6143 `ClientCutText` is Latin-1 by specification; many servers accept UTF-8 in practice, but multilingual text can still depend on server-specific clipboard behavior. The new payload encoding field keeps that distinction visible without leaking draft content.

## Verification

- `swift test`: 610 tests passed, 10 skipped.
- `xcodegen generate --spec project.yml`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`: passed.
- `NARU_RUN_SIM_BENCHMARKS=1 NARU_SIM_BENCHMARK_ITERATIONS=3 swift test --filter SyntheticFramePipelineBenchmarkTests/testSteadyStateFullUploadBenchmark`: passed.
  - Monotonic time average: 0.00047s.
  - CPU time average: 0.00084s.
  - Peak physical memory average: 23654.763 kB.
- Live Mac VNC smoke against local Screen Sharing: passed.
  - `connectSession`: 1.173s.
  - `firstFramePump`: 2.959s.
