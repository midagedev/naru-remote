# Tasks: Single-Row Input Dock

Status legend: `[x]` done · `[ ]` open · `[~]` needs the founder's hardware.

## Measurement first

- [x] **T001** Write the row gate before the change and record the failing
  numbers (`KeyboardUpDockHeightUITests`; iPhone 17 Pro measured 368pt / 6 rows
  in Type, 349pt in Compose). FAIL-first for every requirement below.

## US1 — one row while typing

- [x] **T002** Collapse `compactAccessoryBody` to one row: `⋯` · field · mode ·
  Send (`RemoteInputDockView.swift`).
- [x] **T003** Icon-only Type⇄Compose switch and Send, sized so the *field*
  decides the row height (a 40pt label under `.bordered` measured 54pt and made
  the switch the tallest thing on the row).
- [x] **T004** Type mirror editor to a single line; Compose keeps multi-line
  (FR-008).
- [x] **T005** Gate: one band in Type (span ≤ 72pt), one in Compose (≤ 128pt).

## US2 — keys behind `⋯`

- [x] **T006** `isRemoteInputAccessoryPanelExpanded` on the app model + snapshot,
  default collapsed, reset with the per-session Live state, never persisted
  (FR-004).
- [x] **T007** Panel-gate the accessory strip at compact width; keep it
  permanent at regular width and drop the `⋯` there (FR-005).
- [x] **T008** Move remote ⌫/↵ into the panel as `ComposeQuickKey` emissions
  (mirror-safe in Type mode) and the Mac controls into the panel's scroll, after
  measuring that pinning them beside `Fn` pushed ⌃C out of the no-scroll zone.
- [x] **T009** Model tests: default collapsed, idempotent toggle, collapses on
  session teardown.
- [x] **T010** Gate: revealing the panel adds exactly one row.
- [x] **T011** Point `StickyModifierStripUITests` and the store/audit captures
  at the revealed panel (one tap, the way a user gets there).

## US3 — status costs nothing when nothing is wrong

- [x] **T012** `RemoteInputDockStatusLineState`: drop the "Ready to compose
  locally" placeholder; speak for a non-`.sent` attempt or a helper problem
  (FR-006/FR-007).
- [x] **T013** Render the shell status line as an overlay above the dock, so its
  presence cannot move the dock or disturb the keyboard safe-area layout under
  UIKit IME — which is why the placeholder existed.
- [x] **T014** `liveDegradedTransportDisclosureText` / `liveActionableStatusText`
  on the snapshot; the compact dock renders only those, standard width keeps
  spec 009 FR-013/FR-014 copy exactly as before.
- [x] **T015** Update the render-state tests to the new contract, keeping the
  invariant that matters (status churn must not repaint the focused dock).

## Verification

- [x] **T016** `swift test --skip LiveMac` — 1597 tests, 0 failures.
- [x] **T017** iPhone 17 Pro `KeyboardUpDockHeightUITests` — 3/3, numbers in
  `plan.md`.
- [x] **T018** Full `NaruRemoteUITests` on iPhone 17 Pro Max.
- [x] **T019** iPad Pro 13-inch — FR-005 (strip visible untapped).
- [~] **T020** Founder's device pass: the felt result with a real software
  keyboard, which the simulator (hardware keyboard attached) cannot show.

## Found while working here (not spec 015)

- [x] **T021** `LocalMacConnectE2EUITests.testWrongPassword_showsActionable
  AuthDiagnostic` was waiting for the session diagnostics corner, which spec 013
  US-4 (2026-08-19) removed from the failed-connect path — a failing connect
  keeps the host list. Repointed at the card's failure annotation and its
  Diagnostics action; the asserted behaviour is unchanged.
- [x] **T022** Same test, second cause: the suite's host defaulted to a
  hard-coded LAN address (`192.168.45.148`) from the network it was written on.
  Nothing answers there, so an unconfigured run failed at DNS/TCP and could
  never reach the authentication stage whose copy the test asserts — a default
  that cannot produce the outcome under test. Now defaults to `127.0.0.1`, this
  Mac's own Screen Sharing server (the same target `LiveMac*` tests use), with
  `NARU_E2E_HOST` still overriding.

## v1.1 — founder's on-device feedback (2026-08-19, build 3)

- [x] **T023** One-line Compose field: `compactComposeEditorHeight = 40`
  replaces the 44/88 idle/expanded pair; long drafts scroll inside the line.
- [x] **T024** Compose Send submits: `sendComposedTextUsingPreferredDelivery(_:
  submittingWithReturn:)` appends exactly one trailing Return via
  `composeSubmitPayload` (never doubles, never fires on an empty draft); shell
  passes `true`. Keystroke path verified to end with one 0xFF0D press
  (`LiveTypeThroughRoutingTests`).
- [x] **T025** Type mode row = soft-key strip: visible field removed, mirror
  editor kept as a 1×1 hidden first responder (IME commit boundary intact),
  remote ⌫/↵ lead the strip, `⋯` gone from Type (nothing left to reveal).
- [x] **T026** Keyboard-dismiss key (`naru.input.keyboard-dismiss`) replaces
  the removed field's interactive drag as the way to lower the keyboard.
- [x] **T027** Gate rework: `KeyboardUpDockHeightUITests` — Type asserts
  strip-untapped/no-`⋯`/editor ≤ 1pt at every width; Compose budget tightened
  to the shared 72pt; FR-005 and `⋯` tests re-anchored on Compose.
