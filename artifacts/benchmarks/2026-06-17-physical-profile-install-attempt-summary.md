# Physical Profile Install Attempt - 2026-06-17

## Scope

This artifact records the local attempt to unblock physical iPhone signing by
making existing cached development provisioning profiles visible to command-line
`xcodebuild`.

This is not a physical iPhone Green claim, performance improvement, helper-video
improvement, or PR-ready product change. It exists to avoid repeating the
profile-copy experiment while the physical gate is blocked.

## Starting Hypothesis

Earlier inventory showed:

- the physical iPhone is connected
- the project and launchctl development-team inputs match
- `.paperclip/.env` is not present in the repo, so the old Paperclip env
  mismatch class is not the active blocker
- Xcode cache locations contain team-matching wildcard development profiles
- the standard command-line profile directory was missing or empty
- `xcodebuild` local profile variants still reported no usable profiles

The hypothesis was that copying or installing cached wildcard profiles into the
standard command-line profile location might let local-profile-only
`xcodebuild` find a usable profile.

## Attempted Actions

### Standard Directory Copy

Action:

- Created `~/Library/MobileDevice/Provisioning Profiles`.
- Copied cached `.mobileprovision` files using their profile UUID as the
  destination filename when no destination file existed.

Observation:

- A copied profile was briefly visible in the standard directory.
- A subsequent inventory run still reported `standardProfileCount=0`.
- Rechecking the directory after the inventory run showed the copied profile was
  no longer present.

Interpretation:

- Direct copy of the cached wildcard profile is not a durable unblock for this
  `xcodebuild` gate.
- Do not repeat raw copy of cached wildcard profiles for this blocker.

### `profiles` CLI Install

Action:

```bash
profiles -i -F <cached-development-profile>
```

Observation:

- The command reported the fixed local failure shape equivalent to
  `provisioning-profile-not-compatible-with-macos`.
- The standard directory remained at `0` `.mobileprovision` files.
- The privacy-safe inventory remained unchanged:
  - `standardProfileCount=0`
  - `bundleExactMatchCount=0`
  - `bundleWildcardMatchCount=7`
  - `exactDevelopmentProfileCount=0`
  - `wildcardDevelopmentProfileCount=7`
  - `primaryBlockedGateLabel=ios-exact-provisioning-profile`

Interpretation:

- The macOS `profiles` install path is not a useful way to install these iOS
  development profiles for the current physical iPhone gate.
- Do not repeat `profiles -i -F` against cached wildcard profiles for this
  blocker.

## Post-Attempt Gate Results

Physical provisioning inventory:

```bash
scripts/run-naru-live-benchmark.sh physical-provisioning-profile-inventory
```

Log:

```text
/tmp/naru-physical-provisioning-profile-inventory-20260617-after-profiles-install.log
```

Result:

- `profileDirectoryStatus.standard=present`
- `standardProfileCount=0`
- `userDataProfileCount=1`
- `derivedDataProfileCount=6`
- `teamMatchCount=7`
- `bundleExactMatchCount=0`
- `bundleWildcardMatchCount=7`
- `exactDevelopmentProfileCount=0`
- `wildcardDevelopmentProfileCount=7`
- `primaryBlockedGateLabel=ios-exact-provisioning-profile`
- `recommendedPrimaryAction=create-exact-ios-development-profile`
- After the follow-up runner label fix, `setupActionLabels` now includes
  `install-exact-profile-to-standard-provisioning-directory`, not the older
  ambiguous `install-profile-to-standard-provisioning-directory`.

Physical signing variant probe:

```bash
scripts/run-naru-live-benchmark.sh physical-signing-variant-probe
```

Log:

```text
/tmp/naru-physical-signing-variant-probe-20260617-after-standard-install.log
```

Result:

- `allowProvisioningUpdates`: failed with `hasNoAccounts=true` and
  `hasNoProfiles=true`
- `localProfilesOnly`: failed with `hasNoAccounts=false` and
  `hasNoProfiles=true`
- `allowUpdatesAndDeviceRegistration`: failed with `hasNoAccounts=true`,
  `hasNoProfiles=true`, and `hasDeviceRegistrationHint=true`
- `primaryBlockedGateLabel=xcode-account`
- `recommendedPrimaryAction=open-xcode-account-settings`

Physical device preflight:

```bash
scripts/run-naru-live-benchmark.sh physical-device-preflight
```

Log:

```text
/tmp/naru-physical-device-preflight-20260617-after-profile-install-attempt.log
```

Result:

- `deviceDiscoveryStatus=connected`
- `resolvedDeviceClass=iPhone`
- `codeSigningIdentityStatus=available`
- `developmentTeamStatus=environment`
- `xcodeAccountStatus=missing`
- `provisioningProfileStatus=missing`
- `buildCheckStatus=failed`
- `primaryBlockedGateLabel=xcode-account`
- `issueCodes=[xcode-account-missing, ios-provisioning-profile-missing]`

## Decision

The physical iPhone blocker remains:

1. Xcode account access for the configured development team must be available
   to command-line `xcodebuild`, so `-allowProvisioningUpdates` can create or
   download the exact app profile.
2. Or an exact iOS development profile for the app bundle must be created and
   made available through a path that command-line `xcodebuild` accepts.

Cached wildcard profiles are not enough. Copying cached wildcard profiles or
using `profiles -i -F` does not unblock the current physical iPhone gate.
Benchmark action labels now intentionally say exact profile install so cached
wildcard profile copy/install is not repeated as the next experiment.
The exact-profile wording is aligned across the physical provisioning
inventory, physical device preflight, signing variant probe, physical iPhone
helper-video gate, helper-video live gate summary, and remote-desktop readiness
summary fixtures.

## Next Useful Action

Operator action:

- Open Xcode account settings.
- Sign into the account for the configured development team.
- Let Xcode create or download an exact iOS development profile for the app
  bundle.
- Rerun:

```bash
scripts/run-naru-live-benchmark.sh physical-device-preflight
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate
```

## Privacy

This artifact contains only fixed labels, aggregate counts, local log paths, and
high-level action descriptions. It omits device identifiers, device names,
development team identifiers, bundle identifiers, profile UUIDs, profile names,
certificate names, raw profile plists, raw xcodebuild logs, account names,
email addresses, hostnames, endpoints, credentials, frame payloads, pixels,
dimensions, coordinates, byte counts, composed text, clipboard contents, and
exact timing series.
