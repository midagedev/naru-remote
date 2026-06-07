# Frame Apply Worker Cadence Summary - 2026-06-07

## Scope

Physical iPhone testing still reports that real VNC sessions can feel frozen
as soon as frames begin flowing. PRs #354, #355, #357, and #358 separated the
receive loop, bounded frame-application backlog, moved Metal staging off the
MainActor, and fed backlog pressure into stream pacing. This increment adds a
small cadence floor inside the remaining MainActor frame-application worker.

No host names, credentials, ports, frame contents, framebuffer dimensions,
coordinates, pixels, byte counts, raw per-frame timings, raw TCP/RFB errors,
draft text, marked text, keysyms, pointer coordinates, screenshots, device
identifiers, or command text are recorded here.

## Research Notes

- Apple app responsiveness guidance treats main-thread work during user
  interaction as the critical source of hangs and hitches. A frame worker that
  repeatedly resumes on the MainActor can compete with gestures, Compose
  editing, and pointer input even if each individual frame application is
  reasonably small.
- Apple Metal guidance recommends managing the rate of CPU work relative to
  GPU work to avoid stalls. Naru already stages Metal uploads off MainActor;
  this change adds a matching app-layer cadence guard before the next content
  frame is applied to SwiftUI/Metal-facing state.
- RFC 6143 describes RFB updates as client-driven and explicitly allows slow
  clients/networks to ignore transient framebuffer states. On iPhone, keeping
  the local interaction loop responsive is more valuable than replaying
  back-to-back intermediate desktop states.

Sources:

- https://developer.apple.com/documentation/xcode/improving-app-responsiveness
- https://developer.apple.com/documentation/Metal/synchronizing-cpu-and-gpu-work
- https://www.rfc-editor.org/rfc/rfc6143

## Change

- Add `SessionFrameApplicationWorkerPacing` with a content-frame minimum
  interval of one 60 Hz display-frame budget.
- Before applying a repeated content framebuffer, the MainActor
  frame-application worker waits for that bounded interval to elapse since the
  previous content frame application.
- Empty liveness and server-cursor updates remain delay-free so lightweight
  connection and cursor state can still flow when they are the next queued work.

## Interpretation

This is an interaction starvation guard. It is not a VNC profile promotion and
not evidence that the request/response visual path reaches the 10fps target.
The expected user-visible effect is that the first seconds after connection
start should leave more scheduler room for zoom, pan, trackpad movement, and
Compose editing while stale visual states continue to be coalesced.

## Verification

Completed local verification:

```bash
swift test --filter NaruRemoteAppTests.NaruRemoteAppModelTests/testSessionFrameApplicationWorkerPacing
swift test --filter NaruRemoteAppTests.NaruRemoteAppModelTests
NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
swift test
scripts/run-naru-live-benchmark.sh physical-device-preflight
```

Results:

- The focused pacing tests passed: 3 tests, 0 failures.
- `NaruRemoteAppModelTests` passed: 140 tests, 0 failures.
- Synthetic frame pipeline benchmarks passed with
  `NARU_RUN_SIM_BENCHMARKS=1`: 4 tests, 0 failures.
- The iPhone 17 Pro simulator app build succeeded for iOS 26.2.
- Full `swift test` passed: 1148 tests, 13 skipped, 0 failures.
- Physical-device preflight found the connected iPhone and an available signing
  identity, but the install/build gate is still blocked by missing local Xcode
  account and provisioning profile setup:
  `xcode-account-missing`, `ios-provisioning-profile-missing`.

The remaining physical gate is still a real iPhone session check: connect to
the Mac, start receiving VNC frames, and verify that gestures, trackpad cursor
movement, and Compose input continue responding during the startup burst.
