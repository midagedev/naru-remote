# Physical Device Class Preflight Guard - 2026-06-14

## Scope

This artifact records a narrow T030/T031 gate hygiene improvement: physical
iPhone promotion runs should prove the selected device class from privacy-safe
JSON labels, not from raw device names, IDs, or a separate inventory check.

## Change

`scripts/run-naru-live-benchmark.sh physical-device-preflight` now emits fixed
device-class labels:

- `targetDeviceClass`
- `resolvedDeviceClass`

The physical iPhone helper-video gate also forces its nested preflight target
to `iPhone` and blocks explicit non-iPhone class configuration with the fixed
`physical-iphone-target-class-required` issue code.

## Verification

Commands run:

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh physical-device-id-resolution-self-test
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate-self-test
scripts/run-naru-live-benchmark.sh physical-device-preflight
git diff --check -- scripts/run-naru-live-benchmark.sh artifacts/benchmarks/README.md specs/007-host-helper-video-stream/tasks.md artifacts/benchmarks/2026-06-14-physical-device-class-preflight-guard-summary.md
```

Current safe preflight labels:

- `targetDeviceClass=iPhone`
- `resolvedDeviceClass=iPhone`
- `deviceDiscoveryStatus=connected`
- `buildCheckStatus=passed`
- `issueCodes=[]`
- `setupActionLabels=[]`

## Product Decision

Do not repeat broad physical device inventory checks just to answer whether the
iPhone-first gate is accidentally using an iPad. Inspect `targetDeviceClass`
and `resolvedDeviceClass` in the safe preflight JSON first.

This does not close T030. T030 still requires a successful physical iPhone +
Mac manual verification run.

## Safety

This artifact contains only fixed labels and coarse pass/fail status. It does
not include device names, device identifiers, hostnames, IP addresses,
credentials, ports, helper paths, raw xcodebuild output, raw OS errors,
framebuffer pixels, screenshots, dimensions, coordinates, byte counts, Compose
text, clipboard contents, keysyms, or exact timings.
