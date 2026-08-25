# TestFlight upload — 1.0.0 (build 8)

- Uploaded: 2026-08-25 14:37 KST
- Commit: 7fda9d18 (dirty tree — the only uncommitted change was
  `CURRENT_PROJECT_VERSION: 7 → 8` in `project.yml`, written by `--bump`
  immediately before the archive, and committed straight after this record)
- Bundle: com.naruremote.app, team XEF9KH7N43

## Why this build exists

The founder reported build 7 frozen: frames arriving, picture not updating, one
frame after a trip through the background. **This build does not claim to fix
that** — it makes it answerable.

- **spec 028** — a frame can no longer disappear between the frame store and the
  screen without naming a reason. Both presentation-gating latches are now
  bounded by watchdogs; the upload-suspension latch previously had no release
  path other than the gesture-finish that set it (proven against build 7's own
  source: twelve frames held over six seconds, none presented).
- The diagnostic export now carries `framePresentationPublishedCount`,
  `framePresentationPresentedCount`, `framePresentationPresentedPermille`,
  `framePresentationHeldReason` (fixed catalog) and
  `framePresentationWatchdogReleaseCount`. The perf HUD is DEBUG-only, so on a
  TestFlight build **the export is the readout**.

## What to do on the device when it freezes

Reproduce the freeze, then export diagnostics from the session's diagnostics
sheet. The three numbers that matter:

- `framePresentationPresentedCount` far below `framePresentationPublishedCount`
  → frames arrived and did not reach the screen. That is the founder's symptom,
  now measured rather than described.
- `framePresentationHeldReason` → which stage held them. Fixed labels:
  `heldBySuspension`, `heldByGesture`, `heldByThrottle`, `superseded`,
  `duplicateSuppressed`, `abandonedOnSizeMismatch`, `restagedOnSizeMismatch`.
- `framePresentationWatchdogReleaseCount` > 0 → a latch had to release itself,
  i.e. the freeze happened and the app recovered from it on its own.

If the picture now recovers after a few seconds instead of staying dead, that is
the watchdog, and the count says so.

## Known limits of this build

- The rewritten liveness gate **does not reproduce the freeze** in the simulator
  against loopback Screen Sharing (26 presented / 26 pumped, no stall). The
  device is still the only place this has been seen.
- Two earlier red gate runs during this work were instrumentation defects in
  spec 028 itself, not app defects; both are recorded in the spec.
- specs 024/026 phone-side gains (bandwidth, power, thermals) remain **inferred,
  not measured**, carried over from build 7.
- spec 023 T006 device pass is still outstanding from build 7.

- Archive contract: version/build, bundle id, MinimumOSVersion 17.0,
  ITSAppUsesNonExemptEncryption=false, PrivacyInfo.xcprivacy present,
  no NARU_TEST_* hooks in the Release binary — all verified pre-upload.
- altool: VERIFY SUCCEEDED, UPLOAD SUCCEEDED.
- App Store Connect processingState: VALID

Produced by `scripts/testflight-upload.sh`. Credentials were read from
~/.appstoreconnect and are not recorded here.
