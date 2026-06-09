# Helper Text Dev App Setup Summary

Date: 2026-06-09 KST

This slice adds a text-permission setup gate for the stable development helper
app wrapper. The goal is to avoid testing `nativeInsert` against an ambiguous
CLI helper identity and instead make macOS permission setup point at
`NaruHelperDev.app`.

## Change

- Added `--request-text-permission` to `scripts/install-naru-helper-dev-app.sh`.
- Added `scripts/run-naru-live-benchmark.sh helper-text-dev-app-setup`.
- The setup gate installs the dev helper app, sets launchctl
  `NARU_HELPER_EXECUTABLE`, requests helper text insertion permission, checks
  text capability again, and emits only fixed setup/status labels.

## Verification

Passed:

```bash
bash -n scripts/install-naru-helper-dev-app.sh
bash -n scripts/run-naru-live-benchmark.sh
scripts/install-naru-helper-dev-app.sh --help
```

Live local setup gate:

```bash
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
  scripts/run-naru-live-benchmark.sh helper-text-dev-app-setup
```

Result:

- `installStatus`: `passed`
- `codeSigningStatus`: `appleDevelopment`
- `launchctlEnvStatus`: `set`
- `helperProcessKind`: `appBundle`
- `permissionGrantHint`: `grantAppBundle`
- `permissionRequestResult`: `notGranted`
- `finalAvailability`: `permissionMissing`
- `finalAccessibilityValueInsert`: `missing`
- `finalUnicodeKeyboardEvent`: `missing`

Follow-up observed probe through the launchctl helper executable still reports:

- `safeFailureCode`: `helper.permissionMissing`
- `observationStatus`: `no-input`

Interpretation:

- The helper permission target is now the stable app bundle, not the raw SwiftPM
  CLI binary.
- Native text insertion is still blocked until the user grants Accessibility or
  event-posting permission to `NaruHelperDev`, relaunches the helper, and reruns
  `helper-text-dev-app-setup` plus `helper-text-observed-probe`.

Safety:

- The setup gate does not emit helper executable paths, app paths, team
  identifiers, signing identities, raw install logs, endpoints, credentials,
  text payloads, clipboard bytes, raw OS errors, or exact timings.
