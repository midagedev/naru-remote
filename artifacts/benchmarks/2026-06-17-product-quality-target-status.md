# Product Quality Target Status - 2026-06-17

## Scope

This artifact maps the current implementation evidence to
`PRODUCT_QUALITY_TARGETS.md` so the next iteration does not repeat experiments
whose result is already known.

This is not a Green product claim, PR-ready performance claim, physical iPhone
pass, thermal pass, or default-promotion claim. It is a checkpoint for the
remaining release gates.

## Current Overall Verdict

Current state: `Amber / blocked`

Reason:

- Mac-side helper-video is ready for physical iPhone promotion.
- Helper-native text insertion is ready for physical Compose promotion.
- iPhone device discovery is now connected.
- Physical app install/signing is blocked by Xcode account / exact iOS
  development provisioning.
- VNC visual path remains below the 10 content FPS product gate and should stay
  classified as control/input/fallback unless a future VNC gate passes.

## Latest Commands

```bash
NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip \
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
NARU_HELPER_TEXT_PERMISSION_WATCH_INTERVAL_SECONDS=0 \
  scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness

NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip \
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
NARU_HELPER_TEXT_PERMISSION_WATCH_INTERVAL_SECONDS=0 \
  scripts/run-naru-live-benchmark.sh helper-video-live-gate

NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
NARU_HELPER_TEXT_PERMISSION_WATCH_INTERVAL_SECONDS=0 \
  scripts/run-naru-live-benchmark.sh helper-text-live-gate
```

Logs:

```text
/tmp/naru-remote-desktop-10fps-readiness-20260617-quality-status.log
/tmp/naru-helper-video-live-gate-20260617-quality-status.log
/tmp/naru-helper-text-live-gate-20260617-quality-status.log
```

## Release Gate Checklist Snapshot

| Gate | Current status | Evidence |
| --- | --- | --- |
| iPhone physical gate | Blocked | iPhone is connected, but `buildCheckStatus=failed`, `xcodeAccountStatus=missing`, and `provisioningProfileStatus=missing`. |
| iPad simulator/device smoke | Simulator pass, device not promoted | `simulator-input-viewport-gate` passed for iPhone and iPad simulators. |
| VNC/helper visual gate | Helper ready, VNC fail | Helper synthetic, sustained synthetic, ScreenCaptureKit, and sustained ScreenCaptureKit all pass. VNC reports `contentFramesPerSecond=1.9808517662594916` and `productVerdict=fail`. |
| Helper video screen/app bootstrap | Pass | `helper-video-live-gate` reports Screen Recording `granted`, ScreenCaptureKit helper-video `readyForPhysicalGate`, and app bootstrap `status=passed` for `30` requested displayable frames. |
| Compose unicode observed insertion | Mac-side pass, physical pending | `helper-text-live-gate` reports `readyForPhysicalComposeGate`, `nativeInsertReady=true`, `observedProbeStatus=observed-inserted`, and `observationStatus=matched`. |
| Direct key and trackpad focused tests | Simulator/regression pass | Focused unit tests and `simulator-input-viewport-gate` pass; VNC KeyEvent observed-delivery remains `no-input` and is not promoted. |
| Light/dark screenshot audit | Existing artifact present, not refreshed in this run | UX screenshot artifacts exist in the worktree; no new visual review was claimed here. |
| 30-minute sustained iPhone manual log | Missing | Requires successful physical app install and manual/device sustained run. |
| Diagnostic export privacy tests | Pass for selected non-physical slice | 2026-06-17 security/privacy review and non-physical foundation slice passed selected diagnostic/report privacy tests. |

## Key Current Measurements

### Visual Stream

`remote-desktop-10fps-readiness`:

- `overallGateState=blockedByPhysicalIPhoneGate`
- `primaryBlockedGateLabels=[physical-iphone-gate-blocked, vnc-10fps-product-gate-failed]`
- `recommendedPrimaryAction=open-xcode-account-settings`
- Helper video:
  - `syntheticVerdict=pass`
  - `sustainedSyntheticVerdict=pass`
  - `screenCaptureVerdict=pass`
  - `sustainedScreenCaptureVerdict=pass`
  - `screenRecordingPermission=granted`
- VNC:
  - `wrapperStatus=passed`
  - `productVerdict=fail`
  - `primaryIssueCode=first-byte-wait-failed`
  - `primaryConstraint=receivePath`
  - `serverCadenceStatus=first-byte-wait-dominated`
  - `contentFramesPerSecond=1.9808517662594916`
  - `averageUpdateMilliseconds=484`
  - `p95UpdateMilliseconds=629`
  - `firstByteWaitP95Milliseconds=628`
  - `payloadReadP95Milliseconds=0`
  - `clientProcessingP95Milliseconds=2`
