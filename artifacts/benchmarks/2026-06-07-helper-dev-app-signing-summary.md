# Helper Dev App Signing Summary - 2026-06-07

## Scope

Improve `scripts/install-naru-helper-dev-app.sh` so the development-only
`NaruHelperDev.app` wrapper is a more stable macOS Screen Recording permission
target for helper-video benchmarks.

The installer now:

- keeps explicit `--signing-identity` or `NARU_HELPER_DEV_CODESIGN_IDENTITY`
  selection available for local override
- uses exactly one local Apple Development identity when `auto` is selected and
  one is available
- falls back to ad-hoc signing when no unambiguous Apple Development identity is
  available
- prints only fixed signing labels such as `appleDevelopment`, `adHoc`, or
  `explicit`
- keeps raw signing identities, Team IDs, helper paths, host names, credentials,
  endpoints, frame content, display dimensions, byte counts, and raw OS errors
  out of committed artifacts

## Verification

```bash
bash -n scripts/install-naru-helper-dev-app.sh
scripts/install-naru-helper-dev-app.sh --help
scripts/install-naru-helper-dev-app.sh --set-launchctl-env
scripts/run-naru-live-benchmark.sh helper-synthetic-probe
NARU_HELPER_SCREEN_RECORDING_SETTINGS_OPEN=skip \
  scripts/run-naru-live-benchmark.sh screen-recording-setup
```

Current safe result:

- helper dev app install: `passed`
- signing label: `appleDevelopment`
- helper process kind: `appBundle`
- helper grant hint: `grantAppBundle`
- helper synthetic probe: `pass`
- Screen Recording permission: `missing`
- setup next action: grant Screen Recording to `NaruHelperDev`, then rerun
  `scripts/run-naru-live-benchmark.sh helper-readiness-sweep`

## Research Note

Apple developer guidance and forum reports indicate Screen Recording permission
is tied to app identity/signing. Ad-hoc development signing can make a rebuilt
app appear like a different permission target, so the dev wrapper now prefers a
stable Apple Development identity when local state is unambiguous.
