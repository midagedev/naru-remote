# Physical Device Unavailable Preflight Summary

Date: 2026-06-07 KST

## Purpose

Tighten the physical iPhone readiness gate before T030/T031 evidence
collection. A paired iPhone that is known to the machine but unavailable to
Xcode should be reported as a device setup blocker, not as a generic app build
failure.

## Change

`scripts/run-naru-live-benchmark.sh physical-device-preflight` now filters
`devicectl` iPhone discovery to devices with an available developer tunnel and
available developer services, and avoids treating `xctrace` `Devices Offline`
entries as connected devices.

When a physical iPhone is present but unavailable, the runner emits fixed labels
and skips the build check:

```json
{
  "schemaVersion": 1,
  "mode": "physical-device-preflight",
  "deviceDiscoveryStatus": "unavailable",
  "deviceSelectionSource": "none",
  "codeSigningIdentityStatus": "available",
  "developmentTeamStatus": "inferred",
  "xcodeAccountStatus": "unknown",
  "provisioningProfileStatus": "unknown",
  "buildCheckStatus": "skipped",
  "issueCodes": ["physical-iphone-device-unavailable"],
  "setupActionLabels": ["unlock-connect-and-enable-developer-mode"]
}
```

## Verification

- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh physical-device-preflight`
- `NARU_PHYSICAL_IOS_DEVICE_ID=<unavailable physical iPhone> scripts/run-naru-live-benchmark.sh physical-device-preflight`
- `scripts/run-naru-live-benchmark.sh physical-team-inference-self-test`
- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness`

## Current Readiness Result

- Physical iPhone gate: blocked by `physical-iphone-device-unavailable`.
- Helper ScreenCaptureKit gate: blocked by
  `helper-video-permission-missing`.
- VNC 10fps gate: still failed in the fresh readiness run, with about 1.98
  content FPS, 504 ms average update latency, 620 ms p95 update latency, and
  first-byte wait dominating the receive path.

## Interpretation

The next manual setup action is to make the iPhone available to Xcode before
running physical sustained-session tests. This PR does not complete T030 or
T031; it prevents the gate from misrouting an unavailable-device state into a
generic build failure.

## Privacy

The artifact contains only fixed status labels, fixed issue/setup labels, and
coarse benchmark interpretation. It omits physical device names, identifiers,
serials, raw Xcode logs, provisioning identifiers, live host identity,
credentials, pixels, byte counts, exact helper timings, draft text, and IME
state.
