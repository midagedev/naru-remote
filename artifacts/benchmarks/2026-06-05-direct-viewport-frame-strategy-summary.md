# Direct Viewport Frame Strategy Follow-up

Date: 2026-06-05

Purpose: respond to physical iPhone feedback that zooming and panning still
felt choppy and Compose felt broken. This change separates direct local
viewport manipulation from trackpad cursor-follow frame policy.

Safety boundary: this artifact stores only aggregate command results and
behavioral conclusions. It does not include target identity, framebuffer pixels,
Compose text, credentials, endpoints, or raw timing telemetry.

## Change

- Direct pinch, direct zoomed pan, and pan deceleration now use
  `ViewportInteractionFrameStrategy.deferUntilSettled`.
  - Incoming framebuffer publication is deferred until the gesture settles.
  - Metal pending uploads are not bypassed during the direct gesture.
  - The request loop stays alive at the conservative full-frame viewport floor.
- Zoomed trackpad cursor-follow uses
  `ViewportInteractionFrameStrategy.liveRemoteFrames`.
  - Bounded dirty-rect refresh remains available for actual cursor/text echo.
- Compact Compose blocker copy now names Mac helper setup more directly when
  Korean/CJK/emoji cannot be sent through unconfirmed VNC UTF-8 clipboard.

## Verification

- Focused gesture / renderer / Compose tests:
  - `swift test --filter ViewportGestureRedrawThrottleTests --filter MetalFramebufferRendererTests --filter PointerGestureResolverTests --filter TrackpadModeModelTests --filter NaruRemoteAppModelTests/testDirectViewportInteractionDefersPartialFramesUntilGestureSettles --filter NaruRemoteAppModelTests/testModelKeepsFrameRequestsAliveWithViewportInteractionPacing --filter RemoteInputDockSyncPolicyTests --filter NaruRemoteAppSnapshotTests --filter TextInjectionAdapterTests`
  - Result: passed, 134 tests.
- Full SwiftPM suite:
  - `swift test`
  - Result: passed, 777 tests, 10 benchmark tests skipped by default.
- Opt-in synthetic frame pipeline benchmark:
  - `NARU_RUN_SIM_BENCHMARKS=1 NARU_SIM_BENCHMARK_ITERATIONS=3 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - Result: passed, 4 benchmark tests.
- iPhone simulator app build:
  - `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: build succeeded.

## Residual Risk

- Physical iPhone was visible to Xcode only as an offline device, so direct
  touch smoothness and Korean/CJK Compose must still be rechecked manually on
  the actual phone after installing this PR build.
