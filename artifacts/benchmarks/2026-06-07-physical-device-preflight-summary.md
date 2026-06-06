# Physical Device Preflight Summary - 2026-06-07

## Scope

Add `scripts/run-naru-live-benchmark.sh physical-device-preflight` so physical
iPhone gates can fail fast before a long T030/T031 run. The mode checks:

- whether a physical iPhone is selectable through Xcode tooling
- whether an Apple Development signing identity exists locally
- whether a local development team was supplied through the environment
- whether a physical-device build reaches signing/provisioning successfully
- which fixed setup action should happen next

The mode captures and classifies `xcodebuild` output internally. It does not
print raw device names, device IDs, provisioning profile names, bundle
identifiers, raw xcodebuild logs, helper paths, live VNC credentials, or exact
timings. Device discovery is intentionally iPhone-only; a physical iPad or other
non-iPhone iOS device should not satisfy this gate.

## Commands

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help
scripts/run-naru-live-benchmark.sh physical-device-preflight
NARU_XCODE_DEVELOPMENT_TEAM=<local-development-team-id> \
  scripts/run-naru-live-benchmark.sh physical-device-preflight
```

Results:

- Without a development team environment value: the connected iPhone is detected
  and the local Apple Development identity is available, but the build check
  reports `ios-development-team-missing` with setup action
  `set-xcode-development-team`.
- With the local development team supplied: the next blockers are classified as
  `xcode-account-missing` and `ios-provisioning-profile-missing`, with setup
  actions `add-xcode-account` and
  `create-ios-development-provisioning-profile`.

## Current Next Actions

1. Add the Apple ID in Xcode Accounts.
2. Create or download an iOS development provisioning profile for the app.
3. Rerun `scripts/run-naru-live-benchmark.sh physical-device-preflight`.
4. After the physical build check passes, run the T030/T031 physical iPhone
   helper-video gates.
