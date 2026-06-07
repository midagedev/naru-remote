# Helper Screen Recording Watch Action Summary - 2026-06-08

## Trigger

The live helper-video preflight is repeatedly blocked at the same safe state:
host, port, and credential are configured, but the helper app bundle still lacks
macOS Screen Recording permission. The previous preflight output named only the
manual grant action, even though the repo already has a bounded
`screen-recording-watch` runner that requests permission, opens Settings, polls
capability, and routes to the next helper-video gate when permission appears.

## Change

`BenchmarkLiveEnvironmentPreflightReport` is now schema v7. When an external
ScreenCaptureKit helper reports `permissionMissing` with an app-bundle grant
hint, setup actions are ordered as:

```json
[
  "run-screen-recording-watch",
  "grant-helper-video-app-screen-recording-permission"
]
```

This keeps the human action explicit while making the runnable next command
visible at the first preflight failure. Other helper identities keep their
existing routing:

- SwiftPM build artifacts still route to `install-stable-helper-video-executable`.
- Current command-line helpers still route to
  `request-helper-video-screen-recording-permission`.
- Available helper-video capability still routes to `run-live-gate`.

The top-level helper-video live-gate and remote-desktop readiness summaries now
also use `run-screen-recording-watch` as the primary recommendation while the
Screen Recording gate is blocked, so dashboards point to the runnable watcher
rather than stopping at a manual permission label.

## Live Evidence

Current safe preflight with the live password supplied from environment:

```text
NARU_LIVE_MAC_PASSWORD=... scripts/run-naru-live-benchmark.sh preflight
```

Before this change the report emitted schema v6 and:

```json
{
  "canRunLiveBenchmark": false,
  "credentialStatus": "environment",
  "helperVideoScreenCapturePermissionStatus": "missing",
  "issueCodes": ["helper-video-permission-missing"],
  "setupActionLabels": [
    "grant-helper-video-app-screen-recording-permission"
  ]
}
```

After this change, the same safe preflight emits schema v7:

```json
{
  "canRunLiveBenchmark": false,
  "credentialStatus": "environment",
  "helperVideoScreenCapturePermissionStatus": "missing",
  "issueCodes": ["helper-video-permission-missing"],
  "schemaVersion": 7,
  "setupActionLabels": [
    "run-screen-recording-watch",
    "grant-helper-video-app-screen-recording-permission"
  ]
}
```

The short live watch was also run with two polls. It opened Settings and safely
reported `watchStatus: timedOut`, `permissionRequest.requestResult:
notGranted`, `finalPermissionStatus: missing`, and `permissionGrantHint:
grantAppBundle`.

## Verification

```text
swift test --filter BenchmarkLiveEnvironmentPreflightTests
```

Result: passed, 21 tests. Coverage verifies schema v7, the new app-bundle
action ordering, legacy payload decoding, unavailable/timed-out helper routing,
and privacy boundaries.

```text
NARU_LIVE_MAC_PASSWORD=... scripts/run-naru-live-benchmark.sh preflight
```

Result: safe JSON remains blocked by `helper-video-permission-missing`, with
setup actions now beginning at `run-screen-recording-watch`.

```text
NARU_HELPER_SCREEN_RECORDING_WATCH_MAX_POLLS=2 \
NARU_HELPER_SCREEN_RECORDING_WATCH_INTERVAL_SECONDS=1 \
scripts/run-naru-live-benchmark.sh screen-recording-watch
```

Result: safe JSON reported `watchStatus: timedOut`,
`finalPermissionStatus: missing`, `permissionProcessKind: appBundle`, and
`permissionGrantHint: grantAppBundle`.

```text
scripts/run-naru-live-benchmark.sh screen-recording-watch-self-test
scripts/run-naru-live-benchmark.sh helper-video-live-gate-self-test
scripts/run-naru-live-benchmark.sh remote-desktop-readiness-summary-self-test
```

Result: all passed. The granted self-test path routes to
`run-true-helper-video-live-capture-benchmark`, and blocked top-level summaries
route to `run-screen-recording-watch`.

## Safety

This artifact and schema change do not emit helper executable paths, hostnames,
passwords, endpoints, pixels, framebuffer dimensions, byte counts, raw OS
errors, raw command output, signing identities, or exact timings. The new value
is a fixed action label only.
