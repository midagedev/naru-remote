# Physical iPad Preflight Summary

Date: 2026-06-14 KST

## Question

The operator reported that the app did not appear to launch on the connected
iPad and that the test seemed to start briefly and then finish. This check
separates physical iPad discovery from Xcode signing/provisioning and app
launch.

## Command

```bash
bash scripts/run-naru-live-benchmark.sh physical-ipad-device-preflight
```

## Safe Result

- `targetDeviceClass`: `iPad`
- `resolvedDeviceClass`: `iPad`
- `deviceDiscoveryStatus`: `connected`
- `deviceSelectionSource`: `auto`
- `deviceUnlockedSinceBootStatus`: `true`
- `codeSigningIdentityStatus`: `available`
- `developmentTeamStatus`: `environment`
- `xcodeAccountStatus`: `missing`
- `provisioningProfileStatus`: `missing`
- `buildCheckStatus`: `failed`
- `primaryBlockedGateLabel`: `xcode-account`
- `recommendedPrimaryAction`: `open-xcode-account-settings`
- `issueCodes`: `xcode-account-missing`,
  `ios-provisioning-profile-missing`

## Interpretation

The iPad is reachable and selected as an iPad, but the build does not reach the
app launch or UI test stage in this execution context. Xcodebuild cannot use an
available Xcode account and cannot find an iOS App Development provisioning
profile for the app bundle on the selected iPad.

This means a short or disappearing test run should be treated as a
signing/provisioning setup blocker first, not as evidence of an app runtime
freeze.

## Follow-Up

1. Open Xcode account settings and ensure the local account for the configured
   development team is available to command-line xcodebuild.
2. Create or refresh the iOS Development provisioning profile for the app bundle
   so it includes the connected iPad.
3. Rerun:

   ```bash
   bash scripts/run-naru-live-benchmark.sh physical-ipad-device-preflight
   ```

4. Only after `buildCheckStatus=passed`, run the physical iPad install/launch
   smoke and then the sustained session checks.

## Regression

`physical-ipad-device-preflight-self-test` stubs the physical iPad discovery and
xcodebuild output so the `No Accounts` / `No profiles for` patterns stay pinned
to `xcode-account-missing`, `ios-provisioning-profile-missing`, and the
`open-xcode-account-settings` primary action without requiring a connected
device.

## Privacy

The preflight emits only fixed labels. It does not export device identifiers,
device names, raw xcodebuild logs, account IDs, team IDs, hostnames, endpoints,
framebuffer pixels, input coordinates, keysyms, text, clipboard contents, or
exact timing samples.
