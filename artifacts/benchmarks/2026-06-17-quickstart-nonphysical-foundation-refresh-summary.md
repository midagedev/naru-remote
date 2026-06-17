# Quickstart Non-Physical Foundation Refresh - 2026-06-17

## Scope

This artifact records a non-physical quickstart refresh for the helper-video
foundation, diagnostics, visual-transport benchmark reports, connection
profiles, and app-model helper-video routing tests.

This is not a full `quickstart.md` completion claim. The quickstart still
contains live helper, ScreenCaptureKit, physical iPhone, and provisioning-gated
commands that require environment changes before they should be rerun.

## Readiness Command Fix

The original readiness command searched the entire feature directory for the
plain text `NEEDS CLARIFICATION`, so it matched the quickstart command itself
and the completed task note in `tasks.md`.

Fix applied:

```bash
! rg -n "\[NEEDS CLARIFICATION\]" \
  specs/007-host-helper-video-stream/spec.md \
  specs/007-host-helper-video-stream/plan.md \
  specs/007-host-helper-video-stream/research.md \
  specs/007-host-helper-video-stream/contracts
```

Result:

- No bracketed clarification markers found in the authoritative feature
  design/contract files.
- `tasks.md` and `quickstart.md` can still mention the phrase as documentation
  without failing the readiness check.

## Harness Stability Fix

The first non-physical foundation run found one selected-suite flake:

- `NaruHelperVideoListenRuntimeTests/testExternalHelperProcessSendsSustainedSyntheticEncodedStream`
  timed out when run after the larger helper-video report/test slice.
- The same test passed alone in `0.638s`, which narrowed the failure to a
  too-tight external helper process / synthetic VideoToolbox startup timeout
  under suite load.

Fix applied:

- The synthetic encoded stream listen-runtime tests now use a small
  frame-budget-aware timeout floor instead of a fixed `3s` client timeout.
  This affects the test harness only.

## Verification

Command:

```bash
set -o pipefail
! rg -n "\[NEEDS CLARIFICATION\]" \
  specs/007-host-helper-video-stream/spec.md \
  specs/007-host-helper-video-stream/plan.md \
  specs/007-host-helper-video-stream/research.md \
  specs/007-host-helper-video-stream/contracts
swift test --filter 'HelperVideo|HelperVideoFakeTransportTests|DiagnosticExportTests|BenchmarkHelperVideoReportTests|BenchmarkVisualTransport|ConnectionProfileTests'
```

Log:

```text
/tmp/naru-quickstart-foundation-nonphysical-20260617-rerun.log
```

Result:

- `readiness=passed`
- `swift test selected foundation slice=passed`
- Executed tests: `234`
- Skipped tests: `7`
- Failures: `0`

## Remaining Risk

- `TXXX Run all checks listed in quickstart.md` remains open. This refresh
  covers only the non-physical foundation/app-model slice.
- T030 physical iPhone + Mac manual verification remains open and currently
  blocked by Xcode account / exact development provisioning profile setup.
- Live ScreenCaptureKit/helper-video and physical iPhone commands should be
  rerun only after the relevant permission/signing environment changes.

## Privacy

This artifact contains only command names, fixed test names, aggregate counts,
and local log paths. It omits hostnames, endpoints, credentials, profile
fingerprints, pairing material, helper executable paths, physical device
identifiers, provisioning profile names, team identifiers, bundle identifiers,
raw xcodebuild logs, frame pixels, dimensions, coordinates, byte counts,
composed text, clipboard contents, and exact timing series.
