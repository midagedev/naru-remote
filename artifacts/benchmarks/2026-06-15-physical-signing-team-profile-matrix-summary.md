# Physical Signing Team/Profile Matrix Summary

Date: 2026-06-15 KST

## Question

The operator expected a provisioning profile to exist, but
`physical-device-preflight` and `physical-iphone-helper-video-gate` still
blocked before the physical iPhone sustained helper-video run.

## Current Safe Finding

There are two different signing worlds visible from the local machine:

- The current local Apple Development certificate belongs to one development
  team.
- The discovered iOS Team Provisioning Profile belongs to a different
  development team.
- The discovered profile is stored under Xcode user data rather than the
  standard MobileDevice provisioning profile inventory directory.
- The project itself does not declare `DEVELOPMENT_TEAM`,
  `CODE_SIGN_STYLE`, or `PROVISIONING_PROFILE_SPECIFIER`, so the runner depends
  on environment-provided signing state.

This explains why Xcode-derived checks can appear partially ready while the
runner still blocks: one team has a local signing identity, while the other
team has the discovered provisioning profile/account path.

## Matrix

### Local Certificate Team

Command shape:

```bash
NARU_XCODE_DEVELOPMENT_TEAM=<local-certificate-team> \
  scripts/run-naru-live-benchmark.sh physical-device-preflight
```

Safe result:

- `developmentTeamCertificateMatchStatus`: `matched`
- `xcodeAccountStatus`: `missing`
- `provisioningProfileStatus`: `missing`
- `localProvisioningProfileInventoryStatus`: `none`
- `buildCheckStatus`: `failed`
- `issueCodes`: `xcode-account-missing`,
  `ios-provisioning-profile-missing`

The physical iPhone helper-video gate with explicit sustained candidate labels
also stops before XCTest:

- `xcodebuildTestStatus`: `notRun`
- `issueCodes`: `xcode-account-missing`,
  `ios-provisioning-profile-missing`

### Discovered Profile Team

Command shape:

```bash
NARU_XCODE_DEVELOPMENT_TEAM=<discovered-profile-team> \
NARU_PHYSICAL_IOS_PROVISIONING_PROFILE_PATH=<discovered-profile> \
  scripts/run-naru-live-benchmark.sh physical-device-preflight
```

Safe result:

- `developmentTeamCertificateMatchStatus`: `notMatched`
- `xcodeAccountStatus`: `available`
- `provisioningProfileStatus`: `available`
- `buildCheckStatus`: `passed`
- initial `issueCodes`: `ios-development-team-certificate-mismatch`
- after the local runner policy correction, this mismatch is downgraded to a
  diagnostic label when `xcodebuild` passes

The physical iPhone helper-video gate with explicit sustained candidate labels
still blocks before XCTest:

- current iPhone availability: unavailable in the latest local preflight
- current `physical-iphone-helper-video-gate`:
  - `status`: `blocked`
  - `xcodebuildTestStatus`: `notRun`
  - `issueCodes`: `physical-iphone-device-unavailable`
  - `setupActionLabels`: `unlock-connect-and-enable-developer-mode`
- expected next behavior after iPhone availability is restored: if
  `xcodebuild` passes with the discovered profile team, the certificate-team
  mismatch should no longer block the gate by itself

### Connected Physical iPad Cross-Check

The connected physical iPad is usable as a secondary device loop even while the
iPhone gate remains blocked/unavailable.

Using the discovered profile team from `launchctl` plus the generated
`Debug-iphoneos` app bundle:

- `physical-ipad-device-preflight`:
  - `deviceDiscoveryStatus`: `connected`
  - `resolvedDeviceClass`: `iPad`
  - `deviceUnlockedSinceBootStatus`: `true`
  - `deviceBacklightState`: `activeOn`
  - `xcodeAccountStatus`: `available`
  - `provisioningProfileStatus`: `available`
  - `buildCheckStatus`: `passed`
  - `issueCodes`: none after the runner policy correction
  - diagnostic labels include
    `development-team-certificate-mismatch-overridden-by-passing-xcodebuild`
