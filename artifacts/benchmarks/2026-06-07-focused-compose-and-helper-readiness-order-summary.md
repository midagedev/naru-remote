# Focused Compose And Helper Readiness Order Summary

Date: 2026-06-07 KST

## Purpose

Close three reproduced blockers that were making the next optimization work
point at the wrong layer:

- The readiness dashboard could report the physical iPhone gate as the primary
  blocker even when true helper-video capture was impossible because the helper
  app still lacked Screen Recording permission.
- Focused Korean/CJK Compose could still see keyboard-adjacent layout churn
  when the first new syllable cleared a previous `Remote app confirmation
  unavailable` send result.
- A ready helper text bridge was still treated as a UTF-8-only escape hatch, so
  Compose could fall back to VNC clipboard + paste and surface
  `Remote app confirmation unavailable` even when a more reliable helper insert
  route was available.

## Changes

- `remote-desktop-10fps-readiness` now prioritizes
  `blockedByHelperScreenCapture` over `blockedByPhysicalIPhone` when
  ScreenCaptureKit helper-video capture fails.
- The recommended primary action is now
  `grant-helper-video-app-screen-recording-permission`, followed by the helper
  screen probe, true helper-video live capture benchmark, physical iPhone
  preflight, and physical helper-video gate.
- Focused Compose now keeps its sibling status line mounted for the whole
  focused transaction. Clearing a stale send result after the first Korean/CJK
  syllable changes the line text back to `Ready to compose locally` instead of
  removing the line from the keyboard safe-area stack.
- Added a fixture for `active session + previous confirmation-unavailable
  Compose result` so the iPhone simulator can type `입` and then `력` through
  that status-clear path.
- Compose route selection now prefers a reachable helper text bridge for all
  non-empty payloads, including ASCII and VNC UTF-8-supported text. VNC
  clipboard + paste remains the fallback when the helper is absent or not
  known reachable, and stored-helper probing is still allowed for UTF-8 payloads
  that VNC cannot send safely.

## Current Live Readiness

Latest local run:

```bash
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness \
  > /tmp/naru-remote-desktop-10fps-readiness-action-order.json
jq '.readinessGateSummary' /tmp/naru-remote-desktop-10fps-readiness-action-order.json
```

Result:

- Overall gate state: `blockedByHelperScreenCapture`
- Recommended primary action:
  `grant-helper-video-app-screen-recording-permission`
- Blocked labels:
  `physical-iphone-gate-blocked`,
  `helper-video-screen-capture-gate-blocked`,
  `vnc-10fps-product-gate-failed`
- Helper-video synthetic transport: `pass`
- Helper ScreenCaptureKit capture: `fail`
- Screen Recording permission: `missing`
- VNC content FPS: `1.98`
- VNC average update: `505` ms
- VNC p95 update: `628` ms
- VNC first-byte wait p95: `619` ms
- Payload-read and client-processing p95 remain near zero

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh remote-desktop-readiness-summary-self-test | jq empty
swift test --filter RemoteInputDockRenderStateTests
swift test --filter NaruRemoteAppModelTests/testModelPrefersReachableHelperForComposePayloadsEvenWhenVNCPasteCouldRun
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  test \
  -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeSurvivesConfirmationStatusClearAfterFirstInput
```

All targeted checks pass. The XCUITest proves the system keyboard remains up
and the same active-session Compose editor accepts the second Korean syllable
after the previous send status is cleared. The model route test proves a
reachable helper inserts both ASCII and Korean/CJK/emoji Compose payloads
without touching the VNC clipboard or paste-command path.

## Interpretation

The practical design direction is unchanged but sharper:

- VNC remains the reliable control/input/fallback transport.
- The current VNC visual stream is still not product-grade for sustained iPhone
  use because first-byte wait dominates and content FPS is about `2`.
- The next smoothness gate must unblock true helper ScreenCaptureKit capture
  first, then run the helper-video live capture benchmark, then rerun the
  physical iPhone hand-feel/thermal/Compose gate.
- Focused Compose must be treated as a UIKit-owned transaction. Model mirrors,
  stream frames, helper status, and send-result cleanup can update diagnostics,
  but they must not remount or resize the hot input stack while iOS IME owns the
  keyboard.
- Compose text delivery should be helper-first when the helper is reachable.
  VNC clipboard + paste is useful as a compatibility fallback, but its
  confirmation-unavailable result must not remain the primary path once a
  direct helper insertion route is ready.

## Privacy

This artifact records only fixed gate/action labels, aggregate timing/FPS
metrics, fixed UI state names, and test names. It does not include host
identity, credentials, helper endpoints, helper paths, physical device
identifiers, framebuffer dimensions, pixels, coordinates, byte counts, raw
logs, exact helper timings, live Compose text, marked text, or IME state.
