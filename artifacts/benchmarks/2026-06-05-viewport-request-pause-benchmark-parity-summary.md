# Viewport Request-Pause Benchmark Parity — 2026-06-05

## Change

- `VNCLiveBenchmark` schema v26 changes
  `--stream-shape-viewport-interaction app` from post-frame pacing-floor parity
  to request-pause parity.
- The mode now inserts a synthetic visible-frame request-pause window before
  incremental stream-shape samples and reports only safe aggregates:
  paused request count/permille, pause poll count, and aggregate paused
  milliseconds.
- The fixed in-flight fallback floors remain in the report, but they are no
  longer treated as the normal app path.

## Rationale

- The app now pauses new `FramebufferUpdateRequest` work while a viewport
  gesture is active and a framebuffer is already visible.
- RFB framebuffer updates are client-demanded, so benchmark parity needs to
  model request suppression rather than only slower post-frame sleeps.

## Verification

- `swift run VNCLiveBenchmark --help`
  - Passed.
  - Help shows `--stream-shape-viewport-interaction-pause-seconds`.
- `swift test`
  - Passed: 739 tests, 10 skipped, 0 failures.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Passed: `BUILD SUCCEEDED`.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - Passed: 4 benchmark tests.
  - Full allocation/upload average clock time: about 0.003s.
  - Same-frame upload-gate skip average clock time: near 0.000s.
  - Small dirty-rect upload average clock time: near 0.000s.
  - Steady-state full upload average clock time: about 0.001s.
- `git diff --check`
  - Passed.

## Residual Risk

- Live VNC stream-shape parity was not run in this pass because
  `NARU_LIVE_MAC_HOST` / `NARU_LIVE_MAC_PASSWORD` were not present in the
  environment. A follow-up live run should use:

```bash
swift run VNCLiveBenchmark \
  --first-frame-profiles none \
  --stream-shape-samples 8 \
  --stream-shape-viewport-interaction app \
  --stream-shape-viewport-interaction-pause-seconds 0.20 \
  --json
```
