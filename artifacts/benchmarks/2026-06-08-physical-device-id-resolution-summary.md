# Physical Device ID Resolution Summary

Date: 2026-06-08 KST

## Question

Can the physical iPhone preflight accept the identifier users most often copy
from `devicectl`, while still running the xcodebuild build check against the
identifier xcodebuild expects?

## Reproduction

`devicectl` showed the connected iPhone with a CoreDevice identifier. Passing
that visible identifier directly to xcodebuild made xcodebuild report that no
matching destination was available, even though the same device was listed with
a separate xcodebuild destination id.

## Decision

`physical-device-preflight` now resolves `NARU_PHYSICAL_IOS_DEVICE_ID` through
devicectl JSON:

- xcodebuild UDID input remains direct.
- CoreDevice identifier input is mapped to `hardwareProperties.udid`.
- auto-selection still uses the first connected iPhone xcodebuild UDID.
- JSON exports only the fixed `deviceIDResolutionStatus` label.

## Verification

- `bash -n scripts/run-naru-live-benchmark.sh`
- `scripts/run-naru-live-benchmark.sh physical-device-id-resolution-self-test`
- CoreDevice identifier preflight returned:
  - `deviceDiscoveryStatus=connected`
  - `deviceSelectionSource=environment`
  - `deviceIDResolutionStatus=environmentCoreDeviceIdentifierMapped`
  - residual signing blocker labels:
    `xcode-account-missing`, `ios-provisioning-profile-missing`

## Residual Gate

The connected iPhone is discoverable, but physical install/build remains blocked
until Xcode has an account and a development provisioning profile for the app
bundle.
