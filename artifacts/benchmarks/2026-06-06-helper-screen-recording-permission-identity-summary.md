# Helper Screen Recording Permission Identity Summary

Date: 2026-06-06

## Scope

This run verifies that the helper Screen Recording setup diagnostics now explain
which fixed permission identity class is being checked without recording local
paths or user/device identifiers. It targets the current development helper
binary used by live benchmark setup.

No host names, passwords, ports, helper executable paths, bundle identifiers,
usernames, parent process names, endpoints, frame content, framebuffer
dimensions, byte counts, raw OS errors, stimulus command text, or stimulus
output are recorded here.

## Commands

```bash
swift build --product NaruHelper
.build/debug/NaruHelper --video-capability
.build/debug/NaruHelper --video-request-screen-recording-permission
```

The existing env-backed external helper preflight/smoke commands were also
rerun with live target values sourced from `launchctl` environment variables.
The command output was inspected only through fixed labels.

## Result

- `--video-capability` schema: `2`.
- `--video-request-screen-recording-permission` schema: `2`.
- Screen Recording permission: `missing`.
- Permission request result: `notGranted`.
- Permission identity process kind: `swiftPMBuildArtifact`.
- Permission identity grant hint: `useStableHelperExecutable`.
- Capture API label: `screenCaptureKit`.
- Safe failure code: `helperVideo.permissionMissing`.
- External-helper benchmark preflight remains runnable with schema `4`,
  `delegatedToHelper`, no setup issue codes, and setup action `run-live-gate`.
- External-helper ScreenCaptureKit smoke still fails safely through
  `visualTransportComparison.helperVideoReports[0]` with fixed issue code
  `helper-video-permission-missing` and no unsafe raw fields.

## Interpretation

The current helper is still missing macOS Screen Recording permission, and the
new fixed identity labels show that the checked process is a SwiftPM build
artifact. Repeated live helper-video benchmarks should move to a stable helper
executable or app bundle before requesting Screen Recording permission, so TCC
approval is tied to the helper process that will actually capture frames.
