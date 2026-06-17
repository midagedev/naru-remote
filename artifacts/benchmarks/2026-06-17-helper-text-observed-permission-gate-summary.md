# Helper Text Observed Permission Gate - 2026-06-17

## Scope

This artifact records the current helper-native text insertion gate for the
Compose input lane. It separates local iOS Compose editor responsiveness from
actual remote/native text insertion through the macOS helper.

This is not a physical iPhone Compose Green claim, 200-character mixed-language
manual pass, or remote app insertion pass. It is the current Mac-side observed
native-insert readiness result.

## Self-Tests

Commands:

```bash
scripts/run-naru-live-benchmark.sh helper-text-observed-probe-self-test
scripts/run-naru-live-benchmark.sh helper-text-live-gate-summary-self-test
```

Result:

- `helper-text-observed-probe-self-test=observed-inserted`
- `helper-text-live-gate-summary-self-test=passed`
- The summary logic covers:
  - permission blocked
  - helper sent but unobserved
  - ready for physical Compose gate

## Current Observed Probe

Command:

```bash
scripts/run-naru-live-benchmark.sh helper-text-observed-probe
```

Log:

```text
/tmp/naru-helper-text-observed-probe-20260617-unicode-hangul.log
```

Result:

```json
{
  "schemaVersion": 1,
  "mode": "helper-text-observed-probe",
  "status": "failed",
  "payload": "unicode-hangul",
  "payloadEncoding": "utf8ExtensionRequired",
  "strategyPreference": ["nativeInsert"],
  "capabilityAvailability": "permissionMissing",
  "accessibilityValueInsert": "missing",
  "unicodeKeyboardEvent": "missing",
  "pasteboardFallback": "missing",
  "targetReadinessStatus": "target-ready",
  "insertStatus": "failed",
  "strategyUsed": "nativeInsert",
  "safeFailureCode": "helper.permissionMissing",
  "observationStatus": "no-input",
  "failureLabel": "helper.permissionMissing",
  "issueCodes": [
    "helper-text-permission-missing",
    "helper.permissionMissing"
  ],
  "setupActionLabels": [
    "grant-helper-text-accessibility-or-input-monitoring-permission",
    "quit-and-relaunch-helper-after-permission-change"
  ]
}
```

Interpretation:

- The controlled local text target was ready.
- Native insert did not reach the target because the helper reports missing
  text insertion permissions.
- This is not evidence that iOS Compose typing is frozen; the simulator input
  gate passed separately. This is the next Mac helper permission/setup gate for
  actual composed-text delivery.

## Required Next Action

Before claiming helper-native composed-text insertion:

1. Grant the stable helper app Accessibility permission required for
   accessibility value insertion.
2. Quit and relaunch the helper after the permission change.
3. Rerun:

```bash
scripts/run-naru-live-benchmark.sh helper-text-observed-probe
scripts/run-naru-live-benchmark.sh helper-text-live-gate
```

If `helper-text-live-gate` reports `readyForPhysicalComposeGate`, the next
useful evidence is a physical iPhone Compose native-insert run.

## Privacy

This artifact contains only fixed payload labels, fixed capability/permission
labels, fixed issue/action labels, and a local log path. It omits raw inserted
text, target app titles, focused window names, helper executable paths,
endpoints, credentials, profile fingerprints, clipboard contents, raw OS
errors, key events, coordinates, screenshots, pixels, dimensions, byte counts,
and exact timing series.
