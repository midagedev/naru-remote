# Physical Lock And Backlight Preflight - 2026-06-14

## Scope

This artifact records a follow-up to the physical iPhone helper-video gate
timeout. The previous long UI gate can fail late when the selected iPhone is
not interactively ready, so preflight now records safe lock/backlight labels
before launching the sustained UI test.

## Change

`scripts/run-naru-live-benchmark.sh physical-device-preflight` now emits:

- `deviceUnlockedSinceBootStatus`
- `deviceBacklightState`

The runner maps `unlockedSinceBoot=false` to
`physical-ios-device-locked`, and non-`activeOn` known backlight states to
`physical-ios-device-screen-inactive`. Both route to `unlock-physical-iphone`
before the long `physical-iphone-helper-video-gate` run.

## Limits

Apple's `devicectl device info lockState` JSON currently exposes
`result.unlockedSinceBoot`. This is useful for catching a device that has not
been unlocked after boot, but it is not treated as proof that the screen is
currently unlocked. `deviceBacklightState` is a second coarse readiness signal,
not a substitute for the final physical UI gate.

## Verification

Commands run:

```bash
bash -n scripts/run-naru-live-benchmark.sh
bash scripts/run-naru-live-benchmark.sh physical-device-id-resolution-self-test
bash scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate-self-test
scripts/run-naru-live-benchmark.sh physical-device-preflight
git diff --check -- scripts/run-naru-live-benchmark.sh artifacts/benchmarks/README.md specs/007-host-helper-video-stream/tasks.md artifacts/benchmarks/2026-06-14-physical-lock-backlight-preflight-summary.md
```

Current safe preflight labels:

- `targetDeviceClass=iPhone`
- `resolvedDeviceClass=iPhone`
- `deviceUnlockedSinceBootStatus=true`
- `deviceBacklightState=activeOn`
- `deviceDiscoveryStatus=connected`
- `buildCheckStatus=passed`
- `issueCodes=[]`
- `setupActionLabels=[]`

## Product Decision

Before rerunning the long T030 physical iPhone helper-video gate, inspect the
safe preflight JSON. If lock/backlight readiness labels produce fixed issue
codes, do not start the sustained UI test; unlock and keep the iPhone awake
first.

This does not close T030. T030 still requires a successful physical iPhone +
Mac manual verification run.

## Safety

This artifact contains only fixed labels and coarse pass/fail status. It does
not include device names, device identifiers, hostnames, IP addresses,
credentials, ports, helper paths, raw xcodebuild output, raw OS errors,
framebuffer pixels, screenshots, dimensions, coordinates, byte counts, Compose
text, clipboard contents, keysyms, or exact timings.
