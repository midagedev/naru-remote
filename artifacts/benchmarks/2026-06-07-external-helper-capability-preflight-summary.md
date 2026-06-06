# External Helper Capability Preflight Summary

Date: 2026-06-07

## Scope

This run verifies that `VNCLiveBenchmark --environment-preflight` checks the
selected external helper's safe `--video-capability` labels before running
`external-helper-screen-capturekit-tcp`. The goal is to stop at setup time when
the helper app bundle still lacks Screen Recording permission.

No host names, passwords, ports, helper executable paths, bundle identifiers,
usernames, parent process names, endpoints, frame content, framebuffer
dimensions, byte counts, raw OS errors, stimulus command text, or stimulus
output are recorded here.

## Command Shape

```bash
NARU_HELPER_EXECUTABLE="$(launchctl getenv NARU_HELPER_EXECUTABLE)" \
NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --environment-preflight \
  --visual-transport helper-video \
  --helper-video-probe external-helper-screen-capturekit-tcp \
  --json
```

## Result

- Environment preflight schema: `5`.
- Live benchmark runnable: `false`.
- Helper-video ScreenCaptureKit permission status: `missing`.
- External helper capability status: `permissionMissing`.
- Permission identity process kind: `appBundle`.
- Permission identity grant hint: `grantAppBundle`.
- Issue code: `helper-video-permission-missing`.
- Setup action: `grant-helper-video-app-screen-recording-permission`.

## Interpretation

The benchmark setup now blocks before an external ScreenCaptureKit smoke run
when the selected helper app bundle lacks Screen Recording permission. The next
manual live setup step is to grant Screen Recording to the helper app bundle,
then rerun the same preflight until it reports `run-live-gate`.
