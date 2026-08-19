# Feature Specification: Single-Row Input Dock

**Feature Branch**: `015-single-row-input-dock`
**Created**: 2026-08-19
**Status**: Implemented 2026-08-19 — Type mode measures **1 row / 41pt** above the keyboard (from 6 rows / 368pt), Compose 1 row / 88pt, `⋯` open exactly 2 rows; iPad keeps the permanent strip (2 rows). Gates: `swift test` 1597/0 failures; `KeyboardUpDockHeightUITests` 4/4 on iPhone 17 Pro and iPad Pro 13-inch; full `NaruRemoteUITests` 75 tests green on iPhone 17 Pro Max. Residual: the founder's device pass (§Residual Risk).
**Product**: Naru Remote
**Input**: Founder direction 2026-08-19 — "키보드 입력시 하단 영역 충분히 컴팩트해졌니? 나는 아예 특수키도 기본적으로 …이나 햄버거로 숨겨서 키보드 위에 딱 한 줄만 나오게 만들고 [싶다]". Measured against the shipped build before any change (numbers below).

## Problem

While the software keyboard is up — the founder's primary posture (constitution §VI:
sustained terminal/AI-CLI work from an iPhone) — the dock stacks **six rows** between
the keyboard and the remote screen. Measured on iPhone 17 Pro (window 402×874,
`store-session-active` fixture, Type mode focused, `KeyboardUpDockHeightUITests`):

| y | Row | Height |
| --- | --- | --- |
| 505 | `naru.input.focused-status` — "Ready to compose locally" | 25 |
| 538 | accessory strip + `Fn` | 40 |
| 586 | Mac controls menu + Type⇄Compose toggle | 52 |
| 646 | `naru.input.live-disclosure` badge | 25 |
| 688 | compose/mirror editor | 88 |
| 791 | remote ⌫ / ↵ | 41 |
| | **total chrome above the keyboard** | **368pt** |

368pt is **42% of the screen**. With a real software keyboard (~300pt portrait) the
remote screen — the only thing the user opened the app for — is left roughly 206pt,
**24%**. Compose measures 349pt.

Two structural causes, not six independent ones:

1. **Every affordance owns a row.** The compact dock is a `VStack` where each concern
   (status, keys, mode, disclosure, editor, remote ⌫/↵) appends a row. Nothing forces
   a budget, so each feature that shipped since spec 011 added height that no gate
   measured.
2. **Status text is rendered as layout.** Three separate status surfaces
   (`focused-status`, `live-disclosure`, `live-status`) can occupy rows simultaneously,
   and the top one says "Ready to compose locally" — it carries no information the user
   can act on, yet it costs a row and 25pt whenever the field is focused.

## Ground Truth

- `KeyboardUpDockHeightUITests` (added with this spec) measures the union of every dock
  element that sits above the keyboard, from an identifier list rather than a
  hard-coded row list, so a newly added row is caught instead of being excluded.
- Spec 009 **FR-014** requires disclosure of a *degraded* transport (clipboard =
  unconfirmed + settle latency, ASCII = ASCII-only). It does not require a permanent
  row for the nominal helper path.
- Spec 009 **FR-013** requires per-window delivery status from a fixed catalog and
  forbids presenting the helper path's observed delivery as "unknown".
- Spec 011 US2 put terminal keys "one tap above the editor in both modes". One tap
  from a `⋯` button is still one tap; the requirement was tap count, not permanent
  screen area.
- The keyboard-down state is already a single floating pill row
  (`floatingControlStrip`) — this spec is about the keyboard-**up** state only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — One Row While Typing (Priority: P0)

The user raises the keyboard in Type mode and types into a remote terminal. Between the
keyboard and the remote screen there is exactly one row: a `⋯` keys button, the input
field, and the mode/send action. Nothing else.

**Acceptance Scenarios**:

1. **Given** an active session in Type mode with the keyboard up and nothing degraded,
   **When** the chrome above the keyboard is measured, **Then** it is a single row
   ≤ 72pt including the dock surface's own padding.
2. **Given** the same state, **When** the user looks for terminal keys, **Then** a `⋯`
   button is present in the row and is the only affordance that was added.
3. **Given** Compose mode with a draft, **When** the chrome is measured, **Then** it is
   at most the row plus the multi-line editor (≤ 152pt), and Send remains visible
   without scrolling.

### User Story 2 — Special Keys One Tap Behind `⋯` (Priority: P0)

The user needs Esc, ⌃C, arrows, F-keys, ⌫/↵ or the Mac window controls. One tap on `⋯`
reveals the key panel above the row; it stays open until dismissed, so a terminal
session that needs it keeps it.

**Acceptance Scenarios**:

1. **Given** the collapsed row, **When** the user taps `⋯`, **Then** the accessory
   strip appears (sticky modifiers, Esc, Tab, ⌃C, arrows, Del, remote ⌫/↵, the `Fn`
   toggle and the Mac controls menu) and every key emits exactly the wire envelope it
   emitted before this change.
