# Helper Text Permission Watch Summary — 2026-06-08

## Trigger

Physical-device testing showed local Compose text can be entered, but the
finished Compose payload does not appear in the remote Mac app. After
`2026-06-08-compose-text-event-strategy-summary.md`, automatic Compose routes
through helper native insertion when a helper is reachable. The remaining
question is whether the helper process has the macOS permissions required for
native insertion.

## Change

Added a helper text permission request surface:

```bash
NaruHelper --request-text-permission
```

The request surface prompts for:

- Accessibility trust for AX value insertion.
- Post-event access for Unicode keyboard events and the explicit pasteboard
  fallback path.

Added launchctl-backed runner modes:

```bash
scripts/run-naru-live-benchmark.sh helper-text-capability
scripts/run-naru-live-benchmark.sh request-helper-text-permission
scripts/run-naru-live-benchmark.sh helper-text-permission-watch
scripts/run-naru-live-benchmark.sh helper-text-permission-watch-self-test
```

`helper-text-permission-watch` mirrors `screen-recording-watch`: it checks the
safe helper capability, requests permission, opens Accessibility and Input
Monitoring settings unless skipped, polls for `nativeInsert`, and emits only
fixed status/action labels plus safe helper capability JSON.

## Current Live Observation

After reinstalling the stable development helper app wrapper:

```bash
scripts/install-naru-helper-dev-app.sh --set-launchctl-env
scripts/run-naru-live-benchmark.sh helper-text-capability
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
  NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
  scripts/run-naru-live-benchmark.sh helper-text-permission-watch
```

The stable app-bundle helper currently reports:

```json
{
  "availability": "permissionMissing",
  "supportedStrategies": []
}
```

The permission watch reports:

```json
{
  "watchStatus": "timedOut",
  "finalAvailability": "permissionMissing",
  "finalAccessibilityValueInsert": "missing",
  "finalUnicodeKeyboardEvent": "missing",
  "finalPasteboardFallback": "missing",
  "permissionProcessKind": "appBundle",
  "permissionGrantHint": "grantAppBundle",
  "issueCodes": ["helper-text-permission-missing"],
  "setupActionLabels": [
    "grant-helper-text-accessibility-or-input-monitoring-permission",
    "quit-and-relaunch-helper-after-permission-change",
    "rerun-helper-text-permission-watch"
  ]
}
```

This confirms the current Compose remote-insertion failure is blocked before
text reaches the target app: the helper is not yet authorized for either native
text insertion route.

## Safety

The new runner does not emit helper paths, endpoints, credentials, raw OS
errors, text payloads, clipboard bytes, pixels, dimensions, byte counts, or
exact helper timings. It keeps the diagnostic boundary to fixed labels and safe
capability catalogs.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
swift test --filter NaruHelperTextBridgeCapabilityProbeTests --filter NaruHelperTextBridgeProtocolTests
swift test
scripts/run-naru-live-benchmark.sh helper-text-permission-watch-self-test
scripts/install-naru-helper-dev-app.sh --set-launchctl-env
scripts/run-naru-live-benchmark.sh helper-text-capability
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
  NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
  scripts/run-naru-live-benchmark.sh helper-text-permission-watch
```
