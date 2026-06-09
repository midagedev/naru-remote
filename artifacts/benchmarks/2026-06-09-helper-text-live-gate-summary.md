# Helper Text Live Gate Summary

Date: 2026-06-09 KST

This slice adds `scripts/run-naru-live-benchmark.sh helper-text-live-gate`, a
single privacy-safe gate for the current Compose insertion bottleneck. It runs:

1. `helper-text-dev-app-setup`
2. `helper-text-permission-watch`
3. `helper-text-observed-probe`

The resulting `liveGateSummary` prevents three common false conclusions:

- installed helper app does not mean text insertion permission is granted;
- helper capability `nativeInsert` does not mean the focused editor inserted
  text;
- a physical iPhone Compose gate should not run until the controlled local
  target reports `matched`.

## Verification

Passed:

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh helper-text-live-gate-summary-self-test
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
  NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
  NARU_HELPER_TEXT_PERMISSION_WATCH_INTERVAL_SECONDS=0 \
  NARU_HELPER_TEXT_OBSERVED_PROBE_DURATION_SECONDS=1 \
  scripts/run-naru-live-benchmark.sh helper-text-live-gate |
  jq -e '.mode == "helper-text-live-gate" and .liveGateSummary.overallGateState == "blockedByHelperTextPermission"'
```

Live local gate result:

- setup `installStatus`: `passed`
- setup `helperProcessKind`: `appBundle`
- setup `permissionGrantHint`: `grantAppBundle`
- permission watch `watchStatus`: `timedOut`
- permission watch `finalAvailability`: `permissionMissing`
- observed probe `status`: `failed`
- observed probe `safeFailureCode`: `helper.permissionMissing`
- observed probe `observationStatus`: `no-input`
- summary `overallGateState`: `blockedByHelperTextPermission`
- summary `recommendedPrimaryAction`:
  `grant-helper-text-accessibility-or-input-monitoring-permission`

## Interpretation

The development helper app identity is correct, but macOS still has not granted
the helper a native text insertion route. After granting Accessibility or
event-posting permission to `NaruHelperDev` and relaunching the helper, rerun
`helper-text-live-gate`. Only `readyForPhysicalComposeGate` should trigger a
physical iPhone Compose nativeInsert verification run.

## Safety

The live gate emits fixed setup, permission, observation, summary, issue, and
action labels only. It does not emit helper paths, app paths, endpoints,
credentials, text payloads, clipboard bytes, focused app titles, raw OS errors,
pixels, byte counts, or exact timings.