2. **Given** the panel open, **When** the dock is recreated by a placement swap (the
   compose-reveal path already does this), **Then** the panel is still open — the
   expansion is app-model state, not view state.
3. **Given** a new live session, **When** the keyboard is raised for the first time,
   **Then** the panel is collapsed (hidden by default, per founder direction).
4. **Given** the regular-width (iPad) pinned dock, **When** it renders, **Then** the
   strip stays visible without a tap — the height pressure this spec fixes is a compact
   -width problem, and iPad has the room.

### User Story 3 — Status Costs Nothing When Nothing Is Wrong (Priority: P1)

The user typing over a healthy helper transport sees no status text. A user whose text
is going out over the clipboard or as ASCII-only keystrokes sees exactly one line
saying so, because that one can lose their Korean.

**Acceptance Scenarios**:

1. **Given** Type mode on the helper `nativeInsert` tier with no failures, **When** the
   dock renders, **Then** there is no status row and no disclosure row; the full
   transport sentence is available in the `⋯` panel and in session diagnostics.
2. **Given** the clipboard or ASCII tier, **When** the dock renders, **Then** exactly
   one line discloses it (FR-014 copy unchanged).
3. **Given** a delivery that failed and retained the text, **When** the dock renders,
   **Then** that status wins the single line over the transport disclosure.
4. **Given** a successful delivery, **When** it lands, **Then** it is signalled by the
   existing crossing pulse overlay (zero height) and never rendered as "unknown"
   (FR-013).
5. **Given** any state, **When** the dock renders, **Then** at most one status line
   exists — the three status surfaces share one slot.

## Requirements *(mandatory)*

- **FR-001**: The compact (`compact` horizontal size class) dock MUST, with the
  keyboard up and no degraded/failed state, present exactly one row of chrome above the
  keyboard, ≤ 72pt including the dock surface padding.
- **FR-002**: That row MUST contain, in order: the `⋯` key-panel toggle, the input
  field, the Type⇄Compose toggle, and — in Compose only — Send.
- **FR-003**: Sticky modifiers, Esc/Tab/⌃C/arrows/Del, the `Fn` expansion, remote ⌫/↵,
  and the Mac window controls MUST move into the `⋯` panel, keeping their existing
  identifiers, emission paths and wire envelopes.
- **FR-004**: The panel's expanded/collapsed state MUST live on the app model
  (surviving dock recreation), MUST default to collapsed for each session, and MUST NOT
  persist to disk.
- **FR-005**: Regular-width pinned docks MUST keep the strip visible without a tap.
- **FR-006**: The dock MUST render at most one status line, and none when the transport
  tier is nominal and no delivery has failed. Degraded tiers (clipboard, ASCII) and
  failure/limit statuses MUST still render, with copy unchanged from spec 009.
- **FR-007**: The "Ready to compose locally" focused-status placeholder MUST be
  removed — it costs a row and carries nothing actionable.
- **FR-008**: Type mode's mirror field MUST be single-line height; Compose keeps its
  multi-line editor.
- **FR-009**: A UI test MUST measure the chrome above the keyboard and fail when the
  budget is exceeded, measuring from an identifier list of all dock rows so a future
  row cannot be silently excluded.

### Key Entities

- **`RemoteInputAccessoryPanel`** — the collapsed/expanded key surface. Model-owned
  boolean plus the existing `AccessoryKey` / `StickyModifierState.Modifier` content.
- **`RemoteInputDockStatusSlot`** — the single status line and its priority rule:
  failure/limit status > degraded transport disclosure > nothing.

## Verification Matrix

| Layer | What it proves |
| --- | --- |
| `swift test` — `SimplifiedInputUxModelTests`, new dock-plan unit tests | panel default/toggle/persistence-free state; status slot priority; nominal → no line |
| `swift test` — existing strip emission tests | wire envelopes unchanged after the move into the panel |
| XCUITest — `KeyboardUpDockHeightUITests` (iPhone 17 Pro, iOS 26.2) | FR-001/FR-009 geometry: one row ≤ 72pt in Type, ≤ 152pt in Compose |
| XCUITest — `StickyModifierStripUITests`, `UXAuditScreenshotsUITests` | modifiers and store screenshots survive the panel move |
| XCUITest — iPad Pro 13-inch (M5) | FR-005: regular-width strip still visible untapped |
| Manual device (iPhone, residual) | the founder's own judgement on the collapsed row during a real terminal session |

## Residual Risk

- The measurement runs on a simulator whose hardware keyboard is attached, so the
  reference line is the window bottom rather than a software keyboard's top edge. The
  row layout above it is identical, but the founder's device pass is what confirms the
  felt result.
- Hiding the strip by default costs one tap for users who want it always on. Mitigated
  by FR-004 (it stays open once opened, across dock recreation). If the founder wants
  it remembered across sessions, that is a one-line change to persist the flag.
