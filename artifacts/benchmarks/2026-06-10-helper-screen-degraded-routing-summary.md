# Helper Screen Degraded Routing Summary - 2026-06-10

## Scope

Keep the top-level `remote-desktop-10fps-readiness` recommendation aligned with
the helper ScreenCaptureKit probe's actual failure mode.

## Result

The readiness summary now distinguishes two helper screen capture failure
families:

- Permission blocked:
  - Screen Recording label: `missing`
  - Screen probe readiness: `permissionBlocked`
  - Recommended primary action: `run-screen-recording-watch`
- Stream degraded after permission is granted:
  - Screen Recording label: `granted`
  - Screen probe readiness: `sustainedDegraded`
  - Example stream state: `stalled`
  - Recommended primary action: `inspect-helper-video-sustained-cadence`

This fixes the operator route observed during live readiness work: a helper
ScreenCaptureKit probe can fail as `sustainedDegraded` / `stalled` even while
Screen Recording is already `granted`. That state should not send the operator
back to permission setup.

## Live Evidence

A later live `remote-desktop-10fps-readiness` run on the same machine reported:

- Overall gate: `blockedByPhysicalIPhoneGate`
- Recommended primary action: `open-xcode-account-settings`
- Helper ScreenCaptureKit verdict: `pass`
- Screen Recording label: `granted`
- Physical signing blocker: `xcode-account`
- VNC content FPS: about `1.97`
- Request/response transport FPS: about `7.16`

The live result was not currently degraded, but the self-test now permanently
covers the prior degraded shape.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh remote-desktop-readiness-summary-self-test
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

## Safety

The artifact records only fixed readiness, permission, action, and issue labels
plus aggregate FPS numbers. It does not include helper paths, host values,
credentials, device identifiers, account names, team names, raw helper or
xcodebuild logs, screenshots, pixels, byte counts, exact timings, Compose text,
marked text, keysyms, pointer coordinates, or clipboard contents.
