# Feature Specification: Device-Pass Input Defects — Keyboard, Zoom, Scroll

**Feature Branch**: `043-device-pass-input-defects`
**Created**: 2026-09-13
**Status**: Implemented 2026-09-13 — all three defects root-caused and fixed (commits `cf2bca1b`, `a3f8c527`). Gates: `swift test` Core 693 / App 734 green, iPhone 17 Pro simulator build green. **Open — founder device pass** (SC-1 keyboard on every Type↔Compose switch, SC-2 pinch in a helper-video session, SC-3 slow two-finger scroll). One candidate cause was refuted rather than fixed: the helper-video zoom transform derives from the VNC framebuffer and that is correct (D2). Also surfaced, not resolved: spec 002's Direct Keystroke mode is unreachable from the UI while its Status still claims it shipped — see `NEXT_STEPS.md`.
**Product**: Naru Remote
**Input**: Founder, 2026-09-13, on a physical iPhone after the spec 042 work:

> "이거 거의 된것같았는데 아직 컴포즈모드와 직접키보드 모드 오갈때
> 직접입력모드에 키보드가 안나탈때가 있어서 그거 수정해야하고 헬퍼모드에서
> 줌인아웃 제대로 안되, 그리고 vnc모드에서 두손가락 드래그 스크롤의 양이
> 엄청 적을때가 있어"

Three defects in the input layer, all intermittent, all found by hand on
the canonical device. None is a new capability — each is a shipped
behaviour that does not hold on a real finger.

## Problem

### D1 — the typing mode's keyboard sometimes does not appear

**Root-caused 2026-09-13.** First, a naming correction the investigation
forced: the dock has had two modes since commit `b6e8a5e9` (2026-08-17,
"Simplify input UX to two-mode Type/Compose dock") — **Type**
(type-through) and **Compose**. Spec 002's Direct Keystroke mode is
unreachable from the UI: its three keyboard views were deleted in that
commit and `onToggleDirectMode` is now wired to nothing (declared and
stored in `RemoteInputDockView`, never called). The mode the founder
calls 직접키보드 is **Type**, and that is the mode this defect is in.
(Spec 011 retired Direct as a surface in that same commit; spec 002's
Status was never amended to say so, and the mode's model layer is still
carried. Recorded in `NEXT_STEPS.md`, not resolved here.)

The defect: switching Type ↔ Compose rebuilds the row that hosts the
compose editor, so the editor loses first responder — and nothing asks
for it back. Two triggers exist and both miss this case:

1. `.onAppear` fires only when the dock instance itself is recreated,
   and a mode switch usually keeps it.
2. `.onChange(of: composeExpansionRequested)` fires only on a false→true
   transition, and the mode buttons re-assert an expansion that is
   already requested, so the value does not change.

The guard made it worse: the focus decision read `composeFieldFocused`, a
`@State` mirror updated by the editor's own callback. A departing editor
does not always report, so the mirror can still read `true` while nothing
holds first responder — and the request is then skipped as unnecessary.

Why it is felt as a dead session rather than a missing keyboard: Type
mode's editor is a 1×1 invisible view (there is no field to look at), so
when the keyboard does not come up there is nothing on screen to tap and
the only recovery is to leave and re-enter the mode.

### D2 — Pinch zoom misbehaves in helper-video mode

**Root-caused 2026-09-13.** One of the two candidates held.

**Confirmed — the two-finger classifier locks the gesture to scroll.**
`TwoFingerGestureClassifier` decides once per gesture whether two fingers
mean scroll or zoom and holds that decision until the fingers lift. The
zoom clause always had to out-argue the swipe (`spread > translation`),
but the scroll clause had no mirror: crossing the 12 pt travel bar won
outright, even while the spread signal was the larger one. A pinch with
the hand drifting — fingers spreading 1.5 pt per callback while the
midpoint moves 1 pt — reaches spread 18 / travel 12 and freezes as
`.scroll`, after which `handlePinchGesture` ignores every callback. The
zoom never happens.

**Refuted — the transform is not built from the wrong rectangle.** The
helper's encode preserves aspect to within even-pixel rounding: 3024×1964
scales to 960×622, an aspect error of 0.26%. On a 430×812 hero container
the video's letterbox band (430×278.60) and the framebuffer transform's
content rect (430×279.27) differ by 0.67 pt at fit and under 3 pt at 4×
zoom. Input must stay in framebuffer pixels regardless, because RFB
`PointerEvent` coordinates are framebuffer pixels. No change was made
here; the numbers are pinned by `HelperVideoZoomGeometryTests`.

