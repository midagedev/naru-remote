# Feature Specification: PiP Watch Survives A Second Entry

**Feature Branch**: `032-pip-watch-reentry`
**Created**: 2026-08-25
**Status**: Drafted 2026-08-25.
**Product**: Naru Remote
**Input**: Founder on build 10 — "이거 그런데 pip 모드 두 번 켜면 앱 꺼진다."

## Why

Entering PiP Watch a second time in one session terminates the app. That is the
worst class of defect this product can ship: PiP is the feature that lets a
phone keep watching a long-running remote job, so the user who needs it most
hits it twice.

### The reproduction is device-only, and that is measured

`PiPWatchReentryUITests` drives the `session-active-widescreen` fixture through
the tools menu and taps PiP Watch. On the iPhone 17 Pro simulator (iOS 26.2) the
menu item exists and is **disabled** — `canStartPiPWatch` is false because
`AVPictureInPictureController.isPictureInPictureSupported()` reports false there.
So the simulator cannot produce this crash at all, and the test skips rather than
passing vacuously. The gate that can catch a regression on a runner has to be
somewhere other than AVKit, which is what shapes the fix below.

### What the code does on a second entry

`NaruRemoteAppModel.startPiPWatch()` calls `prepareController(_:)` on **every**
entry, and `PiPWatchPictureInPictureController.prepare(layerHost:)` builds a
brand-new `AVPictureInPictureController` over the **same**
`AVSampleBufferDisplayLayer` each time, replacing the previous one. Three
independent hazards live in that one line, and none of them can be ruled out
without the device:

1. **Two controllers, one layer.** A second `ContentSource` is constructed
   against a layer that the previous controller still holds, and the previous
   controller is released while AVKit may still be mid-transition.
2. **`startPictureInPicture()` with no possibility check.** `start()` calls it
   unconditionally. Apple treats calling it while `isPictureInPicturePossible`
   is false as a programmer error, and the second entry is exactly when it can
   be false — the first PiP window may still be tearing down.
3. **An unbounded sample duration.** The playback time range is
   `CMTime(value: Int64.max, timescale: 1)`, which AVKit re-derives on each
   transition. `.positiveInfinity` is the value that means "live" and cannot
   overflow anything downstream.

There is also a fourth defect that is not a crash but is why the crash was
invisible: `AVPictureInPictureControllerDelegate` is conformed to with an
**empty extension**. When the user closes the floating window from the system
chrome, or AVKit fails to start, the app is never told. `pipWatchSession` stays
`.watching` while there is no PiP window, so the app's idea of PiP state and the
system's diverge, and the second entry is taken against a state that is already
wrong.

## Requirements

- **FR-001** One `AVPictureInPictureController` per layer, for the lifetime of
  the layer. `prepare` is idempotent: preparing again against the same layer host
  reuses the existing controller and does not construct a second content source.
- **FR-002** Starting is guarded. A start request is only delivered when the
  controller reports PiP possible and not already active; otherwise the request
  is refused and reported as a refusal, not as a start.
- **FR-003** The delegate is wired. `didStart`, `didStop`, `failedToStart` and
  the stop transition drive `PiPWatchSession` state, so the app's state follows
  the system's rather than assuming it.
- **FR-004** The playback time range uses `.positiveInfinity` for a live source.
- **FR-005** The lifecycle decision — prepare / reuse / start / refuse / stop —
  lives in a **platform-independent** value type in `NaruRemoteCore` with unit
  tests that run under `swift test`, because AVKit cannot be exercised on the
  only runner this repository can gate on. The iOS controller becomes the thin
  adapter that asks it.
- **FR-006** Lifecycle counts reach the diagnostic export as counts and
  fixed-catalog labels only (constitution §IV): entries requested, controllers
  created, starts refused, and the last stop reason. The founder's next PiP
  report has to be answerable from an export rather than from a code reading.
- **FR-007** `PiPWatchReentryUITests` stays in the suite. It skips where PiP is
  unsupported and asserts app survival where it is, which is the device pass.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — lifecycle unit tests | a second prepare reuses the controller; a start while active, in flight, stopping or impossible is refused; a stop with no app request is recorded as a system dismissal | 14 tests, direct |
| `swift test` — export tests | the lifecycle counters round-trip and reject labels outside their catalogue | direct |
| iPhone simulator UITest | the app survives a second entry where PiP exists; skips where it does not | **measured skip** on iOS 26.2 simulator |
| **Founder device, build 11** | **PiP twice in one session, then close from the system chrome and enter again** | the report that opened this spec |

**These unit tests are not FAIL-first, and saying otherwise would be a false
claim about their strength.** The behaviour they pin lives in a type that did
not exist before this spec, so there is no earlier source for them to fail
against; and the defect they describe is in AVKit's reaction, which no runner
here can execute. What stands in for FAIL-first is the diff: the previous
`prepare(layerHost:)` constructed an `AVPictureInPictureController` and a
`ContentSource` unconditionally on every call, and `start()` called
`startPictureInPicture()` with no possibility check — both visible in one
`git show`. The device pass is the only thing that can confirm the fix.

## Non-Goals

- Making PiP an input surface. It stays watch-only (constitution).
- Reproducing the crash on a simulator. Measured impossible; the effort goes
  into the layer that can be gated instead.
- Naming the exact AVKit objection. Three hazards are closed together because
  the device cannot be instrumented from here, and a fix that closes only the
  one guessed right is a fix that ships the crash.

## Residual Risk
- Closing three hazards in one round means the device pass cannot attribute the
  fix to one of them. Accepted deliberately: the alternative is three device
  round trips through the founder.
- The delegate now drives state, so a system-initiated stop changes app state
  where it previously did not. If AVKit delivers `didStop` during a
  restart-in-place, the session could read stopped while a window exists; the
  guarded start in FR-002 is what keeps that recoverable.
