# Feature Specification: The Session UX Punch List

**Feature Branch**: `038-session-ux-punchlist`
**Created**: 2026-08-27
**Status**: Landed 2026-08-27. Founder device pass on the next build open.
**Product**: Naru Remote
**Input**: Founder, 2026-08-27, on build 12: "전반적으로 스펙 구현은 된것 같네 그런데
키보드 위에 라벨이 자꾸 키 입력 영역을 가리는 문제와 컴포즈에서 아직도 높이가 높은 문제
그리고 컴포즈에서 문자 보내기를 했는데도 여전히 컴포즈된 문자들이 지워지지 않고 남아있는
문제 팔로우 캠은 이거 실 동작영역을 찾는 알고리즘 구현하는건 어려울것 같아서 제거하고
이거 이미 pip가 떠있는 상태에서 영역 선택으로 넘어갈때 pip로 이미 화면이 가있어서 영역을
선택할수 없는 문제 등 전반적으로 ux문제가 많아서 그 외에도 매끄럽지 않은 부분을 찾아서
전반적으로 개선해줘" — and, mid-round: "키보드를 바꾸거나 열거나 닫을때 화면영역이 다른
영역으로 순간이동 하는 의도치 않은 패닝문제도 있어 그리고 기존 접속 줌을 지금 높이 맞춤으로
되어 있는데 너비 맞춤이 더 좋겠어 그리고 호스트목록화면에서 프리뷰 이미지 품질이 아주 낮은데
리사이즈 방식문제일지 여튼 그부분도 개선할 방법 찾아줘"

## Why

Build 12 closed the three things the founder named on build 11, and the reply is
the shape a product takes when the blocking defects are gone: eight smaller ones,
each individually survivable, together making the app feel unfinished. This spec
takes them as one round because they are all the session surface and most of them
share two root causes — chrome that paints outside the layout it belongs to, and a
viewport whose baseline is recomputed from scratch whenever its container resizes.

Every item below was reproduced before it was fixed. Where a gate could have
caught it and did not, the reason it could not is recorded, because that is the
part worth keeping.

## The eight

### 1. The status sentence is painted on top of the keys

`NaruRemoteAppShell` renders the dock's status line as
`.overlay(alignment: .top)` on the dock host with
`.alignmentGuide(.top) { $0[.bottom] }`, intending to float it just above the
dock without costing a row (spec 015 FR-006). Measured, it does not float above
anything — it lands **on** the row:

```
[dock-chrome:status-overlap] row 1 y=776..828:
  naru.input.focused-status + naru.input.accessory.panel-toggle
  + naru.input.editor + naru.input.mode-toggle + naru.input.send
```

The screenshot confirms it: "Remote app confirmation unavailable." sits across
the top of `⋯`, the field, the keyboard key and Send, clipping all four.

**Why no gate saw it.** `KeyboardUpDockHeightUITests` states its contract in
rows, and its `rowBands` helper groups *vertically overlapping* elements into one
band. A label that covers the row is, to that measurement, the same one tidy row
it always wanted — the budget stayed green precisely because the defect is an
overlap. Rows are the wrong question for this class; the right one is whether two
things claim the same pixels.

**FR-001.** A status sentence participates in the dock's layout. It may cost a
row when it has something to say and must cost nothing when it does not, but it
must never be drawn over a control.

**FR-002.** The slot exists whether or not there is a sentence in it, so
appearing and disappearing changes a child's *height* and never the VStack's set
of children — that was the original reason for the overlay (a changing child set
collapsed the keyboard safe-area layout under UIKit IME) and it stays honoured.

### 2. Compose's row is taller than every other row

The compact Compose row is built from 40pt controls and one editor that is
`.frame(height: 40)` **plus** `.padding(.vertical, 6)` — 52pt. The row is
therefore 52pt tall to seat a 40pt field, and the extra 12pt is pure inset. Type
mode's row, built from the same 40pt controls with no such padding, is 40pt.

**FR-003.** Compose's keyboard-up row is the same height as Type's. The field
keeps its one-line height; the padding that made the row taller than its own
tallest control goes.

### 3. Send does not empty the field

Every delivery path marks the draft and keeps its text: `markUnknown(...,
clearAfterSend: false)` on the keystroke path, `markSent`/`markUnknown` with
`clearAfterConfirmation` defaulting to false on the helper and clipboard paths.
Spec 015 v1.1 FR-010 made Send a *submit* — the draft leaves with a trailing
Return — so a field that still holds the text after a submit invites sending the
same line twice, which in a terminal is not a cosmetic mistake.

The view half is separate and would have blocked a model-side fix on its own:
`shouldDeferUIKitComposeBindingWrite` refuses any write that would empty a
focused field, which is correct for a stale model mirror and wrong for the user
pressing Send.

**FR-004.** Text that left the device leaves the field. Text that failed to leave
stays, because then the field is the only place it exists.

**FR-005.** The rule lives on `ComposeDraft` as a property of the outcome, not as
a boolean each call site passes. Three call sites with a default-false flag is
three chances to get it wrong, and all three had.

### 4. Follow-activity framing goes

`PiPFramingMode.followActivity` and `PiPAutoFramingPolicy` frame the PiP window on
a damage-weighted centroid. The founder's judgement is that a reliable
"where is the work actually happening" algorithm is not worth building, and a PiP
window that re-frames on the wrong thing is worse than one that holds still.

**FR-006.** The mode is removed from the menu, the settings enum, and the frame
path. A persisted `followActivity` from an older build resolves to
`currentView` rather than failing to decode.

