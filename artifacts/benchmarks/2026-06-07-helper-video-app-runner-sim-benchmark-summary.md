# Helper Video App Runner Simulator Benchmark Summary - 2026-06-07

## Scope

Add an opt-in benchmark for the app-side helper-video path after finite H.264
access units are available. The benchmark covers:

- app visual transport selection for accepted helper-video streams
- CoreMedia sample-buffer creation from helper-video access units
- helper-video health marking after displayable frames
- normal-test-loop skip behavior when simulator benchmarks are not explicitly
  enabled

This does not replace the true ScreenCaptureKit live helper-video gate. That
gate remains blocked until the stable helper app bundle receives macOS Screen
Recording permission.

## Commands

```bash
swift test --filter HelperVideoAppRunnerBenchmarkTests
```

Result: pass, with both helper-video app-runner benchmark cases skipped by the
opt-in environment gate.

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=1 \
swift test --filter HelperVideoAppRunnerBenchmarkTests
```

Result: pass. The static H.264 app-runner benchmark measured successfully. The
optional macOS VideoToolbox synthetic helper-source case skipped with a fixed
availability label on this host.

```bash
xcodebuild \
  -project NaruRemote.xcodeproj \
  -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteBenchmarkTests/HelperVideoAppRunnerBenchmarkTests \
  test
```

Result: pass. With `NARU_RUN_SIM_BENCHMARKS=1` and one local iteration set in
the booted simulator launchctl environment, the iOS simulator static H.264
app-runner benchmark measured successfully.

## Privacy Boundary

The committed artifact intentionally omits payload bytes, frame content,
display dimensions, byte counts, exact timings, helper endpoints, host names,
credentials, and raw encoder errors. Use local XCTest measurement output only
for relative investigation while keeping committed evidence to fixed labels.

## Next Gate

After macOS Screen Recording permission is granted to the stable helper app
bundle, rerun the helper readiness sweep and then run the true
ScreenCaptureKit helper-video access-unit benchmark for T031.
