# 2026-06-07 Helper-Video Primary Readiness Summary

Command:

```sh
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

Result:

- Overall gate: `blockedByHelperScreenCapture`
- Recommended primary action: `grant-helper-video-app-screen-recording-permission`
- Physical iPhone discovery: `connected`
- Physical build gate: `xcode-account-missing`, `ios-provisioning-profile-missing`
- Helper-video synthetic probe: `pass`
- Helper-video sustained synthetic probe: `pass`
- Helper-video ScreenCaptureKit probe: `fail`
- Helper-video Screen Recording permission: `missing`
- VNC 10fps product verdict: `fail`
- VNC content FPS: about `1.99`
- VNC average update: about `502 ms`
- VNC p95 update: about `632 ms`
- VNC p95 first-byte wait: about `624 ms`
- VNC p95 client processing: about `14 ms`
- VNC primary constraint: `receivePath`
- VNC primary issue: `first-byte-wait-failed`

Interpretation:

The live VNC path remains below the iPhone 10fps product target because frame
arrival is first-byte-wait dominated, not because local client processing or
renderer upload is the primary bottleneck. The helper-video synthetic and
sustained synthetic H.264 paths are healthy, so the product architecture should
promote helper-video to the foreground visual candidate while keeping VNC as the
control/input/fallback lane. True ScreenCaptureKit helper-video verification is
still blocked by macOS Screen Recording permission for the helper app bundle.

Post-change smoke:

- `scripts/run-naru-live-benchmark.sh helper-sustained-synthetic-probe`:
  `verdict=pass`, `streamState=healthy`, `sustainedUpdateBand=smooth`,
  `readinessState=readyForPhysicalGate`
- `scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark`:
  `status=skipped`, `sourceMode=screen-capturekit`,
  `transportPath=helper-tcp-to-app-model`, `decodePath=h264-sample-buffer-factory`,
  `issueCodes=["screen-capturekit-app-bootstrap-skipped"]`,
  `setupActionLabels=["grant-screen-recording-to-benchmark-host",
  "rerun-helper-screen-app-bootstrap-benchmark"]`

Privacy:

This summary contains only fixed gate labels and aggregate/bucketed timing
values. It does not include hostnames, endpoints, credentials, helper paths,
device IDs, pixels, dimensions, byte counts, exact per-frame timings, raw OS
errors, Compose text, keysyms, marked text, or clipboard contents.
