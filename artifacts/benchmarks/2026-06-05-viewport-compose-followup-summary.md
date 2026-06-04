# 2026-06-05 Viewport + Compose Follow-up

## Trigger

Physical-device report: zooming and panning still felt unnatural/stuttery, and
Compose input was not working reliably.

## Findings

- Viewport gestures were still calling `MTKView.draw()` synchronously from touch
  callbacks. On a physical iPhone this can make touch handling compete with
  renderer work.
- Zoomed one-finger pan still waited for long-press failure, adding avoidable
  startup latency before the viewport follows the finger.
- Direct pinch/pan/deceleration state mirroring was deferred to gesture end,
  which reduced per-touch SwiftUI work but could leave overlays/PiP focus visibly
  behind the Metal view.
- Legacy RFB `ClientCutText` is not a reliable Unicode path. The rfbproto
  Extended Clipboard pseudo-encoding (`0xc0a1e5ce`) defines negative
  `ClientCutText`/`ServerCutText` lengths and zlib-compressed UTF-8 payloads for
  servers that confirm support.

## Changes

- Coalesced Metal viewport redraw to display-link cadence and flushes the latest
  requested draw at gesture end.
- Removed the zoomed pan dependency on long-press failure so local panning can
  start as soon as UIKit classifies movement.
- Returned direct pinch, zoomed pan, and pan deceleration SwiftUI/PiP mirroring
  to display-link cadence while keeping renderer state immediate.
- Added Extended Clipboard advertisement, caps parsing, zlib-wrapped UTF-8 text
  provide encoding/decoding, server-support gating, legacy fallback, safe
  diagnostic code mapping, and fake-server signed-length handling.

## Verification

- `swift test --filter RFBClientMessageEncoderTests --filter RFBProtocolDecoderTests --filter RFBEncodingTests --filter FakeRFBServerIntegrationTests/testProductionRFBNetworkClientUsesExtendedClipboardAfterServerCaps`
  - Result: passed, 44 tests, 0 failures.
- `swift test --filter FakeRFBServerIntegrationTests/testFirstFrameConnectionSkipsExtendedClipboardCapsBeforeUpdateHeader --filter FakeRFBServerIntegrationTests/testProductionRFBNetworkClientUsesExtendedClipboardAfterServerCaps`
  - Result: passed, 2 tests, 0 failures.
- `swift test`
  - Result: passed, 617 tests, 10 skipped, 0 failures.
- `xcodegen generate --spec project.yml`
  - Result: passed.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build`
  - Result: passed.
- `NARU_LIVE_MAC_HOST=127.0.0.1 NARU_LIVE_MAC_PORT=5900 NARU_LIVE_MAC_PASSWORD='[redacted]' swift test --filter FakeRFBServerKitTests.LiveMacRFBSmokeTests/testStreamingSessionMirrorsConnectButtonPathAgainstRealMac`
  - Result: passed, connectSession ~= 0.55s, firstFramePump ~= 3.12s.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - Result: passed, 4 benchmarks, 0 failures.
  - Approximate monotonic-time averages: full allocation/upload ~= 2ms,
    steady-state full upload ~= 1ms, small-dirty and same-frame skip paths
    sub-millisecond.

## Remaining Risk

- Physical iPhone feel still needs manual retest because XCTest cannot measure
  touch latency/thermal behavior from a real hand.
- Real macOS Screen Sharing may or may not confirm Extended Clipboard support.
  If it does not, Naru will safely fall back to legacy `ClientCutText`, which may
  still be insufficient for Korean/CJK Compose on that server.
