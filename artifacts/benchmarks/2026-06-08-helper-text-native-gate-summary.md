# Helper Text Native Gate Summary — 2026-06-08

## Trigger

`helper-text-permission-watch` proved that the stable helper app bundle can be
reachable as a process identity while still missing the macOS permissions needed
for Compose native insertion. After automatic Compose requests were narrowed to
`nativeInsert`, the iPhone app must not send raw Compose text to a helper that
only advertises pasteboard fallback or has no native insert route.

## Change

The app now treats helper capability as part of the Compose route gate:

- A helper state with no capability summary remains compatible with older
  in-process test wiring.
- A helper state with a capability summary routes automatic Compose through the
  helper only when native insert is known available.
- Known missing `nativeInsert`, missing Accessibility value insert, and missing
  Unicode keyboard event support are reported as `helper.permissionMissing`
  before the helper receives the Compose payload.
- The input status line now names the actionable Mac permission family:
  Accessibility or Input Monitoring.

## Verification

```bash
swift test --filter HelperTextBridgeTests \
  --filter NaruRemoteAppSnapshotTests/testInputHelperStatusNamesMissingMacTextPermissions \
  --filter NaruRemoteAppModelTests/testReachableHelperWithoutNativeInsertPermissionDoesNotReceiveComposePayload \
  --filter NaruRemoteAppModelTests/testStoredHelperReachableButNativeInsertMissingBlocksComposeBeforePayloadSend
```

The focused app-model tests cover both active helper injection and stored
network helper transport. In both cases, known missing native insert capability
keeps raw Compose text out of the helper insert request path and records the
fixed `helper.permissionMissing` state.

The live helper permission watch still reports the stable helper app bundle as
permission-blocked:

```bash
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
  NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
  scripts/run-naru-live-benchmark.sh helper-text-permission-watch
```

Observed fixed labels:

- `watchStatus`: `timedOut`
- `finalAvailability`: `permissionMissing`
- `finalAccessibilityValueInsert`: `missing`
- `finalUnicodeKeyboardEvent`: `missing`
- `finalPasteboardFallback`: `missing`
- `issueCodes`: `helper-text-permission-missing`

## Next Physical Gate

Grant the stable helper app either Accessibility or Input Monitoring permission,
relaunch the helper, rerun:

```bash
scripts/run-naru-live-benchmark.sh helper-text-permission-watch
```

Then retry physical iPhone Compose native insertion and export diagnostics to
confirm `nativeInsert` is available and `latestInjectionHelperStrategy` is
`nativeInsert`.
