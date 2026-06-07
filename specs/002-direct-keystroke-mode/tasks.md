---
description: "Tasks: Direct Keystroke Streaming Mode"
---

# Tasks: Direct Keystroke Streaming Mode

**Input**: Design documents from `/specs/002-direct-keystroke-mode/`
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/keystroke-emitter.md`
**Product**: Naru Remote

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because files and dependencies are disjoint.
- **[Story]**: Maps to a user story in `spec.md` (US1–US5).
- Every implementation task names the test or evidence that closes it.

PR grouping suggestion: each `Phase` below is a natural PR boundary. Phase 2 + 3 may be split into two PRs (Foundation, then US-1 implementation).

---

## Phase 1: Spec & Research Readiness

**Purpose**: Confirm the agent has grounded context before writing code.

- [x] T001 Spec, plan, research, data-model, and contracts exist at `specs/002-direct-keystroke-mode/`. (PRs #25, #26 merged.)
- [x] T002 No `[NEEDS CLARIFICATION]` markers remain (auto-repeat resolved as one-shot only in FR-016).
- [x] T003 Risky API decisions locked in `research.md` (R-1 keysym source, R-2 hardware-keyboard capture API, R-3 firstResponder handoff, R-4 Cmd-key semantics).
- [x] T004 Verification matrix recorded in `plan.md` "Verification Matrix" section.

**Checkpoint**: ✅ All four items already complete from prior PRs. Coding can start.

---

## Phase 2: Foundation — RFB Layer Extensions

**Purpose**: Extend the existing RFB capability-protocol pattern so on-screen and hardware paths share a single `RFBKeyEventClient` boundary. No UI yet; pure Core + test fixtures.

**PR boundary suggestion**: one PR — small, low-risk, fully unit-tested.

- [ ] T005 [Phase2] Add `RFBKeyEventClient` capability protocol next to `RFBPointerEventClient` in `NaruRemote/Sources/NaruRemoteCore/VNC/RFBClientBoundary.swift`. Compose into `RFBStreamingClient`. Closes: contract `RFBKeyEventClient` shape; verified by `swift build` of dependents.
- [ ] T006 [Phase2] Adopt `RFBKeyEventClient` on `RFBNetworkClient` in `NaruRemote/Sources/NaruRemoteCore/VNC/RFBNetworkClient.swift` — three-line `sendKeyEvent(keysym:isDown:)` routing through the existing `RFBClientMessageEncoder.keyEvent(keysym:isDown:)`. Mirror the existing `sendPointerEvent(...)` call site. Closes: contract production-adopter clause; verified by integration tests in T009.
- [ ] T007 [P] [Phase2] Extend `TestFixtures/FakeRFBServer/ServerKit/FakeRFBClientMessageRecorder.swift` with `FakeRFBKeyEvent` struct and `keyEvents: [FakeRFBKeyEvent]` accessor — mirror the existing `pointerEvents` pattern. Closes: data-model test-fake clause; verified by T008.
- [ ] T008 [P] [Phase2] Extend `NaruRemote/Tests/NaruRemoteCoreTests/RFBClientMessageEncoderTests.swift` with Direct-mode coverage: `(0x0063, true) → "04 01 00 00 00 00 00 63"`, `(0xFFE3, false) → "04 00 00 00 00 00 FF E3"`, `(0x00000000, true)`, `(0xFFFFFFFF, false)` boundary cases. Closes: contract encoder verification clause.
- [ ] T009 [Phase2] Add `KeyEventWireTests.swift` under `NaruRemote/Tests/NaruRemoteCoreFakeRFBServerTests/` proving `RFBNetworkClient.sendKeyEvent(...)` writes the recorder's `keyEvents` array in correct order through a real fake-RFB socket. Closes: T006 integration; verified by `swift test --filter KeyEventWireTests`.

**Checkpoint**: `swift build` passes; `swift test --filter RFB` passes; recorder captures 8-byte `KeyEvent` frames over a fake socket.

---

## Phase 3: User Story 1 — Drive A Remote Shell From iPhone (Priority: P1)

**Goal**: Tap a letter / Tab / Esc / arrow key on a custom soft keyboard → exactly one `KeyEvent` down + one up at the remote.

**Independent Test**: With `FakeRFBServer` recording, switch the dock to Direct mode, tap `q` `w` `e` `Tab` `Esc` `Up` on the on-screen keyboard, and verify the recorder shows the expected six pairs of `KeyEvent`s with the right keysyms in the right order.

**PR boundary suggestion**: split into two PRs — Core logic (T010–T015) first, then App UI (T016–T020) so the UI lands with screenshot evidence.

### Tests First (Core)

- [ ] T010 [P] [US1] Add `KeysymMappingTests.swift` under `NaruRemote/Tests/NaruRemoteCoreTests/` — assert the locked-value table from `data-model.md` for every `NamedKey.allCases` entry plus printable ASCII boundaries (`0x20`, `0x7E`, a few interior). Test fails until T011.
- [ ] T011 [P] [US1] Add `KeystrokeEmitterTests.swift` under `NaruRemote/Tests/NaruRemoteCoreTests/` — empty-modifier emission produces 2 events; emission order assertion against `FakeRFBClientMessageRecorder.keyEvents`. Test fails until T013.

### Implementation (Core)

- [ ] T012 [P] [US1] Implement `KeysymMapping` in new file `NaruRemote/Sources/NaruRemoteCore/RemoteInputDock/KeysymMapping.swift`. Closed `NamedKey` enum + ASCII range. Closes T010.
- [ ] T013 [US1] Implement `KeystrokeEmitter` in new file `NaruRemote/Sources/NaruRemoteCore/RemoteInputDock/KeystrokeEmitter.swift`. Holds `RFBKeyEventClient` injection (Phase 2 protocol). Empty modifier path only — modifier ordering is Phase 4. Closes T011 for the empty-modifier subset.
- [ ] T014 [P] [US1] Implement `DirectKeystrokeMode` + `KeyboardPage` value types in new file `NaruRemote/Sources/NaruRemoteCore/RemoteInputDock/DirectKeystrokeMode.swift`. Pure value types per `data-model.md`.

### Implementation (App-model)

- [ ] T015 [US1] Wire `directKeystrokeMode` `@Published` state, `toggleDirectKeystrokeMode()`, `setDirectKeystrokePage(_:)`, and `tapDirectKey(.character(_)|.named(_)|.pageToggle)` on `NaruRemoteAppModel` in `NaruRemote/App/AppShell/NaruRemoteAppModel.swift`. State resets on `disconnect()`, on a fresh `connectSelectedProfile()`, and on profile change (FR-014). Test in `NaruRemote/Tests/NaruRemoteAppTests/DirectKeystrokeModeTests.swift` (new). Closes US-1 model integration.

### Implementation (App UI)

- [ ] T016 [P] [US1] Build `DirectKeystrokeKeyboardLayouts.swift` in `NaruRemote/App/Features/RemoteInputDock/` — pure-data static descriptors for QWERTY rows and special-keys rows (key labels, widths, keysym binding via `KeysymMapping`). Pure value types — App tests cover.
- [ ] T017 [US1] Implement `DirectKeystrokeKeyboardView.swift` SwiftUI in `NaruRemote/App/Features/RemoteInputDock/`. Bottom-docked. Page-toggle button (no `KeyEvent` emitted on toggle, FR-002). Each key is a `Button` calling `model.tapDirectKey(...)`. Depends on T015.
- [ ] T018 [US1] Update `RemoteInputDockView.swift` in `NaruRemote/App/Features/RemoteInputDock/` to add a `Picker(.segmented)` mode toggle between Compose and Direct, swap which keyboard view shows based on `model.directKeystrokeMode.isActive`, and dismiss the iOS keyboard via the responder-chain change in T019.
- [ ] T019 [US1] Add a `DirectKeystrokeResponderView` `UIViewRepresentable` (non-`UITextInput`) that becomes first responder when Direct mode activates, so iOS keyboard does not appear (FR-001 / `research.md` R-3). Lives at `NaruRemote/App/Features/RemoteInputDock/DirectKeystrokeResponderView.swift`. App-only (`#if canImport(UIKit)`).
- [ ] T020 [US1] [VISUAL] Boot iPhone 17 Pro / iOS 26.2 simulator, drive to Direct mode, capture screenshots of (1) QWERTY page bottom-docked with iOS keyboard absent, (2) special-keys page. Save under `artifacts/screenshots/direct-keystroke/us1-{qwerty,special}.png`. Open both with `Read` tool and judge against spec — keyboard fills bottom area, no iOS keyboard above it, special-keys page shows Tab/Esc/Ctrl/Alt/Cmd/Shift/arrows/F1–F12/Home/End/PgUp/PgDn/Insert/Delete + page-back toggle + (Phase 7) Clear modifiers slot.

