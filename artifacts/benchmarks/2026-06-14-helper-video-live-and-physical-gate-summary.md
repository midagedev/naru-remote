# Helper Video Live And Physical Gate Handoff - 2026-06-14

## Scope

Continue the `PRODUCT_QUALITY_TARGETS.md` helper-video promotion path without
repeating older VNC receive-path experiments.

This run checks the current state after Paperclip was removed from the local
Naru workflow:

- whether the true ScreenCaptureKit helper-video path is ready for physical
  iPhone validation;
- whether the physical iPhone helper-video gate can run now;
- whether the connected iPad is being used accidentally for the iPhone-first
  gate.

## Commands

The local benchmark shell used environment-sourced live credentials only. Raw
credential values, endpoints, device identifiers, helper executable paths,
frame payloads, byte counts, dimensions, screenshots, and xcodebuild logs are
not recorded here.

```bash
scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

```bash
NARU_PHYSICAL_E2E_SUSTAINED_SECONDS=60 \
NARU_PHYSICAL_E2E_STREAM_POWER_MODE=balanced \
NARU_PHYSICAL_E2E_STREAM_ENCODING_MODE=local-low-latency-rgb565 \
NARU_PHYSICAL_E2E_STARTUP_PREFLIGHT_MODE=one-hidden-frame \
NARU_PHYSICAL_E2E_STARTUP_GLANCE_SCALE_MODE=glance-025 \
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate
```

Before the physical run, the local Xcode development team environment was
aligned with the generated Xcode project's signing team. This is benchmark
environment hygiene only; no Paperclip service or repo-local Paperclip config
is required.

## Results

### Helper Video Live Gate

Result: passed through the Mac-side helper-video path and routed to the physical
iPhone gate.

Safe labels:

- `overallGateState=readyForPhysicalIPhoneGate`
- `recommendedPrimaryAction=run-physical-iphone-helper-video-gate`
- `screenRecordingGate.finalPermissionStatus=granted`
- `helperVideoGate.syntheticVerdict=pass`
- `helperVideoGate.sustainedSyntheticVerdict=pass`
- `helperVideoGate.screenCaptureVerdict=pass`
- `helperVideoGate.sustainedScreenCaptureVerdict=pass`
- `helperVideoGate.sustainedScreenCaptureReadinessState=readyForPhysicalGate`
- `appBootstrapGate.status=passed`
- `appBootstrapGate.requestedFrameCount=30`
- `physicalIPhoneGate.buildCheckStatus=passed`

This satisfies the remaining T031 shape: a true live helper-video access-unit
benchmark after the helper sender/listener is connected to the iOS/app decode
path. The passed app bootstrap path is
`screen-capturekit -> helper TCP -> app model -> H.264 sample-buffer factory`.

### Physical iPhone Helper-Video Gate

Result: failed before promotion evidence was collected.

Safe labels:

- `status=failed`
- `xcodebuildTestStatus=timedOut`
- `physicalDevicePreflight.deviceDiscoveryStatus=connected`
- `physicalDevicePreflight.xcodeAccountStatus=available`
- `physicalDevicePreflight.provisioningProfileStatus=available`
- `physicalDevicePreflight.buildCheckStatus=passed`
- `diagnosticExportSummary.status=missing`
- `pipEvidenceSummary.status=missing`
- `issueCodes=[physical-iphone-helper-video-gate-timed-out, physical-ios-device-locked]`
- `setupActionLabels=[inspect-physical-iphone-gate-timeout, unlock-physical-iphone]`

Safe device inventory check showed one connected iPad and one connected iPhone.
The physical helper-video gate was not using the iPad: it is the iPhone-first
gate and the runner targets the physical iPhone selection, rejecting iPad-only
availability.

## Product Decision

Do not repeat the VNC 10fps, ContinuousUpdates, request-pipeline, or viewport
interaction traces for this promotion path. Those are already closed by the
NAR-5 receive-path triage: VNC remains the control/input/fallback path, and
helper-video is the smooth visual-primary candidate.

Do not repeat `helper-video-live-gate` unless code, helper permission, helper
executable identity, or benchmark environment changes. The current Mac-side
helper-video path is ready for physical iPhone validation.

The next useful action is only:

1. unlock and keep awake the selected physical iPhone;
2. rerun `scripts/run-naru-live-benchmark.sh physical-device-preflight`;
3. rerun `scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate`;
4. if it passes, record T030 physical iPhone + Mac manual verification evidence.

### Follow-Up: Device-Class Labeling

After the physical run, the runner was tightened so `physical-device-preflight`
prints fixed `targetDeviceClass` and `resolvedDeviceClass` labels. A current
safe preflight run reports both as `iPhone`, with signing, Xcode account,
provisioning, and build-check labels still passing. This means the next T030
attempt should diagnose any iPad/iPhone confusion from the preflight JSON
instead of rerunning broader device inventory experiments.

The `physical-iphone-helper-video-gate` mode now also forces its nested
preflight to the iPhone target class and blocks explicit non-iPhone class
configuration with the fixed `physical-iphone-target-class-required` label. A
future iPad sustained gate should use a separate mode rather than reusing the
iPhone promotion gate.

Regression coverage:

- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh physical-device-id-resolution-self-test`
- `scripts/run-naru-live-benchmark.sh physical-signing-setup-summary-self-test`
- `scripts/run-naru-live-benchmark.sh physical-device-preflight`

## Status Against Targets

- T031: complete by current evidence.
- T030: incomplete; blocked by physical iPhone timeout/locked state, not by
  helper-video Screen Recording, helper-video decode, Xcode account, or
  provisioning.
- Product Green: not achieved. Physical iPhone helper-video/input evidence is
  still missing.

## Safety

This artifact contains only fixed labels and coarse counts. It does not include
hostnames, IP addresses, credentials, ports, helper paths, device identifiers,
raw xcodebuild output, raw OS errors, helper endpoints, pairing material,
framebuffer pixels, screenshots, dimensions, coordinates, byte counts, Compose
text, clipboard contents, keysyms, or exact per-frame timings.
