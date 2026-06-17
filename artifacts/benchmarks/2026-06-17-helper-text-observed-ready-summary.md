# Helper Text Observed Ready Refresh - 2026-06-17

## Scope

This artifact records the current macOS helper-native text insertion readiness
after installing the stable helper app wrapper and refreshing helper text
permissions.

This is not a physical iPhone Compose Green claim and does not replace the
physical iPhone soft-keyboard/manual gate. It proves that the local helper text
path can perform observed native insertion for the required payload classes
against a controlled local AppKit text target.

## Setup Refresh

Command:

```bash
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
  scripts/run-naru-live-benchmark.sh helper-text-dev-app-setup
```

Log:

```text
/tmp/naru-helper-text-dev-app-setup-20260617-skip-settings.log
```

Result:

- `installStatus=passed`
- `codeSigningStatus=appleDevelopment`
- `launchctlEnvStatus=set`
- `helperProcessKind=appBundle`
- `permissionGrantHint=grantAppBundle`
- Initial post-setup capability still reported `permissionMissing`, so the
  permission watch was run next.

Permission watch:

```bash
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
NARU_HELPER_TEXT_PERMISSION_WATCH_INTERVAL_SECONDS=0 \
  scripts/run-naru-live-benchmark.sh helper-text-permission-watch
```

Log:

```text
/tmp/naru-helper-text-permission-watch-20260617-skip-settings.log
```

Result:

- `watchStatus=granted`
- `finalAvailability=reachable`
- `finalAccessibilityValueInsert=granted`
- `finalUnicodeKeyboardEvent=granted`
- `finalPasteboardFallback=available`
- `supportedStrategies=[nativeInsert, pasteboardPasteWithRestore]`

## Observed Native Insert Matrix

Commands:

```bash
NARU_HELPER_TEXT_OBSERVED_PROBE_PAYLOAD=ascii \
  scripts/run-naru-live-benchmark.sh helper-text-observed-probe

NARU_HELPER_TEXT_OBSERVED_PROBE_PAYLOAD=latin1 \
  scripts/run-naru-live-benchmark.sh helper-text-observed-probe

scripts/run-naru-live-benchmark.sh helper-text-observed-probe
```

Logs:

```text
/tmp/naru-helper-text-observed-probe-20260617-ascii-after-permission.log
/tmp/naru-helper-text-observed-probe-20260617-latin1-after-permission.log
/tmp/naru-helper-text-observed-probe-20260617-unicode-hangul-after-permission.log
```

Result:

| Payload | Encoding | Status | Strategy | Observation | Failure |
| --- | --- | --- | --- | --- | --- |
| `ascii` | `ascii` | `observed-inserted` | `nativeInsert` | `matched` | `none` |
| `latin1` | `latin1` | `observed-inserted` | `nativeInsert` | `matched` | `none` |
| `unicode-hangul` | `utf8ExtensionRequired` | `observed-inserted` | `nativeInsert` | `matched` | `none` |

## Live Gate

Command:

```bash
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
NARU_HELPER_TEXT_PERMISSION_WATCH_INTERVAL_SECONDS=0 \
  scripts/run-naru-live-benchmark.sh helper-text-live-gate
```

Log:

```text
/tmp/naru-helper-text-live-gate-20260617-ready.log
```

Result:

- `overallGateState=readyForPhysicalComposeGate`
- `nativeInsertReady=true`
- `observedProbeStatus=observed-inserted`
- `observationStatus=matched`
- `observedSafeFailureCode=none`
- `recommendedPrimaryAction=run-physical-iphone-compose-native-insert-gate`

## Interpretation

- The helper-native route is now the best Compose delivery candidate for
  multilingual composed text.
- The VNC KeyEvent observed fallback remains a separate blocker: the companion
  `2026-06-17-text-keystroke-observed-no-input-summary.md` shows that both
  ASCII and Hangul VNC KeyEvent probes enqueue successfully but do not reach the
  controlled text target.
- The next useful product evidence is physical iPhone Compose native insertion
  once iOS signing/provisioning allows the app gate to run.

## Privacy

This artifact contains only fixed payload labels, fixed permission labels,
fixed strategy labels, fixed issue/action labels, aggregate pass/fail results,
and local log paths. It omits raw inserted text, focused app/window titles,
helper executable paths, endpoints, credentials, profile fingerprints, physical
device identifiers, screenshots, pixels, coordinates, dimensions, byte counts,
clipboard contents, raw OS errors, and exact timing series.