**Checkpoint**: US-1 acceptance scenarios 1–3 pass on iPhone 17 Pro simulator. Recorder shows the expected wire bytes for a typing sequence. Screenshots saved. Independent of Phase 4 — modifier-less typing works.

---

## Phase 4: User Story 2 — Sticky Modifier Combinations (Priority: P1)

**Goal**: Tap `Ctrl` (armed) → tap `c` → wire shows `Ctrl down → c down → c up → Ctrl up`. Double-tap `Shift` (locked) → next 3 letters held.

**Independent Test**: `StickyModifierState` unit tests pass; emission with `Set<Modifier> = [.control]` produces exactly 4 wire events in the documented order.

**PR boundary suggestion**: one PR (Core state machine + emitter modifier path + App-model integration + button visuals).

### Tests First

- [ ] T021 [P] [US2] Add `StickyModifierStateTests.swift` under `NaruRemote/Tests/NaruRemoteCoreTests/` covering: idle→armed; armed→locked within 400 ms; armed→idle (single-tap consume); locked→idle on tap; armed re-tap after 401 ms = fresh single-tap; `clear()` resets all four; `consumeAfterNonModifierEmission()` releases armed slots, leaves locked alone. Driven by an injected `ContinuousClock.Instant` so no real sleeps.
- [ ] T022 [P] [US2] Extend `KeystrokeEmitterTests.swift` (T011) with modifier-set emission cases: order Control → Shift → Alt → Meta on press, reverse on release, total event count = `2*(1+modifiers.count)`. Hex-string assertions per `contracts/keystroke-emitter.md`.

