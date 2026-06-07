# Frame Apply Backpressure Summary - 2026-06-07

## Scope

This increment follows the physical-iPhone report that a real VNC connection
can make gestures and keyboard input stop responding as soon as frames begin
flowing. PR #357 moved Metal framebuffer staging off the MainActor; this
follow-up links the already-bounded MainActor frame-application backlog to the
stream pacing loop.

No host names, credentials, ports, frame contents, framebuffer dimensions,
coordinates, pixels, byte counts, raw per-frame timings, raw TCP/RFB errors,
draft text, marked text, keysyms, pointer coordinates, screenshots, or device
identifiers are recorded here.

## Research Notes

- RFC 6143 frames RFB updates as client-driven: the client requests framebuffer
  updates, and incremental updates let the server send only changes. On a phone,
  if the UI apply path is already behind, requesting more updates immediately
  adds local decode/apply pressure without improving the user-visible state.
- Apple Metal guidance recommends avoiding CPU/GPU stalls and managing the
  rate of CPU work relative to GPU work. For Naru, the same principle applies
  one layer higher: if the UI apply queue coalesces stale frames, the stream
  should temporarily reduce request/decode pressure instead of building a new
  backlog.
- Apple's frame-rate guidance emphasizes a stable target cadence over trying
  to perform more work than fits in the frame budget. The app already has a
  power-saver pacing floor; this patch reuses it when frame-application backlog
  proves that local presentation is lagging.

Sources:

- https://www.rfc-editor.org/rfc/rfc6143
- https://developer.apple.com/documentation/Metal/synchronizing-cpu-and-gpu-work
- https://developer-mdn.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html

## Benchmark Context

Recent redacted benchmark artifacts show that the VNC visual path is still
below the product-grade 10fps target:

- `2026-06-07-remote-desktop-10fps-target-summary.md`: current VNC
  request/response path recorded about 2 content FPS and failed
  `iphone-remote-desktop-10fps-v1`.
- `2026-06-07-remote-desktop-10fps-readiness-summary.md`: helper synthetic
  H.264 passed, while live helper ScreenCaptureKit remained blocked by Screen
  Recording permission. VNC remains important as input/control/fallback, but
  not yet as the smooth visual path.

This change is therefore not a production default promotion and not a claim
that VNC now reaches the 10fps bar. It is a responsiveness guard: when the app
detects UI frame-apply backlog, the receive/decode loop backs off temporarily
so touch tracking and keyboard input have room to recover.

## Change

- `SessionStreamFrameApplicationQueue.enqueue` already returns the number of
  stale work items dropped while coalescing to the initial frame, latest content
  frame, and latest cursor update.
- The stream loop now forwards that dropped-work count into
  `SessionStreamPressurePacingState`.
- A small backlog drop activates the short one-spike cooldown; a larger drop
  activates the longer adaptive recovery window.
- Existing diagnostics continue to expose only aggregate adaptive pacing
  activation, not raw frame contents or queue contents.

## Verification

Completed verification:

```bash
swift test --filter NaruRemoteAppTests.NaruRemoteAppModelTests/testSessionStreamPressurePacingState
swift test --filter NaruRemoteAppTests.NaruRemoteAppModelTests
NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
swift test
scripts/run-naru-live-benchmark.sh physical-team-inference-self-test
scripts/run-naru-live-benchmark.sh physical-device-preflight
```

The focused tests prove that:

- a single frame-application backlog drop activates adaptive pacing briefly;
- a larger coalescing drop keeps the pacing floor active longer;
- the behavior reuses existing pressure state and does not alter persisted
  stream power mode.

The full test run executed 1145 tests with 13 skipped and no failures. The
simulator app build succeeded. Physical-device preflight found the iPhone and
code-signing identity, but build/install verification is still blocked by the
local Xcode account/provisioning setup:

- `xcode-account-missing`
- `ios-provisioning-profile-missing`

## Next Gate

After merge, rerun the physical sustained candidate gate once Xcode
provisioning is available. The key physical question is whether gestures,
trackpad cursor movement, and Compose input keep responding during the first
seconds after a real VNC session starts.
