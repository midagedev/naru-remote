# Physical Provisioning Profile Inventory - 2026-06-15

## Scope

Clarify why physical iPad preflight can see a connected device and a configured
development team but still reports `xcode-account-missing` and
`ios-provisioning-profile-missing`.

This is signing/profile triage only. It is not a physical iPhone Green claim,
performance improvement, helper-video improvement, or PR-worthy product change.

## Commands

The inventory is now reproducible through the privacy-safe runner mode:

```bash
scripts/run-naru-live-benchmark.sh physical-provisioning-profile-inventory
```

The mode inspects local `.mobileprovision` files without printing profile
names, profile UUIDs, team identifiers, bundle identifiers, device identifiers,
certificate names, raw profile plists, or raw xcodebuild logs.

Shape regression:

```bash
scripts/run-naru-live-benchmark.sh physical-provisioning-profile-inventory-self-test
```

The signing variants were already checked with:

```bash
NARU_PHYSICAL_IOS_DEVICE_CLASS=ipad \
scripts/run-naru-live-benchmark.sh physical-signing-variant-probe
```

## Results

The standard CLI profile directory was absent:

- `MobileDevice/Provisioning Profiles=missing`

Other Xcode cache locations contained profiles:

- `Xcode/UserData/Provisioning Profiles=1`
- `Xcode/DerivedData=6`

Across those seven local profiles:

- `validProfileCount=7`
- `standardProfileCount=0`
- `userDataProfileCount=1`
- `derivedDataProfileCount=6`
- `teamMatchCount=7`
- `developmentProfileCount=7`
- `provisionedDeviceProfileCount=7`
- `bundleExactMatchCount=0`
- `bundleWildcardMatchCount=7`
- `exactDevelopmentProfileCount=0`
- `wildcardDevelopmentProfileCount=7`
- `teamBundleDevelopmentMatchCount=7`

The reusable command summarizes this as:

- `readinessState=blocked`
- `primaryBlockedGateLabel=ios-exact-provisioning-profile`
- `recommendedPrimaryAction=create-exact-ios-development-profile`
- `exactDevelopmentProfileStatus=missing`
- `wildcardDevelopmentProfileStatus=present`

That means the machine has team-matching development profiles, but they are
wildcard profiles. There is no exact development profile for the current app
bundle in the scanned local inventory.

An ad hoc build probe then selected a matching wildcard development profile and
passed it explicitly through `PROVISIONING_PROFILE_SPECIFIER` with manual
signing. Both the full scheme and app target failed with the fixed
`hasSpecifierMismatch=true` label, while these remained false:

- `hasNoProfiles=false`
- `hasNoAccounts=false`
- `hasRequiresDevelopmentTeam=false`

## Product Decision

Do not repeat device-id or helper-video experiments for this blocker. The iPad
is already selected correctly by the target-aware preflight. The remaining
physical-device blocker is signing/profile availability for the current app
bundle.

The useful next operator actions are:

- sign into the Xcode account for the configured development team so
  `-allowProvisioningUpdates` can create/download an exact development profile,
  then rerun `physical-device-preflight`
- or manually create/download an exact iOS development provisioning profile for
  the current app bundle, install it into the standard provisioning profile
  location, then rerun `physical-signing-variant-probe`

Wildcard profiles in Xcode cache locations are not enough evidence that
`xcodebuild` can install this app on the physical iPad/iPhone.

## Safety

This artifact contains only fixed status labels and aggregate profile counts. It
omits profile names, profile UUIDs, team identifiers, bundle identifiers, device
identifiers, certificate names, provisioning profile contents, raw xcodebuild
logs, hostnames, endpoints, credentials, screenshots, pixels, byte counts,
Compose text, clipboard contents, and exact timing series.