### Implementation

- [ ] T023 [P] [US2] Implement `StickyModifierState` in new file `NaruRemote/Sources/NaruRemoteCore/RemoteInputDock/StickyModifierState.swift`. Per `data-model.md` API surface. Closes T021.
- [ ] T024 [US2] Extend `KeystrokeEmitter` (T013) with the modifier-wrapping path per `contracts/keystroke-emitter.md` emission order. Closes T022.
- [ ] T025 [US2] Wire `stickyModifierState` `@Published` + `lastModifierTapAt` dict on `NaruRemoteAppModel`; extend `tapDirectKey(_:)` to handle `.modifier(_)` and to call `state.consumeAfterNonModifierEmission()` after `.character`/`.named` emissions. Test in `DirectKeystrokeModeTests.swift` (extend T015 file).
- [ ] T026 [US2] Build `ModifierKeyButton.swift` SwiftUI in `NaruRemote/App/Features/RemoteInputDock/` — three visual states (idle / armed / locked) distinct from a regular key. Use system-color tokens so dark / light mode both work.
- [ ] T027 [US2] Wire `ModifierKeyButton` into `DirectKeystrokeKeyboardLayouts.swift` for the four modifier slots on the special-keys page.
- [ ] T028 [US2] [VISUAL] Capture screenshots of each modifier in idle / armed / locked state on iPhone 17 Pro simulator. Save under `artifacts/screenshots/direct-keystroke/us2-modifiers-{idle,armed,locked}.png`. Open with `Read` tool to verify states are visually distinct and accessible (constitution: visible state is the indicator, not text).

**Checkpoint**: US-2 acceptance scenarios 1–5 pass on iPhone simulator. Modifier sequencing on the wire matches `contracts/`.

---

