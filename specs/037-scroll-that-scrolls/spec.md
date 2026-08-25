# Feature Specification: Scroll That Scrolls

**Feature Branch**: `037-scroll-that-scrolls`
**Created**: 2026-08-26
**Status**: Landed 2026-08-26. Founder device pass on build 12 open.
**Product**: Naru Remote
**Input**: Founder, 2026-08-26: "스크롤 안되던애 이거 제스쳐로 스크롤 할 방법 만들어야
해.. 우클릭이나.. 나는 보통 두손가락 드래그를 스크롤로 쓰면 되지 싶은데 이게 잘 될지
모르겠다."

## Why

The gesture the founder asked for already exists, and so does everything behind
it. `MetalFramebufferHostingView` installs a two-touch `UIPanGestureRecognizer`
whose handler calls `NaruRemoteAppModel.sendScrollAt`, a `TwoFingerGestureClassifier`
separates a swipe from a pinch, and `sendScrollAt` turns motion into discrete
RFB wheel clicks (RFC 6143 §7.5.5 bits 3..6). Nothing was missing. It still did
not scroll, so the question was which half was broken — and that had to be
measured, not read.

### Half one, ruled out: the server

`LiveMacScrollWheelTests` (new, permanent, env-gated) sends ten wheel notches to
this Mac's Screen Sharing server and reads this machine's own scroll-event
counter through CoreGraphics — an independent path that does not depend on what
happens to be under the cursor:

```
[scroll-probe] first-frame dominant-colour ratio=0.202   (screen awake)
[scroll-probe] drain rounds=1
[scroll-probe] control changedPixelCount=0               (desktop quiet)
[scroll-probe] wheel-down changedPixelCount=0
[scroll-probe] OS scroll events observed=10
```

**Ten notches in, ten scroll events out.** macOS Screen Sharing delivers RFB
wheel buttons faithfully. The zero changed pixels is the probe working
correctly, not failing: the point it aims at is the middle of the desktop,
where there is usually wallpaper and nothing to scroll. The first version of
this probe reported a *control* of 1.7M changed pixels and a treatment of zero,
purely because Screen Sharing answers one request at a time and the cursor
move's repaint had not been collected yet — hence the drain, and hence the
control.

### Half two, the defect: nothing accumulated the remainder

`sendScrollAt` applies the threshold as `floor(|delta| / 24)` on **one
callback's delta**, and `handlePanGesture` calls `recognizer.setTranslation(.zero)`
on every callback so that each delta is incremental. At 60–120 Hz a comfortable
drag delivers a few points per callback: `floor(3 / 24)` is zero, and the motion
is discarded. Next callback, another few points, another zero. A notch only ever
fired when a single callback happened to carry the whole 24 points — a hard
flick — which is exactly "scrolling doesn't work, and once in a while it does".

`sendScrollAt`'s own documentation said it: *"the caller is expected to
accumulate across `.changed` callbacks so a slow drag still eventually crosses
the threshold."* No caller ever did. The contract was written and never wired.

## Requirements

- **FR-001 Sub-notch motion is carried, not discarded.** Motion below one notch
  accumulates across callbacks until it is worth a notch. A slow, comfortable
  two-finger drag scrolls.
- **FR-002 The remainder lives with the threshold, once.** It is owned by the
  model, not by each gesture recognizer, so every scroll source — finger pan,
  hardware trackpad scroll, anything added later — behaves identically.
  Accumulation is a pure Core value type so the arithmetic is testable without
  a gesture.
- **FR-003 A reversal does not spend backwards.** If motion on an axis changes
  direction, that axis's remainder is dropped rather than credited to the new
  direction — half a notch of abandoned upward motion must not become a
  downward notch.
- **FR-004 A gesture end clears the remainder**, so the next gesture starts from
  zero instead of inheriting credit. The recognizer reports the end; the model
  drops it.
- **FR-005 The threshold's value does not change.** 24 points per notch was
  tuned as roughly one desktop wheel notch, and this spec is about making it
  mean what it says, not about re-tuning it. If the founder finds it too slow or
  too fast on the device, that is a separate one-constant change.
- **FR-006 Constitution §I and §IV.** Scroll is a remote input event and already
  went through the pointer lane; nothing new is sent, nothing about deltas or
  coordinates is logged, and the local zoom/pan path is untouched.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — `ScrollTickAccumulator` | a run of sub-threshold deltas eventually emits exactly one notch; the remainder carries; a reversal drops it; a reset clears it | direct, pure value type |
| `swift test` — model | many small `sendScrollAt` calls that used to send nothing now send wheel clicks, and the count matches the accumulated distance | FAIL-first: on the previous source the same sequence sends zero pointer commands |
| **Live Mac** — `LiveMacScrollWheelTests` | RFB wheel buttons reach the OS as scroll events (10/10), which is what rules the server out | done, measured above; permanent and env-gated |
| iPhone simulator | **cannot** perform a two-finger drag with a real touch pair, so the classifier-to-wheel path is not executable here | stated, not hidden |
| **Founder device, build 12** | a two-finger drag scrolls the remote window, at a speed that feels right | the report |

## Non-Goals

- Re-tuning the 24-point notch (FR-005).
- Momentum / inertial scrolling. The remote has no notion of a fling; a notch
  is a notch.
- Pixel-precise (smooth) scrolling. RFB's wheel is discrete; smooth scroll
  needs the helper.
- Right-click as a scroll affordance. The founder floated it ("우클릭이나..")
  and it is already spoken for — two-finger *tap* is right-click in both
  pointer modes (spec 011 US3), so making it scroll too would collide.
- Changing the two-finger classifier's thresholds. It resolves a swipe at 12
  points of travel and was not implicated.

## Residual Risk

- No runner here can drive a real two-finger touch pair, so the gesture half of
  the path is verified by the classifier's own tests plus the model's
  arithmetic, not end-to-end. The device pass is the gate.
- The wheel probe proves delivery to the OS, not that the *frontmost window*
  scrolls. An app that ignores scroll events, or a point over wallpaper, will
  still look like nothing happened — which is also true of a real mouse.
- 24 points per notch is now genuinely reachable, which means scrolling can
  feel too fast on a long drag for the first time. That is a constant, and the
  founder's device is where it gets judged.
