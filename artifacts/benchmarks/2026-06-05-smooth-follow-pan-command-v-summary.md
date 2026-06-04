# 2026-06-05 Smooth Follow-Pan + Command-V Summary

## Trigger

Physical-device report after PR #156: zooming and panning still felt unnatural
and choppy, and Compose input did not reliably appear on the remote Mac.

## Findings

- Zoomed trackpad auto-pan used a viewport-relative follow margin of 44% of the
  shortest side. On a phone-sized viewport, that leaves only a narrow central
  band before auto-pan snaps the viewport back toward the cursor.
- `PointerGestureResolver` applied the full `panToReveal` delta in one sample.
  A representative 200x100pt zoomed viewport moved from `0pt` to `-48pt` pan
  after one 100pt trackpad drag callback.
- The Metal viewport redraw path coalesced redraws to display-link cadence, but
  each redraw tick invalidated the display link. During a continuous gesture,
  the app repeatedly created and destroyed the scheduler.
- Compose's default `.commandV` paste command sent `Alt_L+v`. Naru's Direct
  keyboard path maps Command to `Meta_L`; on macOS, `Alt_L` is Option and is
  not the normal paste modifier.
- The compact active-session Compose editor was visible on screen but exposed
  through UIKit as a `UITextView` while screenshot tests were still querying a
  `TextField`. The outer editor shell also did not explicitly focus the UIKit
  editor when users tapped the styled empty area.

## Changes

- Trackpad auto-pan now uses a 28% viewport-relative follow zone and applies a
  damped, capped portion of the reveal delta each touch sample.
- The same representative zoomed trackpad case now returns `-16.8pt` pan,
  reducing one-sample viewport jumps while still following the cursor over
  successive frames.
- The Metal viewport redraw display link stays alive while a viewport gesture
  or pan deceleration is active, and stops only after the pending redraw queue is
  idle.
- Compose `.commandV` now emits `Meta_L+v`, matching Direct-mode Command key
  handling for macOS VNC targets.
- The compact Compose `UITextView` now carries the production accessibility
  label/identifier itself, and tapping the full visible editor box forwards
  focus to the UIKit text view so the iOS keyboard rises from the compact dock.

## Verification

- `swift test --filter PointerGestureResolverTests --filter TrackpadModeModelTests/testTrackpadDragUsesZoomedTransformAndReturnsAutoPan --filter RFBClientMessageEncoderTests/testCommandVPasteUsesMetaLeftMapping`
  - Result: passed, 14 tests, 0 failures.
- `swift test --filter RFBClientMessageEncoderTests --filter PointerGestureResolverTests --filter TrackpadModeModelTests`
  - Result: passed, 38 tests, 0 failures.
- `swift test`
  - Result: passed, 628 tests, 10 skipped, 0 failures.
- `xcodegen generate --spec project.yml`
  - Result: passed.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: passed.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - Result: passed, 4 benchmarks, 0 failures.
  - Approximate monotonic-time averages: full allocation/upload ~= 2.4ms,
    steady-state full upload ~= 0.46ms, small-dirty upload ~= 0.02ms,
    same-frame upload-gate skip ~= 0.003ms.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test`
  - Result: failed, 45 UI tests executed, 2 skipped, 12 failures.
  - Failures were concentrated in pre-existing screenshot/launch/auth scenarios
    and the compact active-session editor query before the focused fix.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveWidescreen_dark -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveWidescreen_light -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveTrackpadCursor_dark -only-testing:NaruRemoteUITests/UXAuditScreenshotsUITests/testSessionActiveTrackpadCursor_light`
  - Result: passed, 4 UI tests, 0 failures. Verified compact active-session
    editor discovery and keyboard presentation after tapping the editor.

## Remaining Risk

- Physical iPhone hand feel still needs retesting because simulator/unit tests
  cannot measure finger-to-glass latency or thermal throttling.
- If a specific VNC server expects a nonstandard Command-key keysym, Compose may
  still need a profile-level paste-modifier option. The app's default is now
  aligned with its own Direct-mode Command mapping and the macOS target path.
- Compact Compose now focuses correctly in simulator, but physical iPhone
  Korean/CJK marked-text send still needs the manual retest tracked by T033.
