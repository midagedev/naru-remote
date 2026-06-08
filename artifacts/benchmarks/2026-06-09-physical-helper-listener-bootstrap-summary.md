# Physical Helper Listener Bootstrap Summary - 2026-06-09

## Scope

This artifact records the next physical iPhone gate hardening step after the
helper-video seeded profile gate: `physical-iphone-helper-video-gate` now owns
helper-video pairing and listener lifecycle setup by default.

## Changes

- Added `NARU_PHYSICAL_E2E_HELPER_VIDEO_LISTENER_MODE=auto|manual`.
- Default `auto` mode generates ephemeral helper-video pairing and reports only
  `helperVideoProfileMode=generated`.
- Default `auto` mode starts the selected `NARU_HELPER_EXECUTABLE` as
  `NaruHelper --video-listen --video-source screen-capturekit` on port `5975`.
- Helper token/fingerprint are passed by environment-variable indirection and
  are never printed.
- Helper stdout/stderr are captured only in a temporary file and are removed at
  the end of the run.
- `manual` mode remains available for a pre-running, externally managed helper
  listener with explicit pairing.
- The self-test now includes a fake helper listener lifecycle case so the runner
  proves start/stop cleanup without invoking xcodebuild.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate-self-test
```

The self-test completed with:

```json
{
  "schemaVersion": 1,
  "mode": "physical-iphone-helper-video-gate-self-test",
  "status": "passed",
  "configurationMissingCase": "passed",
  "liveFallbackCase": "passed",
  "portValidationCase": "passed",
  "configurationValidCase": "passed",
  "listenerLifecycleCase": "passed",
  "diagnosticSummaryCase": "passed"
}
```

With the 10 minute physical candidate labels set locally, the live runner now
gets past helper-video pairing setup and remains blocked only by local Xcode
account/provisioning setup:

```json
{
  "schemaVersion": 1,
  "mode": "physical-iphone-helper-video-gate",
  "status": "blocked",
  "xcodebuildTestStatus": "notRun",
  "candidateLabels": {
    "targetLabel": "iphone-sustained-usability-v2",
    "durationLabel": "ten-minutes",
    "streamPowerMode": "balanced",
    "streamEncodingMode": "local-low-latency-rgb565",
    "startupPreflightMode": "one-hidden-frame",
    "startupGlanceScaleMode": "glance-025",
    "helperVideoProfileMode": "generated",
    "helperVideoListenerMode": "auto",
    "composePayloadClass": "default-ascii"
  },
  "physicalDevicePreflight": {
    "deviceDiscoveryStatus": "connected",
    "deviceSelectionSource": "environment",
    "deviceIDResolutionStatus": "environmentXcodebuildUDID",
    "codeSigningIdentityStatus": "available",
    "developmentTeamStatus": "environment",
    "xcodeAccountStatus": "missing",
    "provisioningProfileStatus": "missing",
    "buildCheckStatus": "failed",
    "issueCodes": [
      "xcode-account-missing",
      "ios-provisioning-profile-missing"
    ]
  },
  "issueCodes": [
    "xcode-account-missing",
    "ios-provisioning-profile-missing"
  ],
  "setupActionLabels": [
    "add-xcode-account",
    "create-ios-development-provisioning-profile"
  ]
}
```

## Privacy Boundary

This artifact intentionally excludes host values, passwords, helper tokens,
pairing fingerprints, helper executable paths, raw xcodebuild/helper logs,
physical device identifiers, screenshots, pixels, exact timings, byte counts,
pointer coordinates, keysyms, marked text, and Compose payloads.
