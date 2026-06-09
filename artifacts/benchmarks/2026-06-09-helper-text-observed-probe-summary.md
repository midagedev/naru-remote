# Helper Text Observed Probe Summary

Date: 2026-06-09 KST

This slice adds `scripts/run-naru-live-benchmark.sh helper-text-observed-probe`,
which launches the controlled local AppKit text target and then asks the
selected helper to insert the fixed `unicode-hangul` payload using
`nativeInsert` only. The report separates helper capability, helper insert
response, and target observation so a helper-side `sent` response cannot be
mistaken for actual focused-editor insertion.

## Verification

Passed:

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh helper-text-observed-probe-self-test
swift build --product NaruHelper
swift build --product VNCLiveStimulusWindow
```

Live local probe:

```bash
NARU_HELPER_EXECUTABLE="$PWD/.build/debug/NaruHelper" \
  NARU_HELPER_TEXT_OBSERVED_PROBE_DURATION_SECONDS=3 \
  scripts/run-naru-live-benchmark.sh helper-text-observed-probe
```

Result:

- `status`: `failed`
- `payload`: `unicode-hangul`
- `strategyPreference`: `nativeInsert`
- `capabilityAvailability`: `permissionMissing`
- `accessibilityValueInsert`: `missing`
- `unicodeKeyboardEvent`: `missing`
- `insertStatus`: `failed`
- `safeFailureCode`: `helper.permissionMissing`
- `observationStatus`: `no-input`
- `failureLabel`: `helper.permissionMissing`

Interpretation:

- The controlled local AppKit target became ready.
- The active helper binary does not currently have macOS text insertion
  permission, so native insert was not attempted successfully.
- Because the target reported `no-input`, this does not yet verify helper
  nativeInsert as a usable Compose path.

Next actions:

- Grant Accessibility or event-posting permission to the active helper binary,
  relaunch it, and rerun `helper-text-observed-probe`.
- Only promote helper nativeInsert confidence after the same probe reports
  `status: observed-inserted` with `observationStatus: matched`.

Safety:

- The report emits fixed payload, capability, insert, observation, issue, and
  action labels only.
- It does not emit raw Compose text, helper paths, target paths, endpoints,
  credentials, focused app titles, clipboard bytes, pixels, raw OS errors, or
  exact timings.
