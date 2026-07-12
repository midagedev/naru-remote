---
description: "Task list for Live Type-Through Input Mode (spec 009)"
---

# Tasks: Live Type-Through Input Mode

**Input**: `/specs/009-live-type-through/spec.md` (Accepted 2026-07-05), `plan.md`  
**Product**: Naru Remote  
**Constitution gate**: passed in `plan.md`. All `[NEEDS CLARIFICATION]` resolved via founder decisions D1/D2/D3.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable — disjoint write set from other `[P]` tasks in the same phase.
- **[Story]**: maps to a `spec.md` user story (US1–US5) and FR IDs.
- Every task lists exact file paths and the test/evidence that closes it.

## Phase 1: Readiness

- [x] T001 Read `spec.md` (Accepted), `plan.md`, spec 002 (Direct) and spec 006 (helper bridge), and confirm no `[NEEDS CLARIFICATION]` remain (grep clean). No code.
- [x] T002 Confirm the reuse surface compiles/exists: `TextInjectionAdapter`, `KeystrokeEmitter`, `KeysymMapping` (`.backspace`=0xFF08, `.return`=0xFF0D), `HelperTextBridge`, `NaruHelperNetworkTextInsertClient`, `OutboundInputEventDispatcher`, `ComposeQuickKey` (⌫/↵), `MultilingualComposeTextView` marked-text machinery in `RemoteInputDockView.swift`. No code.

**Checkpoint**: grounded; no coding before this passes.

---

## Phase 2: T-core — pure state machine (`NaruRemoteCore`, no UIKit)

**Goal**: value types + window/diff/coalesce/FIFO/seal logic, fully unit-tested with no session.  
**Owns**: `NaruRemote/Sources/NaruRemoteCore/RemoteInputDock/LiveTypeThroughMode.swift`, `.../LiveEditingWindow.swift`, `NaruRemote/Tests/NaruRemoteCoreTests/LiveEditingWindowTests.swift`.

- [x] T003 [US2] Add `LiveTypeThroughMode` value type (active flag, selected insert-adapter tier for open window, persistent disclosure descriptor; resets to Compose default on session start — FR-016) in `LiveTypeThroughMode.swift`. Peer to `DirectKeystrokeMode`. Mirror its `Codable`/default pattern. Closes: type compiles; unit test in T007.
- [x] T004 [US1/US3] Add `LiveEditingWindow` + operation/status types (fixed catalog) in `LiveEditingWindow.swift` (`LiveTypeThroughWindow`, `LiveTypeThroughOperation`) and `LiveDeliveryLadder.swift` (`LiveTypeThroughAdapterTier`, `LiveDeliveryStatus`, `LiveInsertPayloadKind`): delivered-text mirror (process-local), pending coalesced insert buffer, sealed flag, fixed invalidation reason, active insert tier. FR-003/FR-013.
- [x] T005 [US1/US3] Implement the reconciliation diff → ordered op stream: grapheme-cluster common-prefix diff producing forward inserts + a grapheme-count delete; never split a grapheme (FR-003); marked text excluded (FR-002). In `LiveEditingWindow.swift`.
- [x] T006 [US3/US5] Implement coalescing + FIFO + sealing as pure functions in `LiveEditingWindow.swift`: single-in-flight semantics (coalesce while a chunk is in flight), delete flushes pending inserts first (FR-007/FR-008), `seal(reason:)` blocks any subsequent cross-seal delete (FR-011), fresh forward-only window on resume.
- [x] T007 [P] [US1/US2/US3/US5] Unit tests in `LiveEditingWindowTests.swift` (28 tests green): marked text yields no ops; `hte`→⌫→`e`→Return op ordering; grapheme integrity; coalescing under burst; seal blocks cross-seal delete; mode reset. `swift test --filter LiveEditingWindowTests`.

**Checkpoint**: `swift build && swift test` green; state machine correct with zero UIKit/session deps.

---

## Phase 3: T-model — app-model wiring (`NaruRemoteApp`, `@MainActor`)

**Goal**: mode state, per-commit dispatch, adapter-ladder routing, delete/Return via VNC key lane, status surfacing incl. degraded-clipboard disclosure.  
**Owns**: `NaruRemote/App/AppShell/NaruRemoteAppModel.swift` (+ snapshot if state added), `NaruRemote/Tests/NaruRemoteAppTests/LiveTypeThroughRoutingTests.swift` (app-model routing tests belong in `NaruRemoteAppTests`, not `NaruRemoteCoreTests` — the Core target has no app model).  
**Depends on**: Phase 2.