### 5. Choosing a region while PiP is up shows nothing to choose from

With PiP watching, the in-app viewport renders through `pipLayerHost.layer` —
the same `AVSampleBufferDisplayLayer` the system PiP window is displaying. The
system takes that layer's content for the floating window, so the in-app copy is
blank, and "Choose region…" drops the user onto a picker over an empty screen.

**FR-007.** Choosing a region while PiP is up gives the user a picture to choose
from. PiP framing is applied at entry and cannot be adjusted afterwards, so the
window closes for the duration of the pick and re-opens with the region that was
chosen — which is also the only way the choice can take effect.

### 6. Opening or closing the keyboard teleports the viewport

`framebufferLayer`'s `.onChange(of: proxy.size)` calls
`syncImmersiveBaselineZoom`, which sets `targetPan = .zero` whenever the user was
sitting at the baseline zoom. Raising the keyboard shrinks the viewport, which
fires that change, which throws away the pan — so a user who had panned to a
corner is returned to the centre by the act of typing. Switching keyboards
(a globe tap) resizes it twice and does it twice.

**FR-008.** A viewport resize preserves what the user is looking at. The
framebuffer point at the centre of the viewport before the resize is the
framebuffer point at the centre after it, to within a pixel, for any resize that
does not change the zoom.

### 7. A session opens filled, and should open fitted

`immersiveBaselineZoom` opens an immersive session at
`aspectFillZoomScale` — cover, which on a portrait phone against a landscape
desktop means the desktop's *height* fills the screen and most of its width is
off-screen. The founder wants the width.

`ViewportZoomBounds.floorScale` is already documented as exactly that: "On a
portrait phone against a landscape desktop this is precisely the requested 'fit
the width'."

**FR-009.** An immersive session opens at fit. The zoom floor is unchanged, so
this makes the opening state equal to the floor rather than a step above it.

### 8. Host-list previews are mush

`ProfilePreviewThumbnail.init(framebuffer:)` downsamples by point sampling —
`sourceX = Int(Double(x) * sourceXScale)` — so a 3024-wide desktop reduced to 320
wide keeps one pixel in ninety-four and discards the rest. On text, which is what
these desktops are full of, that is not a small loss of sharpness but aliasing:
strokes vanish or double depending on where the sample lands. The 320×200 cap
then leaves the card upscaling on a 3× phone.

**FR-010.** Downsampling averages the source area each destination pixel covers,
so a thumbnail is a smaller picture of the desktop rather than a sample of it.

**FR-011.** The thumbnail is stored at enough resolution for the card to render
it without upscaling on a 3× phone.

## Verification

| Requirement | How |
|---|---|
| FR-001, FR-002 | `KeyboardUpDockHeightUITests.testTheStatusSentenceDoesNotSitOnTheKeys` — no dock element's rect intersects the status sentence's. FAIL-first confirmed against build 12. |
| FR-003 | `KeyboardUpDockHeightUITests` row budget, plus a direct comparison of the Compose row's measured height against Type's. |
| FR-004, FR-005 | `ComposeDraftTests` over the outcome rule; `NaruRemoteAppModelTests` over each of the three delivery paths. |
| FR-006 | `swift build` (the case is gone) plus an `AppSettings` decode test for a persisted `followActivity`. |
| FR-007 | Model-level: choosing a region while watching stops and re-enters. |
| FR-008 | `ViewportTransformTests` — centre-preservation across a resize, as a pure function. |
| FR-009 | `SessionViewportViewTests` over the baseline. |
| FR-010, FR-011 | `ProfilePreviewThumbnailTests` — a synthetic checkerboard downsamples to its average, which point sampling cannot produce. |
| All | iPhone 17 Pro simulator captures before and after; founder device pass on the build that carries this. |

## Measured

Keyboard-up dock chrome, iPhone 17 Pro, `[dock-chrome:*]` from
`KeyboardUpDockHeightUITests`:

| State | Before | After |
|---|---|---|
| Type | 1 row, span 56pt, 96pt to the keyboard | 1 row, **span 41pt, 80pt** |
| Type, degraded transport | 1 row, span 56pt, 96pt | 1 row, **span 41pt, 80pt** |
| Compose | 1 row, span 41pt, 86pt | 1 row, span 41pt, **80pt** |
| Compose, key panel open | 2 rows, span 102pt, 142pt | 2 rows, **span 86pt, 126pt** |
| With a status sentence | **1 row containing the sentence and all four controls** | 2 rows, sentence at y=762..788, controls at 793..834 |

The Type row's 15pt came from the Mac-controls menu, which was a `.bordered`
button among 36pt strip keys; `.bordered` adds its own padding, so one control
decided the height of the row. That is also why the old 72pt row budget never
complained — it had 16pt of slack for exactly this. It is 48pt now.

## Residual risk

An unconfirmed clipboard paste now empties the field like every other dispatch
(FR-004). If a remote app silently refuses the paste, the text has to be
retyped. The alternative is what the founder reported: the default delivery is
the keystroke path, which can never be confirmed, so "keep until confirmed"
meant "never clear" — and re-sending a line that already ran is worse in a
terminal than retyping one that did not.

An immersive session opening at fit means a portrait phone against a 16:9
desktop draws the remote screen across the full width and about a quarter of
the height, with black above and below. That is what fit-to-width is on a tall
screen, and the letterbox bands are where the session chrome can sit without
covering content — but it is a visible change from opening filled, and worth a
look on the device before it is called settled.
