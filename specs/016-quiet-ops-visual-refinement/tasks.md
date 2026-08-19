# Tasks: Quiet Ops Visual Refinement (round 1)

- [x] **T001** Audit captures (iPhone light) of host list, session, editor;
  findings written into spec.md §Problem.
- [x] **T002** Host card: status dot-capsule, tag row, radius 12 + shadow,
  opaque `…` (FR-001..003). File: `ConnectionGridView.swift`.
- [x] **T003** Header `+` → Signal Blue filled circle (FR-004).
- [x] **T004** Session bar: uniform icon weight; Disconnect `bolt.slash.fill`
  + Coral token (FR-005). File: `SessionViewportView.swift`.
- [x] **T005** Floating pill Compose glyph → `square.and.pencil` (FR-006).
  File: `RemoteInputDockView.swift` (floating strip + compact reveal).
- [x] **T006** Contrast rows for new pairs (FR-008). File:
  `NaruColorContrastTests.swift`.
- [x] **T007** Re-run grid/session UI suites + re-capture audits; lead vision
  pass on before/after.
- [~] **T008** Founder device pass (residual).

Follow-on candidates (await founder's reaction): profile editor form styling,
empty-state polish, dark-theme sweep, diagnostics sheet.

## Round 2 (founder greenlit follow-on, 2026-08-20)

- [x] **T010** Status-token sweep (FR-009): `DiagnosticSummaryView`,
  `SessionViewportView` (quality chip, status icon, reconnect badge),
  `ProfileListView` (selected mark → Signal Blue, status colors, edit tint),
  `SessionPerformanceHUDView` (`.orange` → warning).
- [x] **T011** Profile editor input traits (FR-010): host + helper host get
  URL keyboard / no autocorrect / no autocap; name drops autocorrect.
  File: `ProfileEditorView.swift`.
- [x] **T012** Diagnostics stage code goes tertiary (FR-011). File:
  `DiagnosticSummaryView.swift`.
- [x] **T013** `swift test` green with the round-2 edits (one failure was the
  spec 017 live gate's workload-dependent assertion — corrected in spec 017,
  not a 016 defect); editor/diagnostics/selected captures re-shot on iPhone
  light+dark; lead vision pass confirmed URL keyboard + token colors +
  tertiary stage codes.
- [~] **T014** Founder device pass (residual).

## Found while working here (not spec 016)

- [x] **T009** The UX-audit capture harness's second mislabeling incident: a
  full-suite iPhone run overwrote 30 `-ipad-*` capture files with iPhone
  pixels (hard-coded per-test device tags). Closed structurally at the single
  write owner — `saveScreen` now XCTSkips any capture whose filename claims a
  device the runner is not. FAIL-first: the overwrite reproduced in this
  session before the guard; after it, the iPad-slot test skips on iPhone.