## Phase 5: User Story 3 — Bluetooth / Magic Keyboard (Priority: P2)

**Goal**: With a hardware keyboard attached and Direct mode active, hardware keystrokes produce identical wire bytes to the on-screen path (SC-005).

**Independent Test**: Unit test exercising both paths against the same `(keysym, modifiers)` pair, asserting `recorder.keyEvents` equality byte-for-byte.

**PR boundary suggestion**: one PR.

### Tests First

- [ ] T029 [P] [US3] Add `KeysymMappingUIKitTests.swift` under `NaruRemote/Tests/NaruRemoteAppTests/` (App-side because it references `UIKey.Code`). Covers `keyboardLetterA` → `0x61`, `keyboardEscape` → `0xFF1B`, `keyboardLeftControl` → `0xFFE3`, etc. — sample of named + character keys.
- [ ] T030 [P] [US3] Add `HardwareOnScreenIdentityTests.swift` proving for a fixed input `(keysym, modifiers)` pair, `KeystrokeEmitter.emit(...)` and `KeystrokeEmitter.emitHardware(...)` produce byte-identical recorder arrays (SC-005 lock).

### Implementation

- [ ] T031 [P] [US3] Implement `KeysymMapping+UIKit.swift` extension in `NaruRemote/App/Features/RemoteInputDock/` gated by `#if canImport(UIKit)` per `data-model.md` and `research.md` R-2. Closes T029.
- [ ] T032 [US3] Implement `HardwareKeyboardHandler.swift` in `NaruRemote/App/Features/RemoteInputDock/` — a `UIView` subclass with `canBecomeFirstResponder=true`, `pressesBegan(_:with:)` and `pressesEnded(_:with:)` overriding raw `UIPress` events to extract `keyCode`, `modifierFlags` → `Set<Modifier>`, route to `model.handleHardwareKey(_:isDown:)`. Wrapped as a `UIViewRepresentable` for SwiftUI.
- [ ] T033 [US3] Wire `model.handleHardwareKey(_:isDown:)` on `NaruRemoteAppModel` calling `KeystrokeEmitter.emitHardware(...)` (NOT `.emit(...)`) so sticky state is not consumed by hardware presses. Cross-source coexistence test in `DirectKeystrokeModeTests.swift`.
- [ ] T034 [US3] Mount `HardwareKeyboardHandler` in the session view tree only while `directKeystrokeMode.isActive == true`. When Direct mode toggles off, view tears down and resigns first responder so Compose mode's iOS keyboard returns. Tested via `RemoteInputDockToggleTests.swift` (new).

**Checkpoint**: US-3 acceptance scenarios 1–4 pass. SC-005 byte-identity proven by T030. Hardware path only fires while Direct mode is on (FR-007).

---

## Phase 6: User Story 4 — Mode Switch State Preservation (Priority: P2)

**Goal**: Toggling between Compose and Direct retains a partial Compose draft and clears sticky modifier state.

**Independent Test**: Model-level tests assert draft is preserved across toggle; sticky state clears on toggle out.

**PR boundary suggestion**: small PR (model logic + tests + small badge wiring).

- [ ] T035 [P] [US4] Add tests in `DirectKeystrokeModeTests.swift` for: partial Compose draft survives toggle into Direct; survives toggle back to Compose; sticky-modifier state clears on toggle out (FR-012).
- [ ] T036 [US4] Implement preservation: `toggleDirectKeystrokeMode()` does NOT clear the existing Compose-draft state; toggle out additionally calls `stickyModifierState = .init()` and clears `lastModifierTapAt`. Closes T035.

**Checkpoint**: US-4 acceptance scenarios 1–3 pass.

---

## Phase 7: User Story 5 — Sticky Modifier UX Polish + Persistent Indicators (Priority: P3)

**Goal**: One-time-per-session warning, persistent "Direct mode" badge, "Clear modifiers" affordance.

**PR boundary suggestion**: one PR; mostly App UI.

