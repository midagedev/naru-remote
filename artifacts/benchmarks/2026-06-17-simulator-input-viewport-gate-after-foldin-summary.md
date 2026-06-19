# Simulator Input And Viewport Gate Refresh - 2026-06-17

## Scope

This artifact records the simulator-only input and viewport regression gate
after folding the latest focused Compose safe-area/layout fixes into the
long-running helper-video/trackpad worktree.

This is not a physical iPhone Green claim, live FPS improvement claim,
thermal pass, traffic pass, or product-default promotion. It is local
regression evidence for the Korean/CJK Compose freeze class, trackpad viewport
gesture path, and viewport hot-path benchmark while the physical iPhone gate is
blocked by signing/provisioning setup.

## Focused Verification

XcodeBuildMCP simulator test:

```bash
-only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testComposeEditorAcceptsSecondKoreanSyllableAfterFirstInput
-only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testTrackpadViewportGestureBurstThenComposeAcceptsKoreanUnderStreamPressure
```

Result:

- `testComposeEditorAcceptsSecondKoreanSyllableAfterFirstInput=passed`
- `testTrackpadViewportGestureBurstThenComposeAcceptsKoreanUnderStreamPressure=passed`
- Target: `iPhone 17 Pro` simulator
- Result bundle:
  `/Users/hckim/Library/Developer/XcodeBuildMCP/workspaces/naru-remote-70fb02ec5b80/result-bundles/test_sim_2026-06-16T20-38-43-661Z_pid18284_2aacbac0.xcresult`

Interpretation:

- A profile-detail Compose editor still accepts the second Korean syllable.
- A real viewport drag burst under framebuffer pressure does not leave the
  later focused Korean/CJK Compose editor frozen in the simulator.

## Integrated Gate

Command:

```bash
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

Log:

```text
/tmp/naru-simulator-input-viewport-gate-20260617-after-foldin.log
```

Result:

```json
{
  "schemaVersion": 1,
  "mode": "simulator-input-viewport-gate",
  "targetLabel": "simulator-input-viewport-v1",
  "status": "passed",
  "phoneDestinationLabel": "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2",
  "padDestinationLabel": "platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2",
  "deviceCoverageLabels": ["iphone-simulator", "ipad-simulator"],
  "benchmarkIterations": 3,
  "benchmarkSamples": 1000,
  "policyLabels": [
    "korean-cjk-compose-freeze-regression",
    "viewport-hotpath-simulator-benchmark",
    "viewport-pressure-diagnostic-regression",
    "trackpad-viewport-gesture-ui-regression",
    "iphone-and-ipad-simulator-local-iteration-gate"
  ],
  "steps": [
    {"stepLabel":"swift-focused-unit-slice","status":"passed"},
    {"stepLabel":"iphone-compose-basic-ui-test","status":"passed"},
    {"stepLabel":"iphone-compose-full-interaction-storm-ui-test","status":"passed"},
    {"stepLabel":"iphone-trackpad-viewport-compose-ui-test","status":"passed"},
    {"stepLabel":"iphone-viewport-hotpath-benchmark","status":"passed"},
    {"stepLabel":"ipad-compose-basic-ui-test","status":"passed"},
    {"stepLabel":"ipad-trackpad-viewport-compose-ui-test","status":"passed"}
  ]
}
```

## Unit/Static Checks

Commands:

```bash
git diff --check
swift test --filter 'RemoteInputDockRenderStateTests|RemoteInputDockSyncPolicyTests'
```

Result:

- `git diff --check=passed`
- `RemoteInputDockRenderStateTests=passed`
- `RemoteInputDockSyncPolicyTests=passed`
- Total selected unit tests: `75 passed`

## Implementation Notes

- The detail shell keeps the input dock safe-area inset outside the scrollable
  detail body so pre-connection Compose focus no longer needs to switch the
  dock into live compact layout.
- The delayed first-frame fixture now keeps the focus/session-transition
  reproduction wide enough to cover late first-frame application.
- Test-only frame/cursor/model/helper/clipboard storm hooks are cancellable and
  paced at frame-friendly intervals so they recreate pressure without turning
  the test harness itself into a UI-executor denial-of-service.
- The trackpad viewport Compose UI test uses a real hittable viewport surface
  and drag burst before focusing Compose, which better matches the reported
  "zoom/pan then keyboard freezes" path than a model-only cursor storm.

## Remaining Risk

- T030 physical iPhone + Mac manual verification remains open. This simulator
  gate cannot prove physical hand-feel, device heat, sustained helper-video
  decode, network variability, PiP behavior, or real remote text insertion.
- The current physical iPhone gate is blocked by Xcode account / exact
  development provisioning profile setup, recorded separately in
  `2026-06-17-physical-iphone-residual-risk-summary.md`.
- Do not use this artifact as evidence that the product is Green. Use it to
  avoid repeating the same simulator Compose/trackpad regression loop unless
  code changes touch the input dock, viewport gesture path, frame pacing, or
  test storm hooks.

## Privacy

This artifact contains only test names, fixed labels, aggregate pass/fail
results, coarse simulator device labels, and an xcresult path. It omits
hostnames, IP addresses, endpoints, credentials, profile fingerprints, pairing
material, physical device identifiers, screenshots, frame pixels, dimensions,
coordinates, byte counts, composed payload text beyond the fixed test syllables,
clipboard contents, and exact timing series.