- [x] T008 [US2] Add `liveTypeThroughMode` published state to `NaruRemoteAppModel` alongside `directKeystrokeMode`; reset to Compose default on session start / disconnect / profile change (FR-016), and seal any open Live window on those transitions (FR-011). Included in `NaruRemoteAppSnapshot` (memory-only, plus `liveFieldText` mirror + `liveReachedWindowStart` — SP-002).
- [x] T009 [US1/US4] Implement per-window insert-tier selection at window open (helper reachable → `nativeInsert`; else clipboard usable → chunked clipboard paste; else ASCII → `KeyEvent`), held for the window, no mid-window insert-adapter switch; insert-adapter failure seals + retains + safe failure (FR-004/FR-006). Reuses `HelperTextInsertClient`, the Compose clipboard-provide+paste path (`setClipboardText`+`sendPasteCommand` with the 0.30 s settle), and `KeystrokeEmitter`.
- [x] T010 [US1] Implement the per-commit dispatch loop: feed committed/marked snapshots to `LiveTypeThroughWindow`, deliver insert ops on the selected tier with single-in-flight + coalescing (FR-008); never emit Unicode `KeyEvent` (FR-005).
- [x] T011 [US3] Implement delete + line-boundary routing (D1): delete → N × `BackSpace` (0xFF08) key events; Return → `Return` (0xFF0D) — both via `OutboundInputEventDispatcher` key lane (`enqueueKeyEventEmission`), orthogonal to insert tier (FR-005/FR-009/FR-010). Deletes flush pending inserts first.
- [x] T012 [US1/US4] Map `LiveDeliveryStatus` → dock status/disclosure with fixed catalog values (FR-013) via `NaruRemoteAppSnapshot.liveTransportDisclosureText`/`liveStatusText`; surface degraded-clipboard disclosure (unconfirmed, ~0.3 s settle, clipboard overwritten — D2/FR-014/IN-004) and ASCII-only last-resort disclosure; retain not-yet-delivered text on failure (FR-015). No typed content in diagnostics (SP-005) — Live adds nothing to `DiagnosticExport`, keeping the enum-rawValue-only catalog.
- [x] T013 [P] [US1/US3/US4/US5] Routing tests in `NaruRemote/Tests/NaruRemoteAppTests/LiveTypeThroughRoutingTests.swift`: (a) helper present → per-commit `nativeInsert` only, no VNC clipboard/paste/Unicode `KeyEvent`, marked not sent (US1); (b) no helper + clipboard usable → ASCII+Korean via chunked clipboard, disclosure set (D2/US4); (c) clipboard not confirmed → Korean retained + safe failure, no Unicode `KeyEvent` (US4); (d) ⌫ within window → `BackSpace` key events; Return → `Return` + seal (US3/D1); (e) pointer interaction seals, no cross-seal delete (US5); (f) privacy: diagnostic export carries no typed Live content (SP-005/SC-006); plus 3-mode switch preserves Compose draft (US2). `swift test --filter LiveTypeThroughRoutingTests` — 7 tests green.

**Checkpoint**: `swift build && swift test` green; app-model routing proven against fake helper + FakeRFBServer.

---

## Phase 4: T-ui — dock presentation (view only)

**Goal**: mode picker gains Live; commit hook dispatches; ⌫/↵ reuse; status line + disclosure badge.  
**Owns**: `NaruRemote/App/Features/RemoteInputDock/RemoteInputDockView.swift`.  
**Depends on**: Phase 3.