### D3 — Two-finger scroll sends far too little

**Root-caused 2026-09-13.** Both candidates held, and a third defect
surfaced while fixing them.

**Confirmed — the undecided prefix is discarded.** A gesture is
`.undecided` until its winning signal clears a bar, and the pan handler
returned early for every callback before that. A 26 pt drag that resolved
at 12 pt delivered only 16 pt to the scroll path — zero notches, on a
24 pt notch. Short drags therefore did nothing at all.

**Confirmed — jitter drops the remainder.** `ScrollTickAccumulator` zeroed
an axis's pending remainder on *any* sign reversal. A wobble stream of
`[+2, −1]` repeated 24 times nets +24 pt — one full notch — and emitted
nothing.

**Also found — a zoom gesture's tail leaked into scroll.** The handler
gated delivery on `recognizer.numberOfTouches == 2`, which is already 0
by the `.ended` callback, so the last delta of a *zoom* gesture was
delivered to the remote as scroll.

## Direction

**P1 — One finger pair, one meaning, decided fairly.** The scroll/zoom
classifier stays (it exists because scrolling used to drag the viewport,
2026-08-19), but a pinch must not lose to a swipe merely because the
swipe's bar is lower. Whatever thresholds are chosen must be justified by
measurement, not taste.

**P2 — No motion is silently dropped.** Movement the user made before the
gesture was classified belongs to the gesture that was classified. This
is the same defect class spec 037 closed for per-callback deltas.

**P3 — The transform follows the picture the user sees.** In helper-video
mode the visible content is the decoded video, not the VNC framebuffer.
Zoom scale, anchor, and pan bounds derive from the geometry actually on
screen.

**P4 — A mode that promises typing shows a keyboard.** Focus state is
read from the responder that actually has it, never from a mirror of it,
and every event that can cost the editor first responder is a reason to
ask for it back.

## Requirements

- **FR-001** A two-finger pinch that the user perceives as a pinch
  resolves to `.zoom`, including when the finger midpoint drifts. The
  classifier's thresholds and their relationship are pinned by tests over
  recorded gesture shapes (symmetric pinch, thumb-anchored pinch, pinch
  with hand drift, straight swipe, slow swipe with spread jitter).
- **FR-002** Motion accumulated while a two-finger gesture is
  `.undecided` is delivered to the resolved handler once the gesture
  resolves — as scroll distance when it resolves to `.scroll`, and it is
  not double-counted.
- **FR-003** `ScrollTickAccumulator` does not discard the pending
  remainder on jitter-scale sign reversals; a reversal that represents
  real direction change still does. The boundary is a stated number with
  a test on each side.
- **FR-004** In helper-video mode the viewport transform (zoom scale,
  anchor, pan bounds) is computed from the geometry of the content being
  displayed, and a pinch changes the visible picture by the same factor
  it does in a VNC session.
- **FR-005** Switching between the dock's two modes (Type and Compose)
  always leaves the typing surface usable: when the dock is expanded, the
  compose editor holds first responder and the keyboard is up. The focus
  decision reads the editor's real responder state, never a mirrored
  flag, and a mode switch is itself a trigger to re-ask. Leaving and
  re-entering the mode is not required to recover.
- **FR-006** No new user-content logging; gesture coordinates and key
  presses stay unlogged (constitution §IV).

## Success Criteria (device pass)

- **SC-1** In a live session, switching Type ↔ Compose ten times in a row
  brings the keyboard up every time, with no need to leave and re-enter
  the mode.
- **SC-2** In a helper-video session, pinching zooms in and out smoothly
  and by the same feel as a VNC session; a pinch started anywhere on the
  screen works.
- **SC-3** In a VNC session, a two-finger drag of a given distance
  scrolls the remote by an amount proportional to that distance, and a
  slow drag scrolls rather than doing nothing.

## Verification matrix

| Layer | Command | Covers |
| --- | --- | --- |
| Core unit | `swift test --filter NaruRemoteCoreTests` | classifier over recorded gesture shapes (FR-001), accumulator jitter boundary (FR-003) |
| App unit | `swift test --filter NaruRemoteAppTests` | undecided-prefix delivery (FR-002), helper-mode transform geometry (FR-004), compose-focus decision across mode switches (FR-005) |
| iPhone simulator | `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'` | build + any UI test touching the dock |
| Physical iPhone | founder | SC-1, SC-2, SC-3 |

## Out of scope

- Redesigning the scroll or zoom interaction model. The gestures keep
  their current meanings.
- The spec 042 residuals (profile editor helper section, pairing token
  rotation) — tracked in `NEXT_STEPS.md`.
