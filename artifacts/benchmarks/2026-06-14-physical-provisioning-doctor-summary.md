# Physical Provisioning Doctor

Date: 2026-06-14

## Purpose

Prevent repeated physical-device signing experiments when Xcode GUI state and
non-interactive `xcodebuild` state disagree. The new
`physical-provisioning-doctor` mode answers a narrower question than the full
preflight:

> Can this CLI context see an installed iOS development provisioning profile
> that matches the app, selected team, and target physical device?

## Privacy

The doctor reports only fixed labels and buckets. It does not print profile
paths, filenames, UUIDs, team IDs, device IDs, bundle identifiers, account IDs,
raw xcodebuild logs, credentials, helper paths, hostnames, pixels, coordinates,
or copied text.

## What It Checks

- project signing settings are readable
- the app target has the expected app-bundle setting, without printing it
- project team and profile specifier are present or missing
- caller shell and launchctl team environment presence are separated
- local Apple Development identity count is bucketed
- effective team is backed by a local Apple Development certificate
- the standard provisioning directory exists and has installed profiles
- installed profiles match app/team/device in aggregate
- an optional candidate profile path matches app/team/device/expiration, without
  printing that path or profile metadata

Use the optional candidate path when a profile exists outside the standard
installed profile directory:

```bash
NARU_PHYSICAL_IOS_PROVISIONING_PROFILE_PATH=/path/to/profile.mobileprovision \
  scripts/run-naru-live-benchmark.sh physical-provisioning-doctor
```

## Evidence

- `bash -n scripts/run-naru-live-benchmark.sh`: passed.
- `scripts/run-naru-live-benchmark.sh physical-provisioning-doctor-self-test`:
  passed.
- `git diff --check`: passed.
- Connected physical iPhone doctor:
  `targetDeviceStatus=present`,
  `effectiveTeamCertificateMatchStatus=matched`,
  `projectBundleIdentifierStatus=expectedApp`,
  `projectDevelopmentTeamStatus=missing`,
  `projectProvisioningProfileSpecifierStatus=missing`,
  `standardProvisioningDirectoryStatus=missing`,
  `installedProvisioningProfileCountBucket=zero`,
  `diagnosisLabel=localProvisioningInventoryEmpty`,
  `recommendedAction=download-or-install-ios-development-profile`.
- Connected physical iPad doctor:
  same signing/provisioning diagnosis as the iPhone target, with
  `targetDeviceClass=iPad`.
- Current `physical-device-preflight` still blocks on
  `xcode-account-missing` and `ios-provisioning-profile-missing`, which is now
  consistent with the doctor rather than a runtime/app-launch failure.

## Interpretation

This environment has a connected physical iPhone and iPad plus a local Apple
Development certificate matching the effective team. The blocking gap is that
the CLI-visible standard provisioning inventory is empty/missing and the
project does not commit a development team or provisioning profile specifier.

If Xcode GUI can build/install, that success is likely coming from GUI account
state or a profile not installed where this CLI context looks. Either install
or download the matching development profile into the standard profile
inventory, or rerun the doctor with `NARU_PHYSICAL_IOS_PROVISIONING_PROFILE_PATH`
pointing at the profile file to prove whether the candidate actually matches
the app/team/device.
