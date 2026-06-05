---
description: "Tasks: Host Helper Text Bridge"
---

# Tasks: Host Helper Text Bridge

**Input**: Design documents from `/specs/006-host-helper-text-bridge/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, verification matrix  
**Product**: Naru Remote

## Phase 1: Spec & Research Readiness

- [x] T001 Read `BRANDING.md`, `PRODUCT_SPEC.md`, `.specify/memory/constitution.md`, and `specs/006-host-helper-text-bridge/spec.md`. **Done for spec PR.**
- [x] T002 Confirm all clarification markers are resolved or explicitly deferred. **Done; none remain.**
- [x] T003 [P] Complete risky API/protocol/policy decisions in `specs/006-host-helper-text-bridge/research.md`. **Done for spec PR.**
- [x] T004 [P] Record the required verification matrix in `specs/006-host-helper-text-bridge/plan.md`. **Done for spec PR.**

**Checkpoint**: No implementation coding starts until this phase passes.

---

## Phase 2: Foundation / Test Harness

- [x] T005 [US1] Add `HelperTextBridgeAvailability`, `HelperTextBridgeFailureCode`, and helper request/result value types in `NaruRemote/Sources/NaruRemoteCore/RemoteInputDock/`; verify with `swift test --filter HelperTextBridge`. **Done.**
- [x] T006 [US1] Add a fake helper text client in `NaruRemote/Tests/NaruRemoteCoreTests/` or `NaruRemote/Tests/NaruRemoteAppTests/`; verify routing without a real helper. **Done.**
- [x] T007 [US3] Extend diagnostic export model with helper text bridge state in `NaruRemote/Sources/NaruRemoteCore/Diagnostics/` and tests in `NaruRemote/Tests/NaruRemoteCoreTests/DiagnosticExportTests.swift`. **Done.**
- [ ] T008 [US2] Add profile-level helper enabled/revoked state tests in `NaruRemote/Tests/NaruRemoteAppTests/`.
- [x] T009 Update `specs/006-host-helper-text-bridge/quickstart.md` with exact implementation commands after test names exist. **Done.**

**Checkpoint**: Verification tools exist and fail for missing routing implementation where applicable.

---

## Phase 3: User Story 1 - Send Multilingual Compose Through Helper (Priority: P1)

**Goal**: Korean/CJK/emoji Compose sends through fake helper when VNC UTF-8 is unconfirmed and helper is reachable.

**Independent Test**: `swift test --filter HelperTextBridge` plus app-model test proving no VNC clipboard write.

### Tests First

- [ ] T010 [P] [US1] Add failing text-injection routing tests for UTF-8-required payload + reachable helper in `NaruRemote/Tests/NaruRemoteCoreTests/`.
- [x] T011 [P] [US1] Add failing app-model test for helper route and no VNC clipboard write in `NaruRemote/Tests/NaruRemoteAppTests/NaruRemoteAppModelTests.swift`. **Done.**

### Implementation

- [x] T012 [US1] Extend `TextInjectionPath` and `TextInjectionAttempt` in `NaruRemote/Sources/NaruRemoteCore/RemoteInputDock/TextInjectionAdapter.swift` with helper-native path metadata. **Done.**
- [x] T013 [US1] Add helper-aware Compose routing in `NaruRemote/App/AppShell/NaruRemoteAppModel.swift`. **Done.**
- [x] T014 [US1] Keep confirmed Extended Clipboard UTF-8 as the no-helper preferred path when available. **Done.**
- [x] T015 [US1] Add safe helper success/failure status messages without raw text. **Done.**

**Checkpoint**: US1 works independently with fake helper.

---

## Phase 4: User Story 2 - Permission And Revocation Are Visible (Priority: P2)

**Goal**: Helper permission/revocation state is visible and blocks future helper inserts.

### Tests First

- [ ] T016 [P] [US2] Add failing tests for disabled/revoked helper state in app snapshot/model tests.
- [ ] T017 [P] [US2] Add diagnostic export tests for permission and revocation catalog values.

### Implementation

- [ ] T018 [US2] Add profile/helper state to `NaruRemote/App/AppShell/NaruRemoteAppSnapshot.swift` or profile state as selected by implementation design.
- [ ] T019 [US2] Surface helper availability in session/input UI with concise fixed copy.
- [ ] T020 [US2] Add helper revocation handling that prevents helper requests before transport creation.

**Checkpoint**: Revocation blocks helper insert and diagnostics remain safe.

---

## Phase 5: User Story 3 - Keep Basic VNC And Diagnostics Honest (Priority: P3)

- [ ] T021 [US3] Add tests proving no-helper VNC viewing, Direct mode, PiP, and diagnostics paths do not require helper state.
- [ ] T022 [US3] Add safe failure copy for unconfirmed VNC UTF-8 + helper unavailable in `TextInjectionClipboardPolicy` or successor policy.
- [ ] T023 [US3] Update diagnostics schema docs/contracts if schema version changes.

**Checkpoint**: No-helper baseline remains intact.

---

## Phase 6: macOS Helper Implementation (Future PRs)

- [x] T024 [P] [US1] Add `NaruHelper/` macOS target skeleton with no text insertion yet; verify build/test target. **Done.**
- [x] T025 [US2] Implement helper capability response using fixed permission catalog states. **Done.**
- [x] T026 [US1] Implement first text insertion strategy with privacy-preserving tests. **Done.**
- [x] T027 [US1] Implement pasteboard fallback only with restore attempt and restore-failure reporting. **Done.**
- [ ] T028 [US2] Implement helper revoke/disable from Mac helper side.
- [ ] T029 [US1] Record physical iPhone + Mac manual verification evidence.

---

## Cross-Cutting

- [ ] TXXX Run all checks listed in `quickstart.md`.
- [ ] TXXX Update `research.md` if Apple API or permission findings change.
- [ ] TXXX Security/privacy review for helper pairing, transport, diagnostics, and logs.
- [ ] TXXX Record residual manual-device risks if physical iPhone/Mac verification cannot be completed in the current environment.
