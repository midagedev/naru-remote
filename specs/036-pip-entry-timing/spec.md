# Feature Specification: PiP Opens When You Ask, And When You Leave

**Feature Branch**: `036-pip-entry-timing`
**Created**: 2026-08-25
**Status**: Landed 2026-08-25. Founder device pass on build 12 open.
**Product**: Naru Remote
**Input**: Founder on build 11: "pip진입버튼 이거 pip버튼 누르자마자 앱이 백그라운드로
가야 하는데 바로 안간다."

## Why

Two different things are inside that sentence, and only one of them is a bug.

### The bug: the content layer is not mounted when the start is requested

`AVPictureInPictureController`'s content source here is an
`AVSampleBufferDisplayLayer` owned by `PiPLayerHost`. AVKit transitions *that
layer* into the floating window, so the layer has to be in a live view
hierarchy when the transition begins.

It is not. The layer is mounted by `SessionViewportView` only while
`isPiPWatching` — which the shell derives from
`snapshot.pipWatchSession?.state == .watching`
(`NaruRemoteAppShell.swift:1179`). And `pipWatchSession` is assigned at the
**end** of `NaruRemoteAppModel.startPiPWatch`, after
`pipWatchController.start()` has already called
`startPictureInPicture()`. The whole function is one synchronous
`@MainActor` pass, so no SwiftUI render happens in the middle of it:

```
startPiPWatch()
  ├─ enqueue(frame)                    // layer not in any window yet
  ├─ start() → startPictureInPicture() // ← asked to transition an unmounted layer
  └─ pipWatchSession = watching        // ← only now does the layer get mounted
```

The system is being asked to fly a layer that is not on screen into a window,
and it waits. That is the delay, and it is ours.

### Not a bug: an app cannot send itself to the background

There is no public API to background your own app, and there should not be.
When PiP starts from the foreground, iOS opens the floating window **over** the
app; the user leaves when they choose. So "tap and the app goes to the
background" cannot be delivered literally.

What can be delivered is the thing the founder actually wants, which is that
**leaving the app is what puts the session in a floating window** — no button
at all. `AVPictureInPictureController.canStartPictureInPictureAutomaticallyFromInline`
is the platform's own answer, the app already ships the `audio` background
mode PiP needs, and it turns the founder's expectation inside out in the right
direction: instead of a button that tries to background the app, the gesture
that backgrounds the app raises the window.

That has a cost the founder has already flagged in another report: a PiP
session keeps streaming VNC frames while the app is in the background, which
spends cellular data and battery. So it is a setting, defaulted to on because
it is what was asked for, and switchable because the data question is still
unmeasured.

## Requirements

- **FR-001 The PiP content layer is mounted before a start is requested.** The
  shared `AVSampleBufferDisplayLayer` is in the view hierarchy whenever a
  session can enter PiP — not only while a window is up. It stays invisible and
  non-interactive until PiP is actually engaged; the in-app remote screen keeps
  rendering through the existing Metal path, unchanged.
- **FR-002 The controller is prepared while the session is live**, not at the
  moment of the tap, so entry is a start rather than a construct-then-start.
  Preparation stays idempotent per layer (spec 032 FR-001) — this changes
  *when* it happens, not how many controllers exist.
- **FR-003 Frames reach the layer host whenever the layer is mounted and PiP is
  engaged**, including a PiP session the app did not start itself (FR-004).
  A window showing a frozen frame is worse than no window.
- **FR-004 Leaving the app enters PiP**, when a session is live and the setting
  allows it, via `canStartPictureInPictureAutomaticallyFromInline`. An
  auto-started window is a first-class PiP session: the app synthesises its
  `PiPWatchSession` from the `didStart` callback rather than dropping the event
  because no session was pending, and the active framing mode (spec 034)
  applies to it exactly as it does to a tapped entry.
- **FR-005 Automatic entry is a stored preference**, default **on**, presented
  in the PiP control's long-press menu alongside the framing modes. Off means
  the button is the only way in.
- **FR-006 The button keeps its contract.** One tap still enters PiP on the
  current view (spec 034 FR-001); long press still chooses framing (FR-002).
  Nothing about the tap becomes conditional on the new setting.
- **FR-007 Constitution §IV.** No new logging of frames, sizes, or timings.
  The export gains counts only, and PiP stays watch-only (§I) — automatic entry
  changes when a watch window opens, never what it can do.

## Key Decisions

**D1 — mount, don't re-render.** The alternative fix was to set
`pipWatchSession` to `.preparing`, let SwiftUI mount the layer, and start PiP
on the next runloop turn. That works and is smaller, but it makes entry depend
on a render landing between two model writes, which is the kind of ordering
that breaks quietly later. Mounting the layer for the life of the session
removes the race instead of timing it.

**D2 — automatic entry is the real answer to the report.** The button was
built because there was no other way in. With FR-004, the founder's own
sentence — *the app should go to the background* — becomes the trigger rather
than the goal.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — model | an auto-started PiP window (a `didStart` with no pending session) produces a watching session, and frames continue to be forwarded | FAIL-first: today the event is dropped because `pipWatchSession` is nil |
| `swift test` — settings | the automatic-entry preference round-trips and defaults to on with an empty `{}` | direct |
| `swift test` — model | the framing mode applies to an auto-started window | direct |
| iPhone simulator UITest | the long-press menu offers the automatic-entry toggle and it persists | via the DEBUG PiP-availability hook |
| iPhone simulator | **cannot** prove any of the AVKit behaviour: `isPictureInPictureSupported()` is false there (measured, spec 032). The layer-mounting fix and the automatic entry are diff-and-device claims | stated, not hidden |
| **Founder device, build 12** | PiP opens immediately on tap; leaving the app opens it by itself; the window is live, not frozen | the report |

## Non-Goals

- Backgrounding the app from a tap. Not possible, and not attempted.
- Making PiP interactive (constitution).
- Measuring what background streaming costs on cellular. That is the open
  bandwidth question from builds 9–11 and it is not this spec; FR-005's switch
  is what makes the cost avoidable in the meantime.
- Keeping the session alive without PiP when the app backgrounds. Out of
  scope, and a different mechanism entirely.

## Residual Risk

- FR-004 means every app switch during a live session starts a background
  stream. Default-on is the founder's stated preference, and FR-005 is the
  escape hatch, but the data cost of it is genuinely unmeasured.
- The layer being mounted for the life of the session is a new permanent view
  in the session tree. It is sized to nothing and renders nothing until PiP
  engages, but it is one more thing in the hierarchy that a future layout
  change can disturb.
- Neither FR-001 nor FR-004 can be executed by any runner available here.
  Both are read from the diff and confirmed on the founder's device.
