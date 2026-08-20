# Tasks: Helper Video Keyframe Recovery

- [x] **T001** Pure Core recovery policy + decision-table tests. Create file
      `HelperVideoKeyframeRecoveryPolicy.swift` inside
      `NaruRemote/Sources/NaruRemoteCore/HelperVideo/` and file
      `HelperVideoKeyframeRecoveryPolicyTests.swift` inside
      `NaruRemote/Tests/NaruRemoteCoreTests/`.
- [x] **T002** Client send path: signed `requestKeyframe` on the live
      connection + optional sender closure on
      `HelperVideoStreamNetworkEvents`. File:
      `NaruRemote/Sources/NaruRemoteCore/HelperVideo/HelperVideoStreamNetworkClient.swift`
      (+ `HelperVideoTransport.swift` only if the events type lives there).
- [x] **T003** Helper signal + encoder force. Create file
      `NaruHelperVideoKeyframeRequestSignal.swift` inside
      `NaruHelper/Sources/NaruHelperKit/`; add the signal-accepting
      `accessUnitStream(for:keyframeSignal:)` overload with default
      implementation; VT encode loops consume the signal. Files:
      `NaruHelperVideoStreamFramePipeline.swift`,
      `NaruHelperVideoToolboxSyntheticAccessUnitSource.swift`,
      `NaruHelperVideoScreenCaptureKitAccessUnitSource.swift`.
- [x] **T004** Helper inbound receive loop during streaming + authorize
      requestKeyframe → trigger signal. Files:
      `NaruHelperVideoStreamNetworkService.swift`,
      `NaruHelperVideoTransportRequestHandler.swift`.
- [x] **T005** Runner wiring through the policy, **FAIL-first** runner tests
      (current runner falls back without calling the sender). Files:
      `NaruRemote/App/Features/HelperVideo/HelperVideoStreamSessionRunner.swift`,
      `NaruRemote/Tests/NaruRemoteAppTests/HelperVideoStreamSessionRunnerTests.swift`.
- [x] **T006** Helper-side tests: signal→keyframe (VT), coalescing, inbound
      auth accept/reject. Files under `NaruHelper/Tests/NaruHelperKitTests/`
      and `NaruRemote/Tests/NaruRemoteCoreTests/` fake-transport suites.
- [x] **T007** Lead review (2026-08-20): diff read in full; found and fixed
      one defect — the encode loop's short-circuit skipped `consumePending()`
      whenever the interval already forced a keyframe, leaking a redundant
      forced IDR into the next frame (FAIL-first
      `testRequestCoincidingWithIntervalKeyframeDoesNotLeakIntoNextFrame`;
      the test needed output-gated coordination because a wall-clock sleep
      let the request drain at index 1). `swift test` from cold: 1659 tests,
      0 failures. `xcodegen generate` + iPhone 17 Pro simulator build green.
      Docs synced; committed.