- [x] T014 [US2] Replace the boolean Compose/Direct `modePicker` with a 3-way segmented picker (Compose / Live / Direct); active mode visibly indicated; one-tap switch drives model mode state via `onSelectMode` → `setRemoteInputDockMode` (FR-001). Kept `naru.input.mode-picker` accessibility id. Also added a `naru.input.live-toggle` for the phone-first compact/floating live-session accessory where the segmented picker does not render.
- [x] T015 [US1/US3] Wired the Live commit hook: reuses `MultilingualComposeTextView` marked-text/commit-boundary detection so each committed unit dispatches to the model via `onLiveCommit` (no Send button, no draft accumulation in Live — FR-002/FR-012). Kept the T015 IME protections: never writes the field during composition; the equatable focus-freeze now excludes Live so its disclosure/status repaint while focused; `shouldDeferUIKitComposeBindingWrite` relaxes only for Live so the model can clear the line on Return/seal.
- [x] T016 [US3] Reuse the existing ⌫/↵ `ComposeQuickKey` action row as always-visible Backspace/Enter buttons on the Live surface (D1, CRD pattern); ⌫ triggers `liveDeleteBackward`, ↵ triggers `liveNewline` (flush+seal+fresh window). Send button hidden in Live.
- [x] T017 [US1/US2/US4] Render the Live status line + persistent transport/latency disclosure badge (peer to Direct's "IME off" badge): helper observed / unconfirmed-clipboard(settle+overwrite) / ASCII-only / retained-failure (FR-013/FR-014). Fixed English strings via `naru.input.live-disclosure` + `naru.input.live-status`.

**Checkpoint**: iPhone-simulator screenshot review of the dock in Live mode (per user's UI-iteration-via-screenshots workflow) matches spec disclosure requirements.

---

## Phase 5: T-tests — app-level + simulator UI

**Owns**: `NaruRemote/UITests/LiveTypeThroughStormUITests.swift`; `project.yml` regeneration.  
**Depends on**: Phase 4.

- [x] T018 [US1/FR-008] Added `NaruRemote/UITests/LiveTypeThroughStormUITests.swift` following the `ComposeInputResponsivenessUITests` storm pattern: enters Live mode, rapid-type Hangul+ASCII storm → asserts ordered local echo with no loss/dup/reorder; plus a disclosure-badge presence test. Regenerated project via `xcodegen generate --spec project.yml` (UITests dir is globbed).
- [x] T019 Ran the iPhone-simulator UI test: `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:NaruRemoteUITests/LiveTypeThroughStormUITests` — 2 tests green. iPhone Live-mode dock screenshot: `artifacts/screenshots/live-type-through/live-mode-dock.png`.
- [x] T020 [P] iPad graceful-scaling: ran the same storm UI test on iPad Pro 13-inch (M5) after the iPhone row (T019) passed (§VI ordering) — Live dock + disclosure render/behave the same.

**Checkpoint**: simulator matrix green; iPhone before iPad.

---

## Phase 6: T-residual — physical device gates (residual risks)

These cannot be verified in the current environment; each is a residual-risk
follow-up per constitution §III, and each blocks any future promotion of Live to
default (D3) — not this opt-in slice.

- [ ] T021 [US1/SC-001/SC-003] Physical iPhone + Mac: 200-char Korean/English/number/symbol mixed, 10 iterations, via `helper-text-observed-probe` (unicode-hangul) — no loss/dup/reorder/mid-composition (PRODUCT_QUALITY_TARGETS.md §6.1). Record redacted log.
- [ ] T022 [SC-002] Physical iPhone + Mac: per-commit latency probe extending `helper-text-observed-probe` (commit → request accepted / observed insert); record p95, confirm few-hundred-ms class, materially < batch ~1–1.3 s budget.
- [ ] T023 [FR-005] Physical regression: `text-keystroke-observed-probe` (unicode-hangul) confirms Unicode `KeyEvent` to macOS remains `no-input`.
- [ ] T024 [SC-007] Physical iPhone: 30-min sustained live-typing session — no accumulated desync/loss/unrecoverable state/sustained serious thermal. Record session log + diagnostic export.
- [x] T025 Record the non-macOS-host residual (Non-Goal): adapter ladder must
  not assume macOS everywhere; `NEXT_STEPS.md` and `ROADMAP.md` now keep
  non-mac tiers behind a later feature spec rather than implying current
  support. **Done 2026-07-12.**

---

## Post-implementation review fixes (2026-07-05)

Adversarial review of the completed implementation surfaced one confirmed and
two plausible defects, fixed same-day with regression tests:

- [x] TR01 (CONFIRMED) FR-015: a failed async insert trusted the optimistic
  `takePending()` fold, silently dropping the typed chunk while the status line
  claimed retention. Fix: pre-fold baseline snapshot + `LiveTypeThroughWindow.rollBackDelivery(toPreDispatchBaseline:)`
  + `retainedTail`; failure rolls the mirror back before sealing/retaining.
  Tests: `testHelperInsertFailureRetainsTypedTextInsteadOfDroppingIt` + Core rollback tests.
- [x] TR02 (PLAUSIBLE) FR-007: a same-batch async insert (helper tier) could
  overtake its BackSpaces across lanes (key lane stalls behind MainActor work).
  Fix: cross-lane order barrier — when a batch carries deletes, the insert
  fires from a no-op key-lane entry after the deletes flush.
  Test: `testSameBatchDeletesFlushBeforeAsyncInsertFires`.
- [x] TR03 (PLAUSIBLE) FR-011×FR-015: a pointer seal racing an in-flight failed
  insert suppressed the failure and lost the folded chunk. Fix: the failure
  path re-retains against the rolled-back mirror even on sealed windows and
  surfaces `retainedFailure`.
  Test: `testPointerSealDuringInFlightFailureStillRetainsAndSurfacesFailure`.
- [x] TR04 (CONFIRMED, 2026-07-12) FR-001: iOS keyboard AutoFill chrome could
  cover the leading compact Direct/Live controls. Move both switches to the
  trailing mission-control edge, expand compact and floating variants to
  44-point targets, and assert both remain hittable with the system keyboard
  visible in `UXAuditScreenshotsUITests`. The assertion is authored; current
  execution is pending because the local simulator AX service stops before the
  test body.

---

## Dependencies & Parallelism

- Phase 1 blocks all. Phase 2 (T-core) blocks Phase 3 (T-model) blocks Phase 4 (T-ui) blocks Phase 5 (T-tests).
- Within Phase 2, T007 runs after T003–T006. Within Phase 3, T013 runs after T008–T012.
- `[P]` tasks (T007, T013, T020) are the test tasks against otherwise-complete implementation in their phase.
- Shared-ownership files (`NaruRemoteAppModel.swift`, `RemoteInputDockView.swift`) are single-owner per phase — do NOT parallelize edits to them.
- NO new `NaruRemoteCore → UIKit` dependency (T-core stays pure). NO macOS helper contract changes (deletes reuse VNC key lane).

## Agent Handoff Notes

Each agent prompt includes: spec path (`specs/009-live-type-through/spec.md`),
US/FR IDs, owned files (above), forbidden files (everything outside the phase's
Owns list + the many unrelated uncommitted working-tree files), exact
`swift test --filter` / `xcodebuild` command, and the requirement that
`swift build && swift test` stay green before finishing.
