# Best-Effort Buttonless Pointer Move Summary

Date: 2026-06-07

## Goal

Physical iPhone feedback still described trackpad movement as half-beat late,
and earlier regressions showed that input could feel frozen after socket
pressure. PR #379 split app-level pointer and key dispatchers, but a single
buttonless trackpad move could still wait for Network.framework
`contentProcessed` inside the pointer write operation.

This pass targets that concrete remaining input-path blocker: plain trackpad
cursor-follow moves are latest-value state, so they do not need reliable
per-sample completion waiting.

## Design

- Added `RFBBestEffortPointerEventClient` as an optional capability for a
  single buttonless (`0x00`) cursor-follow `PointerEvent`.
- `RFBNetworkClient` adopts the capability and sends the encoded pointer event
  without waiting for `contentProcessed`.
- The app model uses the best-effort path only when a pointer dispatch contains
  exactly one released/buttonless command.
- Clicks, drags, scroll, and key events remain on reliable ordered writes.
- The production client rejects non-zero best-effort button masks.

## Verification

- `swift test --filter DirectKeystrokeModeTests`
  - Proves a delayed reliable pointer fake does not delay a best-effort
    buttonless trackpad move.
  - Proves a trackpad click does not use the best-effort path.
  - Re-runs the prior key/pointer lane timeout regressions.
- `swift test --filter FakeRFBServerIntegrationTests/testProductionRFBNetworkClientSendsBestEffortPointerMoveAfterInteractiveHandshake`
  - Proves the production `RFBNetworkClient` best-effort path still delivers a
    normal RFB pointer event to the fake server.
- `swift test --filter FakeRFBServerIntegrationTests/testBestEffortPointerMoveRejectsPressedButtonMasks`
  - Proves the fast path cannot be used for button-down/click semantics.
- `swift test --filter BenchmarkFailureLabelTests`
  - Proves new error reporting stays on safe catalog labels.
- `swift test`
  - Re-run passed: 1196 tests, 14 skipped, 0 failures.
  - A previous full-suite run reported one failure, but the focused suites and
    the full-suite re-run did not reproduce it.

## Remaining Risk

This does not by itself raise VNC frame FPS. It removes one input-path blocking
point that can make trackpad motion and subsequent keyboard input feel frozen
while the live VNC stream is under backpressure. Physical iPhone retesting is
still required to confirm hand-feel improvement under real Screen Sharing load.