- [ ] T037 [P] [US5] Add `DirectModeBadge.swift` in `NaruRemote/App/Features/RemoteInputDock/` — small `Label("Direct mode", systemImage: "keyboard")` with system-tint background pinned to the dock header. Visible whenever `model.directKeystrokeMode.isActive`. Closes FR-010.
- [ ] T038 [P] [US5] Add `DirectModeWarningDialog.swift` — `confirmationDialog` rendering on first session activation per `model.directKeystrokeMode.hasShownEntryWarningThisSession`. Confirm action calls `model.dismissDirectModeEntryWarning()` which sets the flag true. Closes FR-009.
- [ ] T039 [US5] Add "Clear modifiers" button on the special-keys page calling `model.tapDirectKey(.clearModifiers)`. Closes FR-013. Wire visual feedback: button briefly flashes when tapped.
- [ ] T040 [P] [US5] Hoist the badge into the session-level HUD so it remains visible when the keyboard is collapsed (FR-010 second sentence). Closes the "badge visible while keyboard is collapsed" XCUITest assertion in T043.
- [ ] T041 [US5] [VISUAL] Capture screenshots of (1) initial warning dialog, (2) badge visible with custom keyboard, (3) badge visible with custom keyboard collapsed showing the session viewport. Save under `artifacts/screenshots/direct-keystroke/us5-{warning,badge-keyboard,badge-hud}.png`. Vision-judge.

**Checkpoint**: US-5 acceptance scenarios 1–2 pass. FR-009 / FR-010 / FR-013 verifiable.

---

## Phase 8: Cross-Cutting Verification & Documentation

**Purpose**: XCUITest, manual physical-device, docs.

**PR boundary suggestion**: one or two PRs depending on how the manual physical-device evidence flows in.

- [ ] T042 [P] [Cross] Add XCUITest `DirectKeystrokeModeUITests.swift` under `NaruRemote/UITests/` — toggle into Direct mode → assert custom keyboard visible, iOS keyboard absent (negative assertion via screenshot diff or accessibility identifier). Closes FR-001 verification.
- [ ] T043 [P] [Cross] XCUITest case: warning shows on first toggle of fresh session, no warning on subsequent toggles. Closes FR-009 verification.
- [ ] T044 [P] [Cross] XCUITest case: badge is visible on session HUD when keyboard is collapsed. Closes FR-010 verification.
- [ ] T045 [Manual] [Cross] iPhone physical-device test: connect to a real Mac VNC, enter Direct mode, complete `vim` open → navigate `h j k l` → save & quit `Esc :wq Return`. Record PASS/FAIL in `artifacts/manual-tests/direct-keystroke-vim.md` with a short screen recording.
- [ ] T046 [Manual] [Cross] iPhone physical-device test: same as T045 but with a Bluetooth Magic Keyboard attached. Cover Tab completion, `Ctrl-R` reverse search, `Ctrl-C` cancel. Record PASS/FAIL in `artifacts/manual-tests/direct-keystroke-hwkb.md`.
- [ ] T047 [P] [Cross] Add `quickstart.md` under `specs/002-direct-keystroke-mode/` — how to run the feature checks: `swift test`, fake-RFB byte-trace command, simulator drive-to-Direct steps for screenshots, manual-test recipe templates.
- [ ] T048 [Cross] Update `ROADMAP.md` Phase 9 keyboard sub-track from "promoted to ship-blocker / pending" to "implemented" once T042–T046 close. Update Ship Readiness P0 list.
- [ ] T049 [Cross] Update `PRODUCT_SPEC.md` §6.3.6 if implementation reality changed any user-visible flow described in the spec (e.g., final modifier-button visual semantics, final special-keys page contents, exact warning-dialog wording).
- [x] T050 [Cross] Physical iPhone input-lane correction: split app-level key dispatch from pointer dispatch so slow buttonless trackpad-move writes cannot head-of-line block Direct keys or Compose quick keys; pointer timeout narrows to the pointer lane. Covered by delayed-trackpad-move and timed-out-pointer regressions in `DirectKeystrokeModeTests`. **Done.**

**Checkpoint**: All XCUITest cases pass on iPhone 17 Pro simulator. Both manual physical-device tests recorded as PASS. ROADMAP and PRODUCT_SPEC reflect shipped behavior.

