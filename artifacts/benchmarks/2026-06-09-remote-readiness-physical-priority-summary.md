# Remote Readiness Physical Priority Summary - 2026-06-09

## Scope

Align the top-level `remote-desktop-10fps-readiness` dashboard with the current
helper-video product path: once helper-video is ready, a physical iPhone
signing/provisioning blocker should be the primary next action even while VNC
remains below the 10fps fallback target.

## Result

The current live readiness run reports:

- Helper capability: `available`
- Screen Recording permission: `granted`
- Helper synthetic probe: `pass`
- Helper sustained synthetic probe: `pass`
- Helper ScreenCaptureKit probe: `pass`
- VNC 10fps product verdict: `fail`
- VNC content FPS: about `1.99`
- VNC first-byte wait p95: `622` ms
- VNC client processing p95: `3` ms
- Transport request/response FPS: about `7.07`
- ContinuousUpdates status: `failed-before-samples`
- Physical iPhone status: `connected`
- Physical build status: `failed`
- Physical issue codes: `xcode-account-missing`,
  `ios-provisioning-profile-missing`
- Readiness summary: `blockedByPhysicalIPhoneGate`
- Recommended primary action: `add-xcode-account`

Interpretation:

- VNC remains a fallback/control lane and is still receive/first-byte-wait
  limited on the current Apple Screen Sharing target.
- Helper-video is ready enough that the next product gate is physical iPhone
  install and sustained usability evidence.
- The immediate blocker is local Xcode account/provisioning setup, not more VNC
  renderer or decoder work.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh remote-desktop-readiness-summary-self-test
scripts/run-naru-live-benchmark.sh helper-video-live-gate-self-test
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

## Safety

The artifact records only fixed labels and aggregate FPS/timing metrics. It does
not include helper executable paths, endpoints, credentials, raw xcodebuild
logs, physical device identifiers, display dimensions, pixels, byte counts,
exact timings, Compose text, marked text, keysyms, pointer coordinates, or
clipboard contents.
