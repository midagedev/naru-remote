# Physical Device Team Inference Summary - 2026-06-07

## Scope

Improve `scripts/run-naru-live-benchmark.sh physical-device-preflight` so the
T030/T031 iPhone gate can advance when the developer has exactly one local
Apple Development signing team but has not exported
`NARU_XCODE_DEVELOPMENT_TEAM`.

The runner now:

- keeps explicit `NARU_XCODE_DEVELOPMENT_TEAM` as the highest-priority source
- infers a development team only when exactly one Apple Development team is
  present locally
- passes the inferred team only to the captured `xcodebuild` child process
- reports only fixed labels such as `developmentTeamStatus=inferred`
- keeps raw Team IDs, device IDs, device names, bundle identifiers,
  provisioning profile names, raw xcodebuild logs, helper paths, and live VNC
  credentials out of output and committed artifacts

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh physical-team-inference-self-test
scripts/run-naru-live-benchmark.sh physical-device-preflight
```

Current safe result:

- inference self-test: `passed`
- physical iPhone discovery: `connected`
- signing identity: `available`
- development team: `inferred`
- build check: `failed`
- next setup labels: `add-xcode-account`,
  `create-ios-development-provisioning-profile`

## Current Next Actions

1. Add the Apple ID in Xcode Accounts.
2. Create or download an iOS development provisioning profile for the app.
3. Rerun `scripts/run-naru-live-benchmark.sh physical-device-preflight`.
4. After the physical build check passes and Screen Recording is granted to
   `NaruHelperDev`, run the T030/T031 physical iPhone helper-video gates.
