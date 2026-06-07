# Helper-Video Permission Diagnostics Summary - 2026-06-08

## Reproduction

The live `remote-desktop-10fps-readiness` gate was re-run after the focused
input hot-path work. VNC still failed the 10fps product gate from
first-byte-wait dominated receive cadence, while helper-video synthetic and
sustained synthetic H.264 probes passed. The remaining helper-video blocker was
macOS Screen Recording permission for the stable helper app bundle.

Before this fix, the ScreenCaptureKit probe reported the real permission
blocker together with stream-health labels such as startup failed, sustained
stalled, and fallback observed. That was misleading: when Screen Recording is
missing, true capture has not started yet.

## Change

`BenchmarkHelperVideoReport` now treats an explicit
`helper-video-permission-missing` issue as a setup blocker. It suppresses
health-derived helper-video issue codes until Screen Recording permission is
granted and a real capture stream can run.

The readiness output now keeps the helper screen-capture issue list focused:

```text
screenCaptureIssueCodes = ["helper-video-permission-missing"]
screenCaptureReadinessState = "permissionBlocked"
screenCaptureRecommendedAction = "grant-helper-video-app-screen-recording-permission"
```

## Verification

```bash
swift test --filter BenchmarkHelperVideoReportTests
```

Result: passed, 11 tests.

```bash
scripts/run-naru-live-benchmark.sh helper-video-live-gate-self-test
scripts/run-naru-live-benchmark.sh remote-desktop-readiness-summary-self-test
```

Result: both passed.

```bash
scripts/run-naru-live-benchmark.sh helper-readiness-sweep
```

Result: live-safe helper screen probe reported only
`helper-video-permission-missing` for the permission-blocked capture path.

```bash
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

Result: live-safe readiness summary reported:

- overall gate: `blockedByHelperScreenCapture`
- helper synthetic: `pass`
- helper sustained synthetic: `pass`
- helper screen capture: `permissionBlocked`
- helper screen-capture issue codes: `helper-video-permission-missing`
- VNC product verdict: `fail`
- VNC content FPS: about `1.91`
- VNC primary issue: `first-byte-wait-failed`

## Remaining Gate

Grant Screen Recording to `NaruHelperDev`, quit/relaunch the helper, rerun
`screen-recording-watch`, then rerun `helper-video-live-gate` or
`remote-desktop-10fps-readiness`. Physical iPhone installation still also needs
the Xcode account / iOS development provisioning setup labels to clear.

## Privacy

This artifact contains no host identity, credentials, ports, helper paths,
device identifiers, account names, provisioning names, raw xcodebuild logs, raw
OS errors, pixels, dimensions, byte counts, exact timings, pointer coordinates,
keysyms, Compose text, marked text, or clipboard contents.
