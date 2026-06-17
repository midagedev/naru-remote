# Physical iPhone Residual Risk Refresh - 2026-06-17

## Scope

This artifact records the current residual manual-device blocker for T030
physical iPhone + Mac helper-video verification.

This is not a physical iPhone Green claim, helper-video smoothness pass,
thermal pass, PiP pass, or live FPS improvement. It exists to avoid repeating
device-id, VNC receive-path, or helper-video readiness experiments while the
current physical gate is blocked by signing/provisioning.

## Current Physical Preflight

Command:

```bash
scripts/run-naru-live-benchmark.sh physical-device-preflight
```

Result:

- `targetDeviceClass=iPhone`
- `resolvedDeviceClass=iPhone`
- `deviceDiscoveryStatus=connected`
- `deviceSelectionSource=environment`
- `deviceIDResolutionStatus=environmentXcodebuildUDID`
- `codeSigningIdentityStatus=available`
- `developmentTeamStatus=environment`
- `xcodeAccountStatus=missing`
- `provisioningProfileStatus=missing`
- `buildCheckStatus=failed`
- `primaryBlockedGateLabel=xcode-account`
- `recommendedPrimaryAction=open-xcode-account-settings`
- `issueCodes=[xcode-account-missing, ios-provisioning-profile-missing]`

Interpretation:

- The current blocker is not physical iPhone discovery.
- Do not repeat iPhone device-id or iPad target-class experiments for this
  blocker.
- The physical iPhone helper-video gate cannot produce T030 promotion evidence
  until xcodebuild can sign/install this app for the connected iPhone.

## Current Provisioning Inventory

Command:

```bash
scripts/run-naru-live-benchmark.sh physical-provisioning-profile-inventory
```

Result:

- `projectBuildSettingsStatus=passed`
- `projectBundleIDStatus=present`
- `projectTeamStatus=present`
- `profileDirectoryStatus.standard=missing`
- `profileDirectoryStatus.userData=present`
- `profileDirectoryStatus.derivedData=present`
- `validProfileCount=7`
- `teamMatchCount=7`
- `bundleExactMatchCount=0`
- `bundleWildcardMatchCount=7`
- `exactDevelopmentProfileCount=0`
- `wildcardDevelopmentProfileCount=7`
- `primaryBlockedGateLabel=ios-exact-provisioning-profile`
- `recommendedPrimaryAction=create-exact-ios-development-profile`
- `exactDevelopmentProfileStatus=missing`
- `wildcardDevelopmentProfileStatus=present`
- `issueCodes=[ios-exact-provisioning-profile-missing]`

Interpretation:

- Local wildcard development profiles are present, but no exact development
  profile for the current app bundle exists in the scanned inventory.
- Wildcard profile presence is not enough evidence that `xcodebuild` can
  install the app on the connected physical iPhone.

## Required Next Action

One of these operator actions is required before rerunning the physical helper
video gate:

- Sign into the Xcode account for the configured development team so automatic
  signing can create or download the exact app development profile, then rerun
  `physical-device-preflight`.
- Or manually create/download an exact iOS development provisioning profile for
  the current app bundle, install it into the standard provisioning profile
  location, then rerun `physical-provisioning-profile-inventory` and
  `physical-signing-variant-probe`.

After preflight reports `buildCheckStatus=passed`, rerun:

```bash
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate
```

## Residual Risk

- T030 remains open until a physical iPhone run records helper-video visual
  evidence, input responsiveness evidence, PiP evidence, diagnostic export
  evidence, and sustained-session assessment from the connected iPhone.
- `TXXX Run all checks listed in quickstart.md` remains open because the
  quickstart includes physical and live credential gates that should be
  rerun only after the signing/provisioning state changes.

## Privacy

This artifact contains only fixed labels and aggregate counts. It omits
physical device identifiers, device names, profile names, profile UUIDs, team
identifiers, bundle identifiers, certificate names, raw xcodebuild logs, raw
profile plists, helper paths, endpoints, credentials, screenshots, frame
payloads, pixels, dimensions, coordinates, byte counts, Compose text,
clipboard contents, and exact timing series.
