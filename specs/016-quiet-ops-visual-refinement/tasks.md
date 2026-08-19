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

## Found while working here (not spec 016)

- [x] **T009** The UX-audit capture harness's second mislabeling incident: a
  full-suite iPhone run overwrote 30 `-ipad-*` capture files with iPhone
  pixels (hard-coded per-test device tags). Closed structurally at the single
  write owner — `saveScreen` now XCTSkips any capture whose filename claims a
  device the runner is not. FAIL-first: the overwrite reproduced in this
  session before the guard; after it, the iPad-slot test skips on iPhone.
