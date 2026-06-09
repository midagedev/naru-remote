# Physical Signing Doctor Summary - 2026-06-10

## Scope

Make the physical iPhone preflight diagnose signing/provisioning blockers well
enough for the next operator action, without exposing device, account, team,
profile, bundle, helper, host, or credential details.

## Result

The current live `physical-device-preflight` run reports:

- Physical iPhone status: `connected`
- Build check status: `failed`
- Xcode account status: `missing`
- Provisioning profile status: `missing`
- Signing readiness state: `blocked`
- Primary blocked gate: `xcode-account`
- Recommended primary action: `open-xcode-account-settings`
- Operator action sequence:
  - `open-xcode-account-settings`
  - `sign-in-to-xcode-account-for-development-team`
  - `rerun-physical-device-preflight`
  - `rerun-physical-iphone-helper-video-gate`
- Diagnostic labels:
  - `development-team-supplied-by-environment`
  - `xcode-account-unavailable-to-xcodebuild`
  - `development-team-supplied-but-xcode-account-missing`
  - `provisioning-cannot-be-validated-until-xcode-account-is-available`
- Legacy issue codes remain:
  - `xcode-account-missing`
  - `ios-provisioning-profile-missing`

A live integrated `remote-desktop-10fps-readiness` run also preserved the nested
physical signing summary. Its top-level gate was `blockedByHelperScreenCapture`
because the helper ScreenCaptureKit probe reported `sustainedDegraded` /
`stalled`; the VNC fallback still failed the product gate at about `1.95`
content FPS, with request/response transport at about `6.91` content FPS and
ContinuousUpdates `failed-before-samples`.

Interpretation:

- The physical iPhone is visible to the runner.
- A development team value is already supplied through the environment.
- The first actionable blocker is that xcodebuild cannot use an Xcode account
  for that team yet.
- The provisioning result should be treated as downstream until the Xcode
  account is visible and preflight is rerun.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh physical-signing-setup-summary-self-test
scripts/run-naru-live-benchmark.sh helper-video-live-gate-self-test
scripts/run-naru-live-benchmark.sh remote-desktop-readiness-summary-self-test
scripts/run-naru-live-benchmark.sh physical-device-preflight
```

## Safety

The artifact records only fixed status, action, and diagnostic labels. It does
not include account names, team names, provisioning profile names, bundle
identifiers, physical device identifiers, raw xcodebuild logs, helper paths,
host values, credentials, screenshots, pixels, byte counts, exact timings,
Compose text, marked text, keysyms, pointer coordinates, or clipboard contents.
