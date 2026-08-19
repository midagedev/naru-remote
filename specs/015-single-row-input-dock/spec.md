# Feature Specification: Single-Row Input Dock

**Feature Branch**: `015-single-row-input-dock`
**Created**: 2026-08-19
**Status**: Implemented 2026-08-19, **amended to v1.1 the same day** after the founder used build 3 on device. v1.1 changes: the compact Compose field is one line tall (40pt, was 88pt); Compose Send submits with a trailing Return; Type mode has **no visible text field** — its row is the soft-key strip itself (remote ⌫/↵ leading, no `⋯`), with the mirror editor surviving as a 1×1 hidden first responder and a keyboard-dismiss key replacing the field's drag-dismiss.
**Product**: Naru Remote
**Input**: Founder direction 2026-08-19 — "키보드 입력시 하단 영역 충분히 컴팩트해졌니? 나는 아예 특수키도 기본적으로 …이나 햄버거로 숨겨서 키보드 위에 딱 한 줄만 나오게 만들고 [싶다]". Measured against the shipped build before any change (numbers below). **v1.1 input**, after the founder ran build 3 on device: "키보드 컨트롤 레이아웃이 아직도 너무 상하로 높아 — 멀티라인 입력용 필드인 것 같은데 한 줄짜리로. 컴포즈 모드의 쓰기 버튼은 기본적으로 submit(엔터)이 포함되어야 해. type 모드는 굳이 텍스트 표시 필드 필요 없어 — 백스페이스와 엔터만 잘 되면 되니 소프트키 한 줄만."

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
- **FR-002** *(v1.1)*: **Compose**'s row MUST contain, in order: the `⋯` key-panel
  toggle, a **one-line (40pt) input field** — long drafts scroll inside it, never grow
  it — the Type⇄Compose toggle, and Send. **Type**'s row MUST contain: the soft-key
  strip (see FR-008), a keyboard-dismiss key, and the Type⇄Compose toggle — no text
  field, no `⋯`, no Send.
- **FR-003**: Sticky modifiers, Esc/Tab/⌃C/arrows/Del, the `Fn` expansion, remote ⌫/↵,
  and the Mac window controls MUST move into the `⋯` panel, keeping their existing
  identifiers, emission paths and wire envelopes. *(v1.1)* In Type mode the same strip
  renders inside the row itself, with remote ⌫/↵ leading (the founder named them the
  keys that must never need a scroll); Compose keeps the spec 012 order.
- **FR-004**: The panel's expanded/collapsed state MUST live on the app model
  (surviving dock recreation), MUST default to collapsed for each session, and MUST NOT
  persist to disk.
- **FR-005**: Regular-width pinned docks MUST keep the strip visible without a tap.
- **FR-006**: The dock MUST render at most one status line, and none when the transport
  tier is nominal and no delivery has failed. Degraded tiers (clipboard, ASCII) and
  failure/limit statuses MUST still render, with copy unchanged from spec 009.
- **FR-007**: The "Ready to compose locally" focused-status placeholder MUST be
  removed — it costs a row and carries nothing actionable.
- **FR-008** *(v1.1, supersedes "single-line mirror field")*: Type mode MUST render
  **no visible text field**. The mirror editor survives as a 1×1pt hidden view because
  it is the first responder that keeps the software keyboard raised and owns the IME
  marked→committed boundary — every delivery path, commit trigger and local-echo
  behavior from spec 009 is unchanged. Because removing the field removes its
  interactive drag, the row MUST carry a keyboard-dismiss key.
- **FR-009**: A UI test MUST measure the chrome above the keyboard and fail when the
  budget is exceeded, measuring from an identifier list of all dock rows so a future
  row cannot be silently excluded.
- **FR-010** *(v1.1)*: Compose Send MUST submit: the draft leaves with exactly one
  trailing Return — appended only when the draft does not already end in a newline,
  and never to an empty draft. On the keystroke-stream path (the product default)
  this is a real Return keypress (keysym 0xFF0D) after the text; on the clipboard and
  helper paths it is a trailing newline in the payload, which a terminal executes and
  a GUI text field renders as a line break (honest limit — those transports cannot
  order a separate key event after their own delivery).

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
| XCUITest — `KeyboardUpDockHeightUITests` (iPhone 17 Pro, iOS 26.2) | FR-001/FR-009 geometry: one row ≤ 72pt in both modes (v1.1); Type has no visible editor and no `⋯` |
| `swift test` — `LiveTypeThroughRoutingTests` submit tests (v1.1) | FR-010: keystroke Send ends with exactly one Return press; payload helper never doubles or fires empty |
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
- *(v1.1)* With no visible Type-mode field, an **in-flight Korean syllable** (marked
  text, not yet committed) has no local echo — committed text echoes on the remote
  screen itself, which is the type-through contract, but the syllable being composed
  is invisible until it commits. Accepted by the founder's direction ("백스페이스와
  엔터만 잘 되면"); Compose remains the surface for watching Korean text form.
- *(v1.1)* FR-010's submit is a payload newline on the clipboard/helper paths, not a
  Return keypress — a GUI chat app reached over those transports gets a line break,
  not a send. The keystroke-stream default is unaffected.
