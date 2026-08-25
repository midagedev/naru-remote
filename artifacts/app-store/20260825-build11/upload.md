# TestFlight upload — 1.0.0 (build 11)

- Uploaded: 2026-08-25 21:37 KST
- Commit: 7515d2fa (dirty tree)
- Bundle: com.naruremote.app, team XEF9KH7N43
- Archive contract: version/build, bundle id, MinimumOSVersion 17.0,
  ITSAppUsesNonExemptEncryption=false, PrivacyInfo.xcprivacy present,
  no NARU_TEST_* hooks in the Release binary — all verified pre-upload.
- altool: VERIFY SUCCEEDED, UPLOAD SUCCEEDED.
- App Store Connect processingState: VALID

Produced by `scripts/testflight-upload.sh`. Credentials were read from
~/.appstoreconnect and are not recorded here.

## Why this build exists

Three things the founder reported or asked for on build 10, in one message.

**PiP twice killed the app (spec 032).** Entering PiP Watch a second time in one
session terminated it. The simulator cannot reproduce this —
`AVPictureInPictureController.isPictureInPictureSupported()` is false on the
iPhone 17 Pro simulator (iOS 26.2), so the re-entry UITest skips there — which is
why three hazards are closed together rather than one being confirmed and fixed:
a second controller constructed over the same `AVSampleBufferDisplayLayer` on
every entry, an unguarded `startPictureInPicture()`, and a finite `Int64.max`
playback duration. The fourth defect is why the crash was invisible: the
`AVPictureInPictureControllerDelegate` conformance was empty, so closing the
floating window from the system chrome told the app nothing and the next entry
was taken against a state that was already wrong.

**The session chrome was recomposed (spec 033).** PiP moved out of the
auto-hiding `⋯` menu into the control bar as a state-aware toggle; the idle
dock's `Type` + `Compose` pills became one capsule with the switch inside it;
the health capsule collapses to a 28-point icon while the session is healthy and
only stands alone, labelled, when it has something to say. The 248x44 capsule
that said "Connected · Good" permanently is gone.

**PiP framing is now a choice (spec 034).** A tap enters on the current view; a
long press offers Current view, Follow activity (automatic, from the damage
rectangles the RFB layer already decodes), and a region drawn by hand.

## What to check on the device

1. **PiP twice.** Enter PiP, come back, enter again. Then close the floating
   window from the system chrome and enter again. This is the report that
   opened spec 032 and the only place it can be confirmed.
2. **Is the PiP window readable**, and does **Follow activity** land on the
   terminal that is printing? The legible band it aims for (~750 px of crop
   width) is arithmetic — 3024 ÷ the app's 4x zoom ceiling — not a measurement
   of a real PiP window, which no simulator can produce. If it is wrong, the
   constants move.
3. **Is PiP findable now**, and does the dock read as one control rather than
   two?
4. **A good session should show no status furniture** — just a small green tick
   in the bar. When something goes wrong, an amber chip should appear over the
   remote screen and stay visible even after the bar auto-hides.
5. Still open from build 9/10: `contentFramesPerSecond` out of `underFive`, and
   the **unmeasured bandwidth half** of full-resolution + full-frame incremental
   requests (data use, heat, stutter on cellular).

## Known limits

- **The client's upscaler is still a single linear tap**, deliberately untouched
  since build 10 so the resolution default and a sharper filter stay separately
  attributable. Zoomed-in text will still soften.
- Automatic framing's dead zone and cooldown are tuned for a busy terminal,
  which is the founder's workload; switching windows on the Mac may feel
  sluggish by comparison. One constant cannot be right for both.
- The drawn region is session-scoped by design. The *mode* persists, so a
  relaunch can land on "Chosen region" with nothing drawn — that behaves as
  Current view, and the menu says Current view.
- Two simulator gates are red for reasons outside this build, both recorded in
  `NEXT_STEPS.md`: the App Store 6.9" slot captures need an iPhone 17 Pro Max
  runner, and `testWrongPassword` cannot produce its outcome against this Mac
  (measured with a raw socket: `screensharingd` issues a VNC challenge and then
  never sends a SecurityResult for a wrong password, while the correct one
  returns 0 immediately).