---

## Dependencies & Parallelism

**Strict order:**

- Phase 1 → Phase 2 → Phase 3 → ... → Phase 8.
- Within Phase 2, T005 must land before T006; T007 and T008 can be parallel; T009 needs T005 + T007.
- Within Phase 3, T010–T014 can run as parallel tasks (disjoint files); T015 depends on T012 + T013 + T014; T016 depends on `KeysymMapping` (T012); T017 depends on T015 + T016; T018 depends on T015; T019 is App-only and can be parallel with T017; T020 (VISUAL) waits for T017 + T018 + T019.
- Phase 4 STate machine (T023) is parallel with Phase 3 Core because the file is disjoint, but T024 depends on T013 + T023, and T025 depends on T015 + T023.
- Phase 5 hardware path (T032) depends on Phase 3 model wiring (T015) and Phase 2 protocol (T005).
- Phase 6 is small and depends only on Phase 3 model wiring.
- Phase 7 polish depends on the model surface from Phase 3 + 4.
- Phase 8 verification waits on the relevant phases' implementation completion.

**Maximum-parallelism worker plan** (assumes one PR per phase, agents work concurrently within a phase):

```text
PR-A: Phase 2 (T005..T009)
PR-B: Phase 3 Core (T010..T015)         depends on PR-A
PR-C: Phase 3 App  (T016..T020)         depends on PR-B
PR-D: Phase 4      (T021..T028)         depends on PR-B (Core); can overlap PR-C
PR-E: Phase 5      (T029..T034)         depends on PR-A + PR-B
PR-F: Phase 6      (T035..T036)         depends on PR-B
PR-G: Phase 7      (T037..T041)         depends on PR-C + PR-D
PR-H: Phase 8 unit (T042..T044, T047)   depends on PR-C + PR-D + PR-E + PR-F + PR-G
PR-I: Phase 8 manual + docs (T045, T046, T048, T049)   depends on PR-H + physical iPhone access
```

PR-D can fork from PR-B (same Core base) and merge alongside PR-C — Phase 3 App and Phase 4 modifier path do not write to overlapping files.

---

## Constitution Cross-Check (per `plan.md` Constitution Check table)

| Principle | Closed by tasks |
| --- | --- |
| Input Is Composed Locally (§I, with named MAY exception) | T012 (KeysymMapping pure logic), T013/T024 (Emitter; no clipboard touched), T015 (Compose default), T037 (badge), T038 (warning) |
| Verification Before Confidence (§III) | Phase 2 unit tests, Phase 3–7 unit + integration + visual tests, Phase 8 XCUITest + physical-device |
| Security Boundaries (§IV) | T013/T024 (no logging in emitter — see contract); T015 model-level no-keystroke-content rule asserted in `DirectKeystrokeModeTests`; T038 warning is the disclosure |
| Phone-First, iPad-Graceful (§VI) | every VISUAL task targets iPhone 17 Pro simulator first; iPad screenshots only follow once iPhone path is recorded; T045/T046 manual tests are iPhone physical |
| Helper Optional (§V) | feature does not introduce a helper dependency — verifiable by `grep` for helper imports in the new files |

---

## Notes for the Agent Loop

- Each PR opens against a clean branch off `main` after the prior PR merges. The `feat/<task-id>-<slug>` naming convention is fine; or `feat/02-direct-keystroke-<phase>` if the loop prefers feature-grouped names.
- After every UI-touching task, the agent MUST follow `feedback_ui_iteration_via_simulator_screenshots` — boot simulator, screenshot, vision-judge, save under `artifacts/screenshots/direct-keystroke/`, before claiming the task complete.
- Manual-test tasks (T045, T046) cannot be auto-completed by the agent; they require physical iPhone access. Mark them `BLOCKED` and surface the residual risk explicitly in the closing PR (constitution §III).
- After PR-I lands, mark Phase 9 keyboard sub-track as implemented in `ROADMAP.md` and `feedback_phase9_keyboard_is_ship_blocker.md` becomes historical (do NOT delete; it's the audit trail of why the work happened).
