# Simulator Input/Viewport Gate Refresh - 2026-06-15

## Scope

Refresh the fast input/viewport regression evidence after the latest helper
video readiness work, without repeating VNC receive-path or helper-video live
readiness experiments already closed by the current artifacts.

This is simulator regression evidence only. It is not a physical iPhone Green
claim, a live FPS improvement claim, or a traffic/thermal promotion result.

## Commands

```bash
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate-self-test
```

```bash
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

```bash
scripts/run-naru-live-benchmark.sh physical-device-preflight
```

```bash
NARU_PHYSICAL_IOS_DEVICE_CLASS=ipad \
scripts/run-naru-live-benchmark.sh physical-signing-variant-probe
```

## Results

The simulator gate self-test passed, covering the wrapper's fixed pass/fail
status handling for iPhone-only, iPad-default, and iPad-full-storm cases.

The full simulator gate passed with both iPhone and iPad simulator coverage.
Safe step labels:

- `swift-focused-unit-slice=passed`
- `iphone-compose-basic-ui-test=passed`
- `iphone-compose-full-interaction-storm-ui-test=passed`
- `iphone-trackpad-viewport-compose-ui-test=passed`
- `iphone-viewport-hotpath-benchmark=passed`
- `ipad-compose-basic-ui-test=passed`
- `ipad-trackpad-viewport-compose-ui-test=passed`

The extended iPad full-storm variant also passed when rerun with:

```bash
NARU_SIMULATOR_GATE_INCLUDE_IPAD_FULL_STORM=1 \
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

Additional safe step label:

- `ipad-compose-full-interaction-storm-ui-test=passed`

The covered policy labels were:

- `korean-cjk-compose-freeze-regression`
- `viewport-hotpath-simulator-benchmark`
- `viewport-pressure-diagnostic-regression`
- `trackpad-viewport-gesture-ui-regression`
- `iphone-and-ipad-simulator-local-iteration-gate`

The current physical preflight still blocks before physical-product evidence:

- `targetDeviceClass=iPhone`
- `resolvedDeviceClass=iPhone`
- `deviceDiscoveryStatus=unavailable`
- `deviceIDResolutionStatus=environmentUnresolved`
- `buildCheckStatus=skipped`
- `primaryBlockedGateLabel=physical-iphone-device`
- `recommendedPrimaryAction=unlock-connect-and-enable-developer-mode`
- `issueCodes=[physical-iphone-device-unavailable]`

An iPad-target preflight was also attempted because iPad graceful coverage is a
secondary product target. The first run did not produce iPad evidence because
the current launchctl environment still resolves a selected iPhone device id:

- `targetDeviceClass=iPad`
- `resolvedDeviceClass=iPhone`
- `deviceDiscoveryStatus=wrongDeviceType`
- `deviceSelectionSource=environment`
- `deviceIDResolutionStatus=environmentUnresolved`
- `issueCodes=[physical-ipad-device-required]`
- `setupActionLabels=[set-physical-ios-device-id-to-ipad]`

The runner was then tightened so future iPad physical smoke does not need a
manual id override when a stale iPhone id is present in the process or
launchctl environment. With `NARU_PHYSICAL_IOS_DEVICE_CLASS=ipad`, an existing
iPhone id that does not match the iPad target class is ignored before auto
discovery.

After that change, an iPad target preflight with no shell-local device id
override reached the build/signing boundary:

- `targetDeviceClass=iPad`
- `resolvedDeviceClass=iPad`
- `deviceDiscoveryStatus=connected`
- `deviceSelectionSource=auto`
- `deviceIDResolutionStatus=auto`
- `xcodeAccountStatus=missing`
- `provisioningProfileStatus=missing`
- `buildCheckStatus=failed`
- `issueCodes=[xcode-account-missing, ios-provisioning-profile-missing]`

The preflight summary was tightened so this iPad target no longer recommends
the iPhone helper-video gate. The same run now reports
`operatorActionSequence=[open-xcode-account-settings,
sign-in-to-xcode-account-for-development-team,
rerun-physical-device-preflight, rerun-physical-ipad-smoke]`.

The new signing variant probe makes the same iPad signing blocker reproducible
without preserving raw xcodebuild logs. It compares three fixed xcodebuild
signing variants:

- `allowProvisioningUpdates`: failed with `hasNoAccounts=true`,
  `hasNoProfiles=true`, `hasProvisioningUpdatesHint=true`
- `localProfilesOnly`: failed with `hasNoAccounts=false`,
  `hasNoProfiles=true`, `hasProvisioningUpdatesHint=true`
- `allowUpdatesAndDeviceRegistration`: failed with `hasNoAccounts=true`,
  `hasNoProfiles=true`, `hasProvisioningUpdatesHint=true`,
  `hasDeviceRegistrationHint=true`

This means the attached iPad is reachable and selected correctly, but the
current CLI build path cannot use or create the needed development profile.
The local-profiles-only variant also has no usable profile, so the blocker is
not only caused by passing `-allowProvisioningUpdates`.

## Product Decision

Do not rerun VNC receive-path/traffic experiments or helper-video Mac-side live
readiness for this promotion path unless code or environment changes. The next
useful product evidence remains the physical iPhone helper-video/input gate
after the selected iPhone is connected, unlocked, trusted, and kept awake.

This run is not PR-worthy by itself under the current rule because it verifies
the simulator gate and current blocker state, but does not show a new
before/after performance or hand-feel improvement. The signing variant probe is
useful diagnostic infrastructure, not a product smoothness improvement. Keep it
as regression and triage evidence for the ongoing physical-gate work.

## Safety

This artifact contains only fixed labels and coarse pass/fail state. It omits
hostnames, IP addresses, endpoints, credentials, helper executable paths,
device identifiers, raw xcodebuild output, raw OS errors, screenshots,
framebuffer pixels, dimensions, coordinates, byte counts, Compose text,
clipboard contents, keysyms, pairing material, and exact timing series.
