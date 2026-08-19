# Implementation Plan: Single-Row Input Dock

**Spec**: `specs/015-single-row-input-dock/spec.md`
**Created**: 2026-08-19
**Status**: Implemented 2026-08-19

## Approach

The six rows were not six independent features — they were one missing owner.
`compactAccessoryBody` was a `VStack` that any new affordance could append to,
and nothing measured the result. So the plan is: give the keyboard-up dock a
single row, give the rows that lost their place one owner (`⋯`), and put the
budget under a gate that counts rows.

### Layer 1 — structural blockade

| Concern | Before | After |
| --- | --- | --- |
| Terminal keys, modifiers, `Fn` | permanent row | inside the `⋯` panel |
| Mac window controls | shared a 52pt row with the mode switch | inside the `⋯` panel's scroll (not pinned beside `Fn`, which would push ⌃C out of the no-scroll zone spec 012 US2-2 reserved for it) |
| Remote ⌫ / ↵ | own row | inside the `⋯` panel, still as `ComposeQuickKey` emissions so Type mode's local mirror stays in step (spec 009 D1) |
| Type⇄Compose switch | own row, labelled pill | icon-only on the row |
| Send | own row, labelled | icon-only on the row |
| `focused-status` | own row, "Ready to compose locally" | removed |
| `live-disclosure`, `live-status` | up to two rows | one line, degraded/actionable only, and only at compact width |
| Type mirror editor | 88pt (3 lines) | 40pt (1 line) |

The panel's expanded flag lives on `NaruRemoteAppModel`
(`isRemoteInputAccessoryPanelExpanded`) and travels on the snapshot, because the
compose-reveal placement swap recreates the dock view — the same reason
`composeExpansionRequested` was hoisted in 2026-07. It is reset by
`resetLiveTypeThroughState()`, i.e. with the rest of the per-session Live state,
so a new session starts collapsed and a Type⇄Compose switch does not collapse it.

The shell's status line moved from a `VStack` sibling to
`.overlay(alignment: .top)` on the dock host. That is what makes FR-007
possible: the placeholder existed to hold the stack slot open, because
adding/removing that row mid-typing changed the container's children and
collapsed the keyboard safe-area layout under UIKit IME. As an overlay its
presence cannot move the dock at all.

### Layer 2 — recurrence gate

`NaruRemote/UITests/KeyboardUpDockHeightUITests.swift` measures the chrome above
the keyboard and states the contract in **rows**: it collects every dock element
from an identifier list, groups them into bands of vertically overlapping
elements, and asserts one band in Type, one in Compose, and exactly one more
when `⋯` is open. Rows are keyboard-independent (a simulator with a hardware
keyboard raises none; the dock then rests on the bottom safe area and the rows
above are identical), and the identifier list means a newly added row is
measured rather than excluded.

FAIL-first, measured on the pre-change build (iPhone 17 Pro, 402×874):

```
[dock-chrome:type]    368pt, 6 rows — focused-status | strip+Fn | mac+mode | live-disclosure | editor | ⌫↵
[dock-chrome:compose] 349pt, 6 rows
```

After:

```
[dock-chrome:type]          1 row, span 40pt
[dock-chrome:compose]       1 row, span 88pt
[dock-chrome:type-expanded] 2 rows (panel + row), span 106pt
```

Model-side, `SimplifiedInputUxModelTests` pins the panel's default, idempotent
toggle, and per-session reset.

### Layer 3 — debuggability

The measurement prints one line per state (`[dock-chrome:type] 1 row(s), span
40pt … row 1 y=786..826: naru.input.editor + naru.input.mode-toggle`) and
attaches the screenshot, so "how tall is the dock right now, and what is in it"
is answered by running one test instead of by reading SwiftUI.

## Files

| File | Change |
| --- | --- |
| `NaruRemote/App/Features/RemoteInputDock/RemoteInputDockView.swift` | single row, `⋯` panel, icon-only mode/Send, panel-gated strip, migrated ⌫/↵ + Mac controls, disclosure/status gating |
| `NaruRemote/App/AppShell/NaruRemoteAppModel.swift` | `isRemoteInputAccessoryPanelExpanded` + setter + per-session reset |
| `NaruRemote/App/AppShell/NaruRemoteAppSnapshot.swift` | panel flag on the snapshot; `liveDegradedTransportDisclosureText`, `liveActionableStatusText` |
| `NaruRemote/App/AppShell/NaruRemoteAppShell.swift` | render-state plumbing, status line as overlay, `RemoteInputDockStatusLineState` rule |
| `NaruRemote/UITests/KeyboardUpDockHeightUITests.swift` | new row gate |
| `NaruRemote/UITests/{StickyModifierStrip,UXAuditScreenshots}UITests.swift` | reveal the panel before asserting/capturing the strip |
| `NaruRemote/Tests/NaruRemoteAppTests/{SimplifiedInputUxModel,RemoteInputDockRenderState}Tests.swift` | panel state; status-slot contract |

## Rejected alternatives

- **Shrink the rows instead of removing them.** Six rows at 28pt is still six
  rows and 200pt; the founder asked for one.
- **Keep the status rows but make them shorter.** The problem is not their
  height, it is that a nominal state was rendering at all.
- **Put the disclosure behind `⋯` unconditionally.** Spec 009 FR-014 exists so a
  clipboard/ASCII transport is never misrepresented; hiding that behind a tap
  would trade a real honesty requirement for 25pt.
- **Collapse the strip at regular width too.** iPad has the height; FR-005 keeps
  it permanent there, which also keeps the iPad store captures honest.
