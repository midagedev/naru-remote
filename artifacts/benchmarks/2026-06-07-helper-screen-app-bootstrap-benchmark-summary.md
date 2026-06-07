# Helper Screen App Bootstrap Benchmark Summary

Date: 2026-06-07 KST

## Purpose

Add a privacy-safe gate for the remaining helper-video T031 risk: finite
ScreenCaptureKit access units must be able to travel through helper TCP
framing, app-model helper-video bootstrap, and the H.264 sample-buffer factory
before helper video can be treated as the primary smoothness path.

## Runner

`scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark`

The runner executes the opt-in app-runner XCTest with:

- `NARU_RUN_SIM_BENCHMARKS=1`
- `NARU_SIM_BENCHMARK_ITERATIONS=1`
- `NARU_HELPER_VIDEO_APP_BENCHMARK_FRAMES=2`
- filter:
  `HelperVideoAppRunnerBenchmarkTests/testNetworkBackedScreenCaptureKitHelperVideoBootstrapThroughAppModelSmoke`

Raw XCTest stdout/stderr is captured only for pass/skip/fail classification and
is not emitted.

## Verification

- `swift test --filter HelperVideoAppRunnerBenchmarkTests/testNetworkBackedScreenCaptureKitHelperVideoBootstrapThroughAppModelSmoke`
- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark`
- `jq empty /tmp/naru-helper-screen-app-bootstrap-benchmark.json`

## Current Result

```json
{
  "schemaVersion": 1,
  "mode": "helper-screen-app-bootstrap-benchmark",
  "status": "skipped",
  "sourceMode": "screen-capturekit",
  "transportPath": "helper-tcp-to-app-model",
  "decodePath": "h264-sample-buffer-factory",
  "iterationCount": 1,
  "requestedFrameCount": 2,
  "issueCodes": ["screen-capturekit-app-bootstrap-skipped"],
  "setupActionLabels": [
    "grant-screen-recording-to-benchmark-host",
    "rerun-helper-screen-app-bootstrap-benchmark"
  ]
}
```

## Interpretation

- The new app-bootstrap ScreenCaptureKit benchmark compiles and is runnable
  through the launchctl-backed runner.
- The current local environment has not yet produced pass evidence because
  ScreenCaptureKit capture is skipped until the benchmark host has Screen
  Recording/capture setup.
- This closes the repeatability gap before T031, but does not complete T031.
  The next evidence step is a passing `helper-screen-app-bootstrap-benchmark`,
  followed by the physical iPhone helper-video gate.

## Privacy

The runner emits only fixed mode/source/path/status labels, fixed issue/action
labels, and configured counts. It omits raw XCTest output, frame payloads,
pixels, dimensions, endpoints, helper paths, device IDs, credentials, byte
counts, raw OS errors, and exact timings.
