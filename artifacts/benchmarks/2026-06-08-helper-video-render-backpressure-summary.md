# Helper-Video Render Backpressure Summary - 2026-06-08

## Reproduction

The sustained helper-video path had source-side and TCP backpressure, but the
app-side renderer still treated every accepted access unit as work to prepare
for display. If the foreground `AVSampleBufferDisplayLayer` queue falls behind
on iPhone, replaying every old delta frame can trade freshness for heat,
memory, and visible latency.

## Design

Use renderer readiness before expensive CoreMedia sample-buffer preparation:

- Parameter sets always pass through so decoder format state is preserved.
- Keyframes always pass through so visible recovery is not delayed.
- Delta access units may be dropped when the display layer reports it is not
  ready for more media data.
- Dropped deltas keep the helper-video stream healthy, but downgrade fixed
  health labels from `smooth/low` to `usable/medium`.

Apple documents `AVSampleBufferDisplayLayer.isReadyForMoreMediaData` as a
queue-occupancy signal for clients that can produce sample buffers faster than
the renderer consumes them:
https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer/1387317-isreadyformoremediadata

## Change

- Added `HelperVideoAccessUnitRenderBackpressureReporting`.
- `HelperVideoH264SampleBufferRenderer` now reports delta-only drops when the
  display layer is not ready for more media data.
- `HelperVideoStreamSessionRunner` asks the renderer before enqueueing access
  units for both streaming and finite start-result paths.
- `HelperVideoStreamSessionOutcome` now includes a safe
  `droppedAccessUnitCount` for tests/benchmarks; product diagnostics still use
  fixed helper-video health labels.
- Added a focused Compose UI regression gate that runs helper-video health
  churn together with framebuffer flood, trackpad cursor pressure, and
  app-model chrome churn. This keeps the current renderer/status work tied to
  the physical "first Korean input step then keyboard freezes" symptom instead
  of treating helper-video as a separate visual-only concern.

## Verification

Runner regression:

```bash
swift test --filter NaruRemoteAppTests.HelperVideoStreamSessionRunnerTests
```

Result: pass, 12 tests.

Renderer and default benchmark skip path:

```bash
swift test --filter 'NaruRemoteAppTests.HelperVideoH264SampleBufferRendererTests|NaruRemoteBenchmarkTests.HelperVideoAppRunnerBenchmarkTests'
```

Result: pass, 15 tests, 4 opt-in benchmarks skipped.

Opt-in static app-runner benchmark:

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=1 \
NARU_HELPER_VIDEO_APP_BENCHMARK_FRAMES=16 \
swift test --filter NaruRemoteBenchmarkTests.HelperVideoAppRunnerBenchmarkTests/testStaticH264AccessUnitsThroughAppRunnerBenchmark
```

Result: pass. Local measured values from XCTest:

- Clock monotonic time: about `0.001459` s for the measured batch
- CPU time: about `0.001890` s
- Peak physical memory: about `7390.976` kB

Full suite:

```bash
swift test
```

Result: pass, 1255 tests, 14 skipped, 0 failures.

Focused Compose with helper-video status pressure:

```bash
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  test -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeSurvivesHelperVideoHealthStorm
```

Result: pass, 1 UI test. The lifecycle probe kept the same focused
`UITextView` token with `make=1` and `firstResponder=true` through both Korean
input steps while helper-video health, framebuffer, trackpad cursor, and model
chrome storms were active.

Live helper-video gate:

```bash
scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

Result: blocked before true helper-video capture by the current local setup
gates:

- `overallGateState`: `blockedByScreenRecordingPermission`
- Screen Recording watch: `timedOut`
- final helper permission: `missing`
- physical iPhone: connected; code signing identity and development team
  environment are available, but Xcode account and provisioning profile are
  still missing, so install/build preflight remains blocked

Safe JSON output:
`artifacts/benchmarks/2026-06-08-helper-video-live-gate-render-backpressure.json`.

## Remaining Gate

True ScreenCaptureKit helper-video and physical iPhone evidence still require:

- Grant Screen Recording to the stable helper app bundle.
- Quit and relaunch the helper after the permission change.
- Add the Xcode account and create the iOS development provisioning profile for
  the connected iPhone.
- Rerun:

```bash
scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

## Privacy Boundary

This artifact contains no host identity, credentials, ports, command text,
draft text, marked text, keysyms, pointer coordinates, display dimensions,
pixels, byte counts, raw stdout/stderr, raw network errors, raw OS errors, or
exact live frame timing samples.
