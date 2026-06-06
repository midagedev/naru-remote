# Helper Screen Recording Setup Summary

Date: 2026-06-07

## Scope

This run verifies a launchctl-backed helper Screen Recording setup command for
the true helper-video ScreenCaptureKit gate. The command checks helper
capability, invokes the helper's explicit permission request, opens the macOS
Screen Recording settings pane, and checks helper capability again.

No host names, passwords, ports, helper executable paths, bundle identifiers,
usernames, parent process names, endpoints, frame content, framebuffer
dimensions, byte counts, raw OS errors, helper stderr, stimulus command text,
or stimulus output are recorded here.

## Command Shape

```bash
scripts/run-naru-live-benchmark.sh screen-recording-setup
```

For automation that must not open System Settings, use:

```bash
NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip \
scripts/run-naru-live-benchmark.sh screen-recording-setup
```

The mode rejects additional arguments so the setup path remains fixed and does
not accidentally turn into a benchmark comparison.

## Result

- Setup schema: `1`.
- Mode: `screen-recording-setup`.
- Settings open status: `opened`.
- Capability before: `permissionMissing`.
- Screen Recording permission before: `missing`.
- Permission identity process kind: `appBundle`.
- Permission identity grant hint: `grantAppBundle`.
- Explicit permission request result: `notGranted`.
- Capability after: `permissionMissing`.
- Screen Recording permission after: `missing`.
- Next action label: `rerun-helper-readiness-sweep`.

Automation-only verification with `NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip`
keeps the same permission/capability labels and emits `settingsOpenStatus=skipped`.

## Interpretation

The setup command can open the relevant macOS settings pane without printing
unsafe details, but the helper app bundle still needs the user to enable Screen
Recording in System Settings and relaunch the helper. After granting permission,
rerun `scripts/run-naru-live-benchmark.sh helper-readiness-sweep`; the expected
next milestone is `canRunLiveBenchmark=true` with a passing external
ScreenCaptureKit helper-video probe.
