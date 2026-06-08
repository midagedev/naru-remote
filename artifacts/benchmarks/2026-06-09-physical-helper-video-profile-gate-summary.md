# Physical Helper-Video Profile Gate Summary - 2026-06-09

## Scope

This slice makes `physical-iphone-helper-video-gate` prove that the iOS app is
launched with a helper-video configured profile before any sustained iPhone
FPS, thermal, input, or hand-feel evidence can be promoted.

## Changes

- The XCUITest seed profile hook accepts helper-video pairing fields and builds
  `ConnectionProfile.helperVideo`.
- The app launch keychain hook writes both the VNC password and helper-video
  token when their test environment references are present.
- `PhysicalDeviceConnectE2EUITests` forwards physical helper-video pairing into
  the target app and fails partial pairing instead of silently using VNC only.
- `physical-iphone-helper-video-gate` requires helper-video pairing, imports the
  existing Mac-side `NARU_HELPER_VIDEO_TOKEN` /
  `NARU_HELPER_VIDEO_PROFILE_FINGERPRINT` as fallbacks, and reports only the
  safe `candidateLabels.helperVideoProfileMode` label.

## Verification

- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate-self-test`
- `git diff --check`
- `swift test`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' -only-testing:NaruRemoteUITests/NaruRemoteLaunchUITests/testLaunchEnvironmentSeedProfileCanEnableHelperVideo test`

## Current Live Runner Result

With the 10 minute candidate labels set locally, the privacy-safe live runner
currently reports:

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
    "helperVideoProfileMode": "missing",
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
    "physical-e2e-helper-video-pairing-missing",
    "xcode-account-missing",
    "ios-provisioning-profile-missing"
  ],
  "setupActionLabels": [
    "set-physical-e2e-helper-video-pairing",
    "add-xcode-account",
    "create-ios-development-provisioning-profile"
  ]
}
```

No host, password, helper token, pairing fingerprint, device identifier, raw
xcodebuild log, screenshot, pixels, exact timings, or input payload appears in
the report.
