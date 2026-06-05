# 2026-06-05 iPhone Touch + Compose Follow-up Summary

## Trigger

Physical iPhone feedback after PR #210: zooming and panning still felt
unnatural / stepped, and Compose input still did not work properly on the
remote Mac.

## Changes

- Lowered active viewport-interaction request cadence from 8 Hz-class to
  4 Hz-class (`0.25s`) so local Core Animation touch movement has more CPU/GPU
  room while the app keeps only the newest deferred frame.
- Reduced zoomed trackpad pan coupling from `0.55` to `0.25`; the cursor still
  travels finger-paced, but central cursor movement no longer drags the remote
  screen as aggressively.
- Restored strict Korean/CJK/emoji Compose behavior for unconfirmed VNC UTF-8:
  if no confirmed UTF-8 clipboard or reachable helper bridge exists, fail before
  writing clipboard bytes or sending paste.

## Live Benchmark

Command shape:

```bash
env NARU_LIVE_MAC_HOST=127.0.0.1 swift run VNCLiveBenchmark \
  --ask-password \
  --first-frame-profiles none \
  --stream-shape-profiles local-low-latency \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 6 \
  --stream-shape-client-pressure app \
  --stream-shape-viewport-interaction app \
  --json
```

Result: passed against the redacted local target.

Key safe aggregates:

- schema: 26
- viewport interaction content interval: 0.25 seconds
- viewport interaction pacing: 7/7 samples, 1000 permille
- transport: request-response
- received samples: 7
- content updates: 4
- empty updates: 3
- actual encoding mix: ZRLE rectangles only
- renderer uploads: 75% partial, 25% full
- average update latency: 647 ms
- p95 update latency: 2707 ms
- very slow updates: 1
- continuous-updates probe: failed with safe catalog label

## Verification

- `swift test --filter PointerGestureResolverTests`
  - Result: passed, 16 tests, 0 failures.
- `swift test --filter TrackpadModeModelTests`
  - Result: passed, 11 tests, 0 failures.
- `swift test --filter TextInjectionAdapterTests`
  - Result: passed, 8 tests, 0 failures.
- `swift test --filter NaruRemoteAppModelTests/testModelRejectsUTF8ComposeWhenClipboardSupportIsUnconfirmedWithoutHelper`
  - Result: passed, 1 test, 0 failures.
- `swift test --filter ViewportGestureRedrawThrottleTests`
  - Result: passed, 7 tests, 0 failures.
- `swift test`
  - Result: passed, 770 tests, 10 skipped, 0 failures.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: build succeeded.

## Remaining Risk

- Physical iPhone hand feel still needs retesting because simulator/unit tests
  cannot measure finger-to-glass latency or thermal throttling.
- Compose now fails honestly for unconfirmed UTF-8 without helper; the practical
  Korean/CJK path for Apple Screen Sharing remains confirmed Extended Clipboard
  UTF-8 or the host helper bridge.
