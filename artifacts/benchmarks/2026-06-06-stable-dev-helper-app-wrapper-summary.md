# Stable Dev Helper App Wrapper Summary

Date: 2026-06-06

## Scope

This run verifies a development-only app wrapper for the macOS helper so live
helper-video benchmarks can target a stable app-bundle Screen Recording
permission identity instead of the transient SwiftPM build artifact.

No host names, passwords, ports, helper executable paths, bundle identifiers,
usernames, parent process names, endpoints, frame content, framebuffer
dimensions, byte counts, raw OS errors, stimulus command text, or stimulus
output are recorded here.

## Commands

```bash
scripts/install-naru-helper-dev-app.sh --set-launchctl-env --request-permission
```

The external helper benchmark probes were rerun with live target values and
`NARU_HELPER_EXECUTABLE` sourced from `launchctl`.

## Result

- Stable dev helper wrapper installed successfully.
- `NARU_HELPER_EXECUTABLE` was set through `launchctl`.
- Helper capability schema: `2`.
- Helper permission request schema: `2`.
- Permission identity process kind: `appBundle`.
- Permission identity grant hint: `grantAppBundle`.
- Screen Recording permission remains `missing`.
- Permission request result remains `notGranted`.
- External-helper synthetic encoded probe with the stable helper wrapper:
  `pass`, `healthy`, `fast`, `smooth`, no issue codes.
- External-helper ScreenCaptureKit probe with the stable helper wrapper:
  fixed `helper-video-permission-missing` failure, as expected until
  Screen Recording is granted to the helper app bundle.

## Interpretation

The benchmark now has a stable helper app-bundle target for local Screen
Recording permission setup. The next live ScreenCaptureKit step is manual TCC
approval for the helper app bundle, followed by rerunning
`external-helper-screen-capturekit-tcp` with `NARU_HELPER_EXECUTABLE` sourced
from `launchctl`.
