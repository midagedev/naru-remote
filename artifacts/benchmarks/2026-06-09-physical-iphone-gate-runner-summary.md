# Physical iPhone Gate Runner Summary - 2026-06-09

## Scope

Add a launchctl-aware physical iPhone sustained UI/input gate runner:

```bash
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate-self-test
```

The runner is the handoff after Mac-side helper-video readiness passes. It keeps
host/password values in environment only, requires sustained candidate labels
explicitly, runs `physical-device-preflight`, and only then launches
`PhysicalDeviceConnectE2EUITests/testPhysicalDeviceSustainedCandidateGate` on the
selected physical iPhone.

## Current Local Result

With the current live host/password and these explicit candidate labels:

```bash
NARU_PHYSICAL_E2E_SUSTAINED_SECONDS=600
NARU_PHYSICAL_E2E_STREAM_POWER_MODE=balanced
NARU_PHYSICAL_E2E_STREAM_ENCODING_MODE=local-low-latency-rgb565
NARU_PHYSICAL_E2E_STARTUP_PREFLIGHT_MODE=one-hidden-frame
NARU_PHYSICAL_E2E_STARTUP_GLANCE_SCALE_MODE=glance-025
```

the runner reports:

- `status=blocked`
- `xcodebuildTestStatus=notRun`
- `candidateLabels.durationLabel=ten-minutes`
- `candidateLabels.streamEncodingMode=local-low-latency-rgb565`
- `candidateLabels.startupGlanceScaleMode=glance-025`
- `physicalDevicePreflight.deviceDiscoveryStatus=connected`
- `physicalDevicePreflight.codeSigningIdentityStatus=available`
- `physicalDevicePreflight.xcodeAccountStatus=missing`
- `physicalDevicePreflight.provisioningProfileStatus=missing`
- `issueCodes=["xcode-account-missing","ios-provisioning-profile-missing"]`
- `setupActionLabels=["add-xcode-account","create-ios-development-provisioning-profile"]`

## Interpretation

The physical iPhone selection and code-signing certificate are visible, and the
live VNC target credentials are available through the environment. The sustained
UI/input gate still cannot install/run because Xcode has no usable account and
development provisioning profile for this app target. Once those are fixed, the
same command should launch the physical iPhone test and summarize the final safe
`sustainedSessionAssessment` labels.

## Verification

- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate-self-test`
- `scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate` with the
  explicit candidate labels above
