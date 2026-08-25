# Feature Specification: Recompose The Session Chrome

**Feature Branch**: `033-session-chrome-recomposition`
**Created**: 2026-08-25
**Status**: Drafted 2026-08-25.
**Product**: Naru Remote
**Input**: Founder on build 10, in one message: PiP entry "…버튼에 숨겨져 있기는
별로인 거 같아"; the input control "지금 키를 두 개를 표시하는데 하나만 표시하고
표시된 곳 안에서 전환하는 형태로"; the status readout "지금 너무 큰데 이것도 상단
메뉴 안에 포함시켜도 충분하겠어 — 상태 안 좋을 때만 좀 경고로 표시되는 것도 방법이다,
좋을 때는 표시할 필요 없으니까." And then: "이런 맥락을 고려해서 전반 재구성해보자."

## Why

Three separate observations with one cause. The live session screen has
accumulated surfaces that each made local sense and together spend the phone's
screen on chrome rather than on the remote computer.

Measured on the iPhone 17 Pro simulator, `session-active-widescreen` fixture,
portrait, from a capture of the shipped build:

| surface | what it costs | what it is worth |
|---|---|---|
| Diagnostics capsule, top-trailing, `maxWidth 248 × 44` | permanently over the remote screen | "Connected · Good" — the state the user can already see |
| Idle input strip: `Type` + `Compose` pills | two of the three controls in the dock row | one mode is active; the other is a mode switch dressed as a destination |
| PiP entry | zero pixels, and unreachable | two taps behind `⋯`, which itself hides after 2.4 s |

The last row is the one that reads as a design error rather than a trade: PiP
Watch is a headline capability of a phone remote client — it is what lets a
long-running remote job stay visible — and it is the single least reachable
control on the screen. Meanwhile the space it could occupy is held by a capsule
whose message when everything is fine is that everything is fine.

## Requirements

- **FR-001 PiP is a first-class control.** A PiP toggle sits in the session
  control bar (immersive) and in the header action row (standard), enabled
  exactly when PiP is available. It reflects live state — enter versus exit — so
  it is also how a session leaves PiP.
- **FR-002 One input control, switchable in place.** The idle dock shows a
  single capsule for the current mode. Tapping the label raises that mode's
  dock; a trailing segment inside the same capsule switches mode. Two
  destinations become one control with a switch in it, which is what the founder
  described.
- **FR-003 Health is silent when it is healthy.** The diagnostics affordance
  collapses into the control bar as an icon-sized element while the session is
  active and quality is good. It is not removed: it keeps its identifier, its
  44-point target, and its sheet.
- **FR-004 A bad state is louder than a good one.** When the tone is anything
  but healthy the affordance renders with its label and, because the control bar
  auto-hides, also as a standalone chip so a warning is never behind a hidden
  bar. The two placements are mutually exclusive, so exactly one element carries
  the identifier at any moment.
- **FR-005 Diagnostics stay reachable at all times.** With the capsule collapsed
  to an icon, the tools menu also carries a Diagnostics item, so the sheet has a
  labelled path that does not depend on recognising a dot.
- **FR-006 The PiP status chip over the viewport is retired.** Its text is now
  the button's state (FR-001), and a chip that narrates a control next to it is
  the accumulation this spec is removing.
- **FR-007 Identifiers follow the elements.** The single input capsule takes a
  new stable identifier and the mode-specific identifiers move onto the switch's
  menu items. Tests that drove the old two-pill layout are updated to drive the
  new one rather than kept alive against elements that no longer exist.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — placement rules | a healthy session shows no standalone chip and does show the inline one; everything else is the reverse; neither renders without a session | FAIL-first: the shipped rule was `sessionWarrantsInputDock` alone, which returns true for active+good |
| `swift test` — collapse rule | only active-and-good collapses; nine other state/quality pairs do not | direct |
| iPhone simulator, fixture captures | the recomposed bar and dock, healthy **and** degraded | done — `session-active-widescreen` and the new `session-degraded` fixture |
| iPhone simulator, existing UITests | the reveal / dock / liveness gates still drive the new elements | full `NaruRemoteUITests` |
| Founder device, build 11 | PiP is findable, the dock reads as one control, a good session shows no status furniture | founder device pass |

The first capture of the recomposed bar overflowed the screen — six controls
plus a 120-point "Connections" label, with the tools button clipped at the right
edge. The label is icon-only on compact width now. Worth recording because the
`swift test` rules were all green while the bar was unusable: placement logic
and layout are separate failures, and only the capture caught the second.

## Non-Goals

- The immersive bar's auto-hide behaviour and its 2.4 s timing. Unchanged.
- The accessory key strip, the Fn row, and the Mac window controls menu. This
  spec touches how the dock is *entered*, not what it contains.
- Any change to what diagnostics report. The sheet and the export are the same;
  only the affordance's size and placement change.
- iPad-specific layout work. The standard header gets the same controls, but the
  design target here is the phone (constitution §VI).

## Residual Risk
- Hiding a healthy status is a bet that the user does not need continuous
  reassurance. If a silent session that has actually stalled now reads as
  healthy, the tone rule is the thing that is wrong — and spec 028's
  presentation ledger, not this chrome, is what would have to catch it.
- A trailing switch segment inside a capsule is a small target next to a large
  one. The label area is the primary action, so a mis-tap opens the dock rather
  than changing mode, which is the recoverable direction.
- Seven UITests use the diagnostics capsule as their "session is live" landmark.
  Keeping the identifier on the collapsed element is what makes that safe, and
  it is asserted rather than assumed.
