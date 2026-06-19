# Physical iPhone Reconnected Signing Gate - 2026-06-17

## Scope

This artifact records the physical iPhone state after the operator reconnected
an iPhone for T030 physical iPhone + Mac verification.

This is not a physical iPhone Green claim, helper-video smoothness pass, input
responsiveness pass, thermal pass, PiP pass, or live FPS improvement. It exists
to prevent repeated device-discovery experiments while the connected-device
gate is now blocked by Xcode account and exact app provisioning.

## Device Preflight

Command:

```bash
scripts/run-naru-live-benchmark.sh physical-device-preflight
```

Log:

```text
/tmp/naru-physical-device-preflight-20260617-iphone-reconnected.log
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

- The reconnected iPhone is visible to the physical gate.
- The current blocker is not USB discovery, stale iPad selection, or device
  lock.
- The physical app gate cannot run until command-line Xcode signing can build
  and install this app on the connected iPhone.

## Provisioning Inventory

Command:

```bash
scripts/run-naru-live-benchmark.sh physical-provisioning-profile-inventory
```

Log:

```text
/tmp/naru-physical-provisioning-profile-inventory-20260617-iphone-reconnected.log
```

Result:

- `projectBuildSettingsStatus=passed`
- `projectBundleIDStatus=present`
- `projectTeamStatus=present`
- `effectiveTeamSource=project`
- `validProfileCount=7`
- `teamMatchCount=7`
- `bundleExactMatchCount=0`
- `bundleWildcardMatchCount=7`
- `exactDevelopmentProfileCount=0`
- `wildcardDevelopmentProfileCount=7`
- `provisionedDeviceProfileCount=7`
- `primaryBlockedGateLabel=ios-exact-provisioning-profile`
- `recommendedPrimaryAction=create-exact-ios-development-profile`
- `issueCodes=[ios-exact-provisioning-profile-missing]`

Interpretation:

- Team-matching wildcard development profiles are present and include the
  device, but no exact development profile for the app bundle is available in
  the scanned inventory.
- Wildcard profile presence is not enough to promote the physical iPhone gate.

## Signing Variant Probe

Command:

```bash
scripts/run-naru-live-benchmark.sh physical-signing-variant-probe
```

Log:

```text
/tmp/naru-physical-signing-variant-probe-20260617-iphone-reconnected.log
```

Result:

| Variant | Status | Account | Profiles | Hint |
| --- | --- | --- | --- | --- |
| `allowProvisioningUpdates` | `failed` | `hasNoAccounts=true` | `hasNoProfiles=true` | `hasProvisioningUpdatesHint=true` |
| `localProfilesOnly` | `failed` | `hasNoAccounts=false` | `hasNoProfiles=true` | `hasProvisioningUpdatesHint=true` |
| `allowUpdatesAndDeviceRegistration` | `failed` | `hasNoAccounts=true` | `hasNoProfiles=true` | `hasDeviceRegistrationHint=true` |

Interpretation:

- Automatic signing cannot create or download the missing exact profile because
  `xcodebuild` cannot access a usable Xcode account for the configured team.
- Local-only signing also fails because the exact app development profile is
  missing.

## Required Next Action

One of these operator actions must happen before the physical helper-video or
physical Compose gate can produce product evidence:

- Sign into the Xcode account for the configured development team in Xcode, make
  sure command-line `xcodebuild` can use that account, then rerun
  `physical-device-preflight`.
- Or create/download an exact iOS development provisioning profile for the app
  bundle, install it into the standard provisioning profiles directory, then
  rerun `physical-provisioning-profile-inventory` and
  `physical-signing-variant-probe`.

After `physical-device-preflight` reports `buildCheckStatus=passed`, rerun:

```bash
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate
```

## Do Not Repeat

- Do not rerun iPhone-vs-iPad target-class experiments for this blocker.
- Do not rerun helper-video Mac-side readiness as a substitute for physical
  iPhone promotion. The Mac-side helper video and helper text gates are already
  ready for physical promotion; the current stop is iOS signing/install.
- Do not treat wildcard profile counts as a passing signal for this app bundle.

## Privacy

This artifact contains only fixed labels, aggregate counts, and local log
paths. It omits physical device identifiers, device names, team identifiers,
bundle identifiers, profile names, profile UUIDs, certificate names, raw
xcodebuild logs, raw profile plists, helper paths, endpoints, credentials,
screenshots, frame payloads, pixels, dimensions, coordinates, byte counts,
Compose text, clipboard contents, and exact timing series.