- `physical-ipad-launch-smoke`:
  - `installStatus`: `passed`
  - `launchStatus`: `passed`
  - `runningStatus`: `passed`
- `physical-ipad-state-marker-smoke` after the runner fallback:
  - `installStatus`: `passed`
  - `launchStatus`: `passed`
  - `runningStatus`: `passed`
  - `markerCopyStatus`: `passed`
  - `markerValidationLabel`: `passed`
  - `markerProfileCountStatus`: `one`
  - `markerSelectedProfileStatus`: `present`
  - `markerHelperVideoStatus`: `enabled`

The state-marker failure was not an app launch failure. The app wrote the marker
into its Documents container; this local `devicectl` environment failed to copy
the individual `Documents/<marker>` source but succeeded when copying the whole
`Documents` directory and then validating the marker locally. The runner now
falls back to that directory-copy path.

The signing mismatch failure was also not an app build failure when using the
discovered profile team. The runner now treats a passing `xcodebuild` result as
authoritative for the current signing path and leaves the local certificate-team
mismatch as a diagnostic label rather than a hard issue code.

## Interpretation

The currently discovered provisioning profile is real, not expired, and can
build/install the app on the connected iPad. The runner now treats a passing
`xcodebuild` result as authoritative for that signing path, so the local
certificate-team mismatch is no longer a hard blocker by itself.

The immediate iPhone gate blocker is now the physical iPhone availability
state, not signing/profile confusion:

- `physical-device-preflight`: `physical-iphone-device-unavailable`
- `physical-iphone-helper-video-gate`: `physical-iphone-device-unavailable`

For long-term release hygiene, it is still cleaner to choose one signing world
and make all of these match:

- `NARU_XCODE_DEVELOPMENT_TEAM`
- local Apple Development certificate/private key
- iOS Development provisioning profile
- target device membership
- app bundle identifier eligibility

Most direct options:

- Install/download a matching iOS Development provisioning profile for the team
  that already has the local Apple Development certificate.
- Or install the Apple Development certificate/private key for the team that
  owns the discovered provisioning profile.

After that, rerun:

```bash
scripts/run-naru-live-benchmark.sh physical-device-preflight
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate
```

For the currently connected iPad loop, the verified baseline is:

```bash
scripts/run-naru-live-benchmark.sh physical-ipad-device-preflight
scripts/run-naru-live-benchmark.sh physical-ipad-launch-smoke
scripts/run-naru-live-benchmark.sh physical-ipad-state-marker-smoke
```

An additional manual 10-second physical iPad XCTest attempt did not prove app
smoothness. It failed at the CoreDevice/XCTest runner layer rather than at a
Naru assertion:

- `manual-physical-ipad-sustained-e2e-log-summary`
- `runStatus`: `failed`
- safe failure label: `unclassifiedXcodebuildFailure` before classifier update
- summary line category: remote test-runner communication invalidated
- no app diagnostic export was available on the final detail attempt

The runner now classifies this shape as
`physical-ios-test-runner-communication-invalidated` with setup actions to keep
the device unlocked, reconnect the physical iOS device, and inspect the
physical XCTest runner. Do not repeat the physical iPad XCTest sustained run as
a product signal until this CoreDevice runner instability is resolved; use the
passing install/launch/state-marker smokes for iPad device-lifecycle evidence.

## Verification Commands

```bash
scripts/run-naru-live-benchmark.sh physical-provisioning-doctor
scripts/run-naru-live-benchmark.sh physical-device-preflight
scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate
```

## Safety

This artifact records only fixed status labels and command shapes. It does not
include raw device identifiers, provisioning profile UUIDs, profile filenames,
certificate names, account identifiers, raw xcodebuild logs, hostnames,
credentials, endpoints, exact timings, frame payloads, pixels, dimensions,
coordinates, composed text, clipboard contents, or byte counts.
