# Nonblocking Input and Helper-Video Gate Summary - 2026-06-07

## Scope

The latest physical-device report said a real connection could freeze gestures
and Compose input after the stream started. This pass treats the symptom as a
product-level interaction failure, not just a VNC tuning miss.

No host names, credentials, helper executable paths, endpoints, command text,
raw OS errors, frame contents, pixels, dimensions, byte counts, device IDs,
draft text, marked text, keysyms, or clipboard contents are recorded here.

## Reproduction Evidence

Commands run on current `main` before the implementation:

```bash
swift test --filter RemoteInputDockSyncPolicyTests
swift test --filter RemoteInputDockRenderStateTests
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringFramebufferAndCursorStorm
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

Results:

- Compose policy unit tests passed.
- The strongest simulator Compose fixture passed: Korean input still accepted
  the second syllable under active-session framebuffer and cursor pressure.
- The live VNC 10fps gate failed at `1.49` content FPS.
- VNC update latency was `540` ms average and `1054` ms p95.
- VNC receive path was the primary constraint, with first-byte wait p95
  `638` ms and payload read p95 `554` ms.
- Helper-video synthetic and sustained synthetic gates passed.
- True helper ScreenCaptureKit remained blocked by Screen Recording permission
  for the stable helper app bundle.

## Design Decision

The evidence does not support promoting another VNC profile as the smooth
visual path. VNC remains the control, input, and fallback path. The primary
smoothness path should be helper-video once the macOS Screen Recording gate is
cleared.

The app still needs to protect input while VNC is visible. Compose focus now
switches framebuffer delivery into an input-priority policy: steady VNC frames
are coalesced on a longer keyboard-friendly cadence, and leaving focus flushes
only the newest pending frame immediately. This prevents stale frame delivery
from competing with the active UIKit keyboard transaction.

## Changes

- Added `SessionFrameDeliveryPriority.visual` and `.inputEditing`.
- Kept normal steady VNC delivery at 16 ms.
- Added input-editing VNC delivery coalescing at 50 ms.
- Wired Compose focus changes from `NaruRemoteAppShell` into
  `NaruRemoteAppModel.setComposeInputEditingActive(_:)`.
- Added a safe Screen Recording watch summary for helper permission process
  kind, grant hint, and the required relaunch action after permission changes.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh screen-recording-watch-self-test | jq '{mode, watchStatus, permissionProcessKind, permissionGrantHint, postPermissionChangeRequiresRelaunch, setupActionLabels}'
swift test --filter SessionFrameStoreTests
swift test --filter RemoteInputDockRenderStateTests
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:NaruRemoteUITests/ComposeInputResponsivenessUITests/testFocusedActiveSessionComposeAcceptsKoreanDuringFramebufferAndCursorStorm
swift test
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

All commands above passed locally.

The post-implementation live readiness run still blocked the product gate:

- `overallGateState`: `blockedByHelperScreenCapture`
- VNC content FPS: `1.57`
- VNC update latency: `544` ms average and `1073` ms p95
- VNC primary constraint: `receivePath`
- Server cadence status: `first-byte-wait-dominated`
- Helper-video synthetic and sustained synthetic gates: pass
- True helper-video ScreenCaptureKit gate: blocked by Screen Recording
  permission for the helper app bundle

## Next Gate

Grant Screen Recording to the helper app bundle, quit and relaunch the helper,
then rerun:

```bash
scripts/run-naru-live-benchmark.sh screen-recording-watch
scripts/run-naru-live-benchmark.sh helper-readiness-sweep
scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark
scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness
```

If true ScreenCaptureKit capture passes, the next large implementation unit is
the physical iPhone helper-video gate and only then product default promotion.
