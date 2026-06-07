# 2026-06-08 UI/Input/Gesture Service-Level Summary

## Reproduced Symptom

Physical iPhone feedback showed that the remaining issue was not just low VNC
FPS. Compose could still feel frozen after a first Korean character, and
zoomed trackpad navigation felt a half-beat behind the finger. The reproduced
design failure was that text input, viewport gestures, transient pointer/key
input, and steady visual frame delivery still shared one broad interactive
frame-delivery priority.

## Design Change

- Split frame delivery priority into `visual`, `viewportNavigation`, and
  `textInput`.
- Make focused Compose use the strongest text-input priority, and make it win
  over viewport/transient interaction priority until focus leaves.
- Keep visual pan/zoom on the UIKit/Core Animation hot path, but publish
  viewport transform state at display-link cadence so viewport-aware VNC
  request regions follow the visible screen while the gesture is still active.
- Increase zoomed trackpad cursor-follow pan coupling so the actual cursor and
  local viewport move together while visible cursor travel remains finger-paced.

## Verification

```text
swift test --filter SessionFrameStoreTests --filter SessionFrameDeliveryPriorityModelTests --filter SessionViewportViewGeometryTests --filter PointerGestureResolverTests
```

Result: passed, 57 selected tests.

```text
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests test
```

Result: passed, 5 UI tests. The simulator accepted the second Korean syllable
after the first input in profile-detail, active compact, stale confirmation
clear, cursor-storm, and framebuffer-flood plus cursor-storm fixtures.

```text
swift test
```

Result: passed, 1238 tests, 14 skipped.

```text
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

Result: wrapper passed, but the product gate remains blocked. VNC content FPS
was 1.91 against the 10fps target, average update latency was 479ms, p95 update
latency was 632ms, first-byte wait p95 was 628ms, and client-processing p95 was
5ms. The primary constraint is still `receivePath` /
`first-byte-wait-dominated`. Synthetic and sustained synthetic helper-video
passed, while true ScreenCaptureKit helper-video remains blocked by missing
Screen Recording permission for the helper app bundle.

## Residual Risk

This does not change the live VNC server cadence blocker: the latest readiness
evidence still routes smooth visual promotion through helper-video
ScreenCaptureKit permission and physical iPhone validation. Physical iPhone
preflight also reported missing Xcode account/provisioning setup, so the next
visual-smoothness gate is: grant Screen Recording to the helper app, rerun the
helper screen probe, resolve physical-device signing, then run the true
helper-video physical iPhone gate. This change reduces UI/input contention and
makes viewport-aware traffic follow local navigation more directly while that
helper-video path is still blocked.
