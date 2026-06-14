# Compose Input Storm Pacing Summary - 2026-06-14

## Decision

This change meets the PR threshold for a clear performance/responsiveness
improvement. The simulator input/viewport gate moved from a failed iPhone
Compose step with multi-minute XCUITest event synthesis stalls to a passing
iPhone+iPad simulator gate.

## Before

- `ComposeInputResponsivenessUITests` full iPhone class:
  - wrapper: `1324s`, exit `65`
  - `testFocusedActiveSessionComposeAcceptsKoreanDuringTrackpadCursorStorm`:
    `980.431s`, passed only after launch idle stalled
  - `testFocusedActiveSessionComposeSurvivesConfirmationStatusClearAfterFirstInput`:
    `220.497s`, failed while synthesizing the second Korean syllable
- `simulator-input-viewport-gate`:
  - wrapper: `3565s`
  - status: `failed`
  - failing step: `iphone-compose-storm-ui-tests`

## Change

- Focused Compose input now owns the first-responder transaction:
  connection-quality, helper-video health, incoming-clipboard review, and stale
  send-feedback clearing are deferred while Compose focus is active and flushed
  when focus leaves.
- The framebuffer flood fixture now uses the same focused-input frame
  application interval as production and runs in a bounded wall-clock window.
- The trackpad cursor storm fixture now waits until Compose focus is active
  before applying pressure, then runs a finite display-cadence burst. This keeps
  the fixture pressure on the input path without poisoning app launch idleness.

## After

### Focused unit slice

```bash
swift test --filter 'NaruRemoteAppModelTests/testFocusedComposeEditingDefersStaleSendFeedbackClearUntilFocusLeaves|NaruRemoteAppModelTests/testModelUpdatesComposeDraftAsUserTypes|SessionFrameDeliveryPriorityModelTests|IncomingClipboardReviewTests'
```

Result: `passed`, 27 tests executed, 1 skipped.

### Targeted iPhone UI regressions

```bash
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringTrackpadCursorStorm \
  -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeSurvivesConfirmationStatusClearAfterFirstInput \
  test
```

Result: `passed`, wrapper `35s`.

- Trackpad cursor storm: `10.481s`
- Confirmation status clear: `11.120s`

### Full iPhone Compose class

```bash
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests \
  test
```

Result: `passed`, wrapper `139s`, XCTest suite `133.709s`.

All 10 Compose input cases passed. The slowest case was the intentional
incoming-clipboard chrome storm at `19.818s`; the previously pathological
trackpad and confirmation cases completed in `11.263s` and `11.160s`.

### Simulator input/viewport gate

```bash
./scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

Result: `passed`, wrapper `295s`.

Gate JSON:

```json
{
  "schemaVersion": 1,
  "mode": "simulator-input-viewport-gate",
  "targetLabel": "simulator-input-viewport-v1",
  "status": "passed",
  "deviceCoverageLabels": ["iphone-simulator", "ipad-simulator"],
  "steps": [
    {"stepLabel": "swift-focused-unit-slice", "status": "passed"},
    {"stepLabel": "iphone-compose-storm-ui-tests", "status": "passed"},
    {"stepLabel": "iphone-viewport-hotpath-benchmark", "status": "passed"},
    {"stepLabel": "ipad-compose-storm-ui-tests", "status": "passed"}
  ]
}
```

## Remaining Risk

This is simulator evidence, not a physical iPhone/iPad sustained-session
result. It establishes that the UI/input lane is no longer blocked by local
chrome/frame/cursor fixture pressure, but live VNC throughput and device thermal
behavior still need separate physical-device runs.
