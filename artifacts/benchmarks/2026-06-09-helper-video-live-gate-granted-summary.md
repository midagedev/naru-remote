# Helper Video Live Gate Granted Summary — 2026-06-09

## Scope

Record the first local `helper-video-live-gate` run after the selected
`NaruHelperDev.app` Screen Recording permission reported `granted`.

Command:

```bash
scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

The runner now imports the optional live VNC environment before the nested
helper readiness preflight, so its preflight rows reflect the configured live
host and credential state instead of false missing-host labels.

## Result

- Screen Recording watch: `granted`
- Helper capability: `available`
- Helper readiness preflight host: `configured`
- Helper readiness preflight credential: `environment`
- External synthetic helper-video: `pass`
- External sustained synthetic helper-video: `pass`
- External ScreenCaptureKit helper-video: `pass`
- App bootstrap benchmark: `passed`
- App bootstrap source: `screen-capturekit`
- App bootstrap transport path: `helper-tcp-to-app-model`
- App bootstrap decode path: `h264-sample-buffer-factory`
- Overall gate state: `blockedByPhysicalIPhoneGate`
- Recommended primary action: `add-xcode-account`
- Physical iPhone build status: `failed`
- Physical issue codes: `xcode-account-missing`,
  `ios-provisioning-profile-missing`

Interpretation:

- The true helper-video capture/decode path is no longer blocked by macOS
  Screen Recording permission on this machine.
- ScreenCaptureKit frames can pass through the selected external helper app,
  helper-video TCP framing, the app-model helper-video bootstrap, and the H.264
  sample-buffer factory.
- The next gate is physical iPhone signing/provisioning, then the physical
  helper-video hand-feel and thermal run.

## Verification

- `scripts/run-naru-live-benchmark.sh helper-video-live-gate`
- `scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark`
- `scripts/run-naru-live-benchmark.sh helper-video-live-gate-self-test`
- `swift test --filter HelperVideoAppRunnerBenchmarkTests/testNetworkBackedScreenCaptureKitHelperVideoBootstrapThroughAppModelSmoke`

## Safety

The artifact records only fixed labels and configured counts. It does not
include helper executable paths, endpoints, credentials, raw XCTest output, raw
helper stdout/stderr, raw OS errors, display dimensions, pixels, byte counts,
exact timings, physical device identifiers, Compose text, marked text, keysyms,
pointer coordinates, or clipboard contents.
