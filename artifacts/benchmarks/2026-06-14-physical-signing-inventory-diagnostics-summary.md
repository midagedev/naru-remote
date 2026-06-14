# Physical Signing Inventory Diagnostics Summary

Date: 2026-06-14 KST

## Question

The true helper-video path is now mostly ready locally, but the physical iPhone
gate still stops before app launch. The previous preflight labels showed
`xcode-account-missing` and `ios-provisioning-profile-missing`, but did not say
whether the configured team was backed by a local Apple Development certificate
or whether any local iOS provisioning profiles were installed.

## Change

Physical iPhone and physical iPad preflight now emit two additional fixed
labels:

- `developmentTeamCertificateMatchStatus`: `matched`, `notMatched`,
  `notSupplied`, `noLocalAppleDevelopmentTeams`, or `unknown`
- `localProvisioningProfileInventoryStatus`: `present`, `none`, or `unknown`

The same labels are also propagated into:

- `helper-video-live-gate` `gateSummary.physicalIPhoneGate`
- `remote-desktop-10fps-readiness` `readinessGateSummary.physicalIPhoneGate`

This pass also adds `physical-ipad-launch-smoke`, a separate `devicectl`
install/foreground-launch/process-observation gate for the connected iPad. It
is intentionally separate from XCTest because XCTest can complete quickly and
clean up the launched app, which can look like the app never stayed open.

No team IDs, account IDs, certificate names, profile filenames, profile UUIDs,
bundle profile contents, device identifiers, raw xcodebuild logs, hostnames,
credentials, frame pixels, input coordinates, text, clipboard contents, byte
counts, or exact timings are emitted.

## Current Live Evidence

Command:

```bash
bash scripts/run-naru-live-benchmark.sh helper-video-live-gate
```

Safe result:

- `screenRecordingWatch.watchStatus`: `granted`
- `helperVideoGate.syntheticVerdict`: `pass`
- `helperVideoGate.sustainedSyntheticVerdict`: `pass`
- `helperVideoGate.screenCaptureVerdict`: `pass`
- `helperVideoGate.sustainedScreenCaptureVerdict`: `pass`
- `appBootstrapGate.status`: `passed`
- `physicalIPhoneGate.deviceDiscoveryStatus`: `connected`
- `physicalIPhoneGate.developmentTeamCertificateMatchStatus`: `matched`
- `physicalIPhoneGate.localProvisioningProfileInventoryStatus`: `none`
- `physicalIPhoneGate.xcodeAccountStatus`: `missing`
- `physicalIPhoneGate.provisioningProfileStatus`: `missing`
- `physicalIPhoneGate.buildCheckStatus`: `failed`
- `gateSummary.overallGateState`: `blockedByPhysicalIPhoneGate`
- `gateSummary.recommendedPrimaryAction`: `open-xcode-account-settings`

Interpretation:

The configured development team is backed by a local Apple Development
certificate, so this is not currently a team/certificate mismatch. The local
iOS provisioning profile inventory is empty, and xcodebuild still reports that
the Xcode account/provisioning path is unavailable for the physical iPhone
build. The next action remains opening Xcode account settings, signing in for
the configured development team, creating or refreshing the iOS Development
provisioning profile, and rerunning `physical-device-preflight`.

## Connected iPad Launch Smoke

Command:

```bash
bash scripts/run-naru-live-benchmark.sh physical-ipad-launch-smoke
```

Safe result:

- `deviceDiscoveryStatus`: `connected`
- `resolvedDeviceClass`: `iPad`
- `deviceUnlockedSinceBootStatus`: `true`
- `deviceBacklightState`: `activeOn`
- `appBundleStatus`: `present`
- `installStatus`: `passed`
- `launchStatus`: `passed`
- `launchPIDStatus`: `present`
- `runningStatus`: `passed`
- `safeFailureLabel`: `none`

Interpretation:

The connected iPad can install and foreground-launch the existing
`NaruRemote.app`, and the app remains running after the short observation
window. A short `xcodebuild test` ending does not prove the app failed to
launch; it usually means the XCTest runner completed and cleaned up its
application lifecycle. For longer manual or UX/performance runs, keep the iPad
unlocked with Auto-Lock disabled or the smoke gate will stop early with
`unlock-physical-ipad`.

## Transient Note

One `helper-video-live-gate` run reported
`screen-capturekit-app-bootstrap-failed`, but an immediate standalone
`helper-screen-app-bootstrap-benchmark` passed, and the following
`helper-video-live-gate` also passed the app bootstrap gate. Treat a single
bootstrap failure as a rerun/triage signal unless it repeats.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
git diff --check
bash scripts/run-naru-live-benchmark.sh physical-team-inference-self-test
bash scripts/run-naru-live-benchmark.sh physical-ipad-device-preflight-self-test
bash scripts/run-naru-live-benchmark.sh physical-ipad-launch-smoke-self-test
bash scripts/run-naru-live-benchmark.sh physical-ipad-launch-smoke
bash scripts/run-naru-live-benchmark.sh helper-video-live-gate-self-test
bash scripts/run-naru-live-benchmark.sh remote-desktop-readiness-summary-self-test
bash scripts/run-naru-live-benchmark.sh physical-device-preflight
bash scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark
bash scripts/run-naru-live-benchmark.sh helper-video-live-gate
```