- Transport cadence drilldown:
  - request/response reaches `6.873136800264988` content FPS but still fails
    the product target.
  - ContinuousUpdates fails before samples with
    `stream-continuous-updates-continuous-updates-not-confirmed`.

Interpretation:

- The smooth visual path should remain helper-video primary.
- The current VNC blocker is server/receive cadence, not client decode or
  renderer upload.
- Do not repeat VNC ContinuousUpdates experiments for the current Mac Screen
  Sharing target unless the server or transport configuration changes.

### Helper Video

`helper-video-live-gate`:

- `overallGateState=blockedByPhysicalIPhoneGate`
- `recommendedPrimaryAction=open-xcode-account-settings`
- `screenRecordingGate.watchStatus=granted`
- `screenRecordingGate.finalAvailability=available`
- `helperVideoGate.syntheticVerdict=pass`
- `helperVideoGate.sustainedSyntheticVerdict=pass`
- `helperVideoGate.screenCaptureVerdict=pass`
- `helperVideoGate.sustainedScreenCaptureVerdict=pass`
- `appBootstrapGate.status=passed`
- `appBootstrapGate.sourceMode=screen-capturekit`
- `appBootstrapGate.transportPath=helper-tcp-to-app-model`
- `appBootstrapGate.decodePath=h264-sample-buffer-factory`
- `appBootstrapGate.requestedFrameCount=30`

Interpretation:

- Mac-side helper-video readiness does not need to be repeated for the current
  blocker.
- The next helper-video evidence must come from the physical iPhone gate after
  signing/provisioning is fixed.

### Compose / Text Input

`helper-text-live-gate`:

- `overallGateState=readyForPhysicalComposeGate`
- `recommendedPrimaryAction=run-physical-iphone-compose-native-insert-gate`
- `nativeInsertReady=true`
- `observedProbeStatus=observed-inserted`
- `observationStatus=matched`
- `observedSafeFailureCode=none`

Interpretation:

- Helper-native text insertion is the preferred Compose delivery path.
- VNC KeyEvent fallback remains unpromoted because the observed fallback probe
  reports `no-input` even for ASCII.
- The next input evidence must be physical iPhone Compose native insertion
  once the app can install on the device.

### Physical iPhone

Physical signing state:

- `deviceDiscoveryStatus=connected`
- `resolvedDeviceClass=iPhone`
- `codeSigningIdentityStatus=available`
- `developmentTeamStatus=environment`
- `xcodeAccountStatus=missing`
- `provisioningProfileStatus=missing`
- `buildCheckStatus=failed`
- `primaryBlockedGateLabel=xcode-account`
- `recommendedPrimaryAction=open-xcode-account-settings`
- `issueCodes=[xcode-account-missing, ios-provisioning-profile-missing]`

Companion provisioning inventory:

- `bundleExactMatchCount=0`
- `bundleWildcardMatchCount=7`
- `exactDevelopmentProfileCount=0`
- `wildcardDevelopmentProfileCount=7`
- `primaryBlockedGateLabel=ios-exact-provisioning-profile`

Interpretation:

- The current physical blocker is not device connection, stale target class,
  helper-video readiness, helper text permission, or VNC receive-path.
- The next operator action is Xcode account access for automatic signing or an
  exact app development profile for this app bundle.

## Do Not Repeat Until State Changes

- Do not rerun iPhone/iPad device-selection experiments for the current
  physical blocker.
- Do not rerun VNC ContinuousUpdates promotion experiments against the same Mac
  Screen Sharing server state.
- Do not rerun Mac-side helper-video readiness as a substitute for physical
  iPhone promotion.
- Do not rerun helper text permission setup as a substitute for physical
  Compose verification.
- Do not create a PR from this checkpoint alone; it records evidence and
  blocker state, not a measured product improvement.

## Next Useful Work

When signing/provisioning changes:

```bash
scripts/run-naru-live-benchmark.sh physical-device-preflight
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate
```

When code touches input, viewport, frame pacing, helper-video rendering, or
test storm hooks:

```bash
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

When helper-video code or helper permissions change:

```bash
NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip \
  scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

When helper text routing or permissions change:

```bash
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
NARU_HELPER_TEXT_PERMISSION_WATCH_INTERVAL_SECONDS=0 \
  scripts/run-naru-live-benchmark.sh helper-text-live-gate
```

## Privacy

This artifact contains only fixed labels, aggregate counts, gate verdicts,
privacy-safe issue/action labels, and local log paths. It omits hostnames,
endpoints, credentials, helper executable paths, profile fingerprints, pairing
tokens, physical device identifiers, device names, team identifiers, bundle
identifiers, profile names, profile UUIDs, certificate names, raw xcodebuild
logs, raw profile plists, frame pixels, screenshots, dimensions, coordinates,
byte counts, composed text, clipboard contents, focused app/window titles, raw
OS errors, and exact timing series.
