# Helper Video Network Bootstrap Smoke Summary - 2026-06-07

## Scope

Add an opt-in macOS SwiftPM smoke benchmark for the app-model helper-video
connect bootstrap after T029X. The smoke covers:

- VNC first framebuffer remains the session's safe baseline visual/control path
- helper-video starts only after that first framebuffer is available
- the helper-video start request travels through the real authenticated TCP
  server/client harness
- finite VideoToolbox synthetic H.264 access units feed the app-side
  sample-buffer renderer
- VNC pointer/control remains active after helper-video becomes the visual
  transport

This is not the physical iPhone + Mac live ScreenCaptureKit gate. It is the
automatic bridge between the injected app bootstrap test and the later true
live helper-video benchmark.

## Commands

```bash
swift test --filter HelperVideoAppRunnerBenchmarkTests/testNetworkBackedHelperVideoBootstrapThroughAppModelSmoke
```

Result: pass, with the network-backed smoke skipped by the opt-in environment
gate.

```bash
NARU_RUN_SIM_BENCHMARKS=1 \
NARU_SIM_BENCHMARK_ITERATIONS=1 \
NARU_HELPER_VIDEO_APP_BENCHMARK_FRAMES=2 \
swift test --filter HelperVideoAppRunnerBenchmarkTests/testNetworkBackedHelperVideoBootstrapThroughAppModelSmoke
```

Result: pass. The app model connected through the fake VNC first-frame path,
then started helper-video through the loopback authenticated TCP helper-video
server/client path, selected helper-video visual transport, and preserved VNC
pointer/control.

```bash
scripts/run-naru-live-benchmark.sh preflight
```

Result: pass for safe preflight reporting. Live credentials are configured via
the environment-backed runner, but true live helper-video remains blocked by
fixed permission labels: `helperVideoExternalCapability.status=permissionMissing`,
`helperVideoScreenCapturePermissionStatus=missing`, and setup action
`grant-helper-video-app-screen-recording-permission`.

## Privacy Boundary

The committed artifact intentionally omits payload bytes, frame content,
display dimensions, byte counts, exact timings, helper endpoints, host names,
credentials, pairing secrets, raw OS/network errors, and raw encoder errors.
Use local XCTest output only for investigation while keeping committed evidence
to fixed pass/skip labels.

## Next Gate

Grant macOS Screen Recording permission to the stable helper app bundle, rerun
the helper readiness sweep, then run the true ScreenCaptureKit helper-video
access-unit benchmark for T031 and physical iPhone verification for T030.
