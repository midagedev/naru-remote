# 2026-06-04 Viewport Redraw + Input Diagnostics Verification

Branch: `codex/viewport-redraw-compose-diagnostics`

## Scope

- Coalesce incoming framebuffer redraws while a local viewport gesture is active.
- Preserve Compose draft text when the VNC clipboard-paste path can only report
  `unknown`.
- Add diagnostics schema v9 `input` report with safe fixed-catalog step status.

## Local Checks

- `swift test`
  - 607 tests passed
  - 10 opt-in/live benchmark tests skipped by default
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  - Build succeeded after regenerating `NaruRemote.xcodeproj`
- `git diff --check`
  - Passed

## Live Mac VNC Smoke

Redacted local Screen Sharing target over `127.0.0.1:5900`.

- `connectSession`: 1.217 s
- first frame pump: 3.191 s
- result: passed

## Synthetic Frame Upload Benchmark

Command: `NARU_RUN_SIM_BENCHMARKS=1 NARU_SIM_BENCHMARK_ITERATIONS=3 swift test --filter SyntheticFramePipelineBenchmarkTests/testSteadyStateFullUploadBenchmark`

- monotonic time average: 0.001 s
- CPU time average: 0.001 s
- peak physical memory average: 23856.960 kB

## Interpretation

The live target still spends multiple seconds on the first-frame path, so large
frame upload/redraw work remains capable of competing with touch handling on a
physical iPhone. This PR prioritizes touch tracking during local viewport
gestures by allowing the first incoming frame immediately, coalescing subsequent
gesture-time redraws to at most 15 fps, and flushing the latest deferred frame
when the gesture ends.
