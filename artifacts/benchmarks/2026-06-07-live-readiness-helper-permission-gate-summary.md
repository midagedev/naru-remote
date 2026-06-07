# Live Readiness Helper Permission Gate Summary

Date: 2026-06-07

## Purpose

Record the post-Compose-hot-path live readiness state before the next helper
video implementation or manual-device gate. The goal is to avoid spending more
work on VNC request tuning when the latest benchmark shows the sustained 10fps
failure is dominated by the server/update wait rather than local app decode,
render, or UI work.

## Commands

```bash
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
scripts/run-naru-live-benchmark.sh screen-recording-watch
```

Both commands imported live target, credential, port, and helper executable
values from the environment/launchctl path and emitted privacy-safe JSON only.

## Results

`remote-desktop-10fps-readiness`:

- Overall gate: `blockedByHelperScreenCapture`.
- Primary blocked gates:
  - `helper-video-screen-capture-gate-blocked`
  - `vnc-10fps-product-gate-failed`
- Recommended primary action:
  - `grant-helper-video-app-screen-recording-permission`
- VNC 10fps product verdict: `fail`.
- VNC primary issue: `first-byte-wait-failed`.
- VNC primary constraint: `receivePath`.
- VNC server cadence status: `first-byte-wait-dominated`.
- VNC content FPS: `1.98`.
- VNC average update: `504 ms`.
- VNC p95 update: `619 ms`.
- VNC p95 first-byte wait: `616 ms`.
- VNC p95 payload read: `1 ms`.
- VNC p95 client processing: `5 ms`.
- Helper synthetic H.264: `pass`.
- Helper sustained synthetic H.264: `pass`.
- Helper ScreenCaptureKit: `fail`, `permissionBlocked`.

`screen-recording-watch`:

- Watch status: `timedOut`.
- Settings open status: `opened`.
- Final helper-video availability: `permissionMissing`.
- Permission process kind: `appBundle`.
- Permission grant hint: `grantAppBundle`.
- Post-permission change requires relaunch: `true`.
- Setup actions:
  - `grant-helper-video-app-screen-recording-permission`
  - `quit-and-relaunch-helper-after-permission-change`
  - `rerun-screen-recording-watch`

## Interpretation

The latest live evidence points away from more VNC-only client tuning:

- Sustained VNC is still around 2fps against the 10fps product gate.
- The slow phase is waiting for the next update from the VNC server.
- App-side decode/render pressure is low in this run.
- Helper-video synthetic transport is healthy and smooth.
- True helper-video capture is blocked by macOS Screen Recording permission
  for the helper app bundle.

The next practical work is therefore:

1. Grant Screen Recording to the helper app bundle on the Mac.
2. Quit/relaunch the helper after the permission change.
3. Rerun `screen-recording-watch`.
4. Run the true helper-video live capture benchmark.
5. Then run the physical iPhone helper-video gate.

## Privacy

This artifact records only fixed mode, verdict, issue, action, and aggregate
benchmark labels. It does not include host identity, credentials, ports, helper
paths, endpoints, raw errors, command text, command output, frame contents,
pixels, dimensions, coordinates, byte counts, exact helper timings, draft text,
marked text, IME state, keysyms, pointer coordinates, or physical device IDs.
