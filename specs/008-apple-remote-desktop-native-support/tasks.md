---
description: "Tasks for Apple Remote Desktop native support strategy"
---

# Tasks: Apple Remote Desktop Native Support Strategy

**Input**: Design documents from `/specs/008-apple-remote-desktop-native-support/`
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, and verification matrix
**Product**: Naru Remote

## Phase 1: Spec & Research Readiness

**Purpose**: Ensure the ARD support boundary is explicit before writing code.

- [x] T001 Read `BRANDING.md`, `PRODUCT_SPEC.md`,
  `.specify/memory/constitution.md`, and this feature's `spec.md`.
- [x] T002 Confirm all `[NEEDS CLARIFICATION]` markers are resolved or
  explicitly deferred.
- [x] T003 [P] Complete Apple Remote Desktop protocol, privilege, port, and
  High Performance screen sharing decisions in
  `specs/008-apple-remote-desktop-native-support/research.md`.
- [x] T004 [P] Record the required verification matrix in
  `specs/008-apple-remote-desktop-native-support/plan.md`.

**Checkpoint**: No coding starts until this phase passes.

---

## Phase 2: Foundation / Test Harness

**Purpose**: Build the smallest catalog infrastructure needed to verify
Apple-aware behavior without touching live remote hosts.

- [x] T005 Create `NaruRemote/Sources/NaruRemoteCore/AppleRemoteDesktop/` for
  support-tier catalog models. Evidence:
  `swift test --filter AppleRemoteDesktopSupportCatalogTests`. **Done.**
- [x] T006 [P] Add `AppleRemoteDesktopSupportCatalogTests` in
  `NaruRemote/Tests/NaruRemoteCoreTests/` covering VNC-compatible, helper-backed,
  research-only, and unsupported tiers. **Done.**
- [x] T007 [P] Add diagnostic redaction fixtures in
  `NaruRemote/Tests/NaruRemoteCoreTests/` ensuring catalog reports never expose
  hostnames, endpoints, credentials, message text, command text, filenames,
  usernames, screenshots, pixels, or exact timing series. **Done.**
- [x] T008 Add documentation for running the feature checks in
  `specs/008-apple-remote-desktop-native-support/quickstart.md`. **Done.**

**Checkpoint**: Catalog tests exist and fail for missing implementation.

---

## Phase 3: User Story 1 - Apple-Aware Mac Profile Guidance (Priority: P1)

**Goal**: Apple Screen Sharing profiles guide users through the public
VNC-compatible path and do not imply full ARD administrator privileges.

**Independent Test**: `swift test --filter AppleRemoteDesktopSupportCatalogTests`

### Tests First

- [x] T009 [P] [US1] Add failing tests for default TCP `5900`, additional
  display ports `5901`/`5902`, and full-ARD-admin-unavailable labels in
  `NaruRemote/Tests/NaruRemoteCoreTests/AppleRemoteDesktopSupportCatalogTests.swift`.
  **Done.**

### Implementation

- [x] T010 [US1] Implement `AppleRemoteDesktopSupportTier`,
  `AppleScreenSharingProfileHints`, and fixed setup labels in
  `NaruRemote/Sources/NaruRemoteCore/AppleRemoteDesktop/AppleRemoteDesktopSupportCatalog.swift`.
  **Done.**
- [ ] T011 [US1] Integrate the catalog with existing profile diagnostics in
  `NaruRemote/Sources/NaruRemoteCore/Diagnostics/` without changing raw VNC
  connection behavior.
- [ ] T012 [US1] Add profile UI copy hooks in `NaruRemote/App/AppShell/` only
  after the catalog tests pass.

**Checkpoint**: US1 works independently and evidence is recorded.

---

## Phase 4: User Story 2 - Helper-Backed ARD-Class Actions (Priority: P2)

**Goal**: Naru can present ARD-class actions only when a paired helper advertises
safe capabilities and the approval policy allows them.

**Independent Test**: `swift test --filter AppleRemoteDesktopSupportCatalogTests`

### Tests First

- [x] T013 [P] [US2] Add failing tests for helper-backed capability visibility
  and approval-gated destructive actions in
  `NaruRemote/Tests/NaruRemoteCoreTests/AppleRemoteDesktopSupportCatalogTests.swift`.
  **Done.**

### Implementation

- [x] T014 [US2] Implement `ARDClassHelperCapability` and
  `ARDClassActionRequest` in
  `NaruRemote/Sources/NaruRemoteCore/AppleRemoteDesktop/`. **Done.**
- [x] T015 [US2] Map helper capability labels into action availability without
  adding actual shell command, file transfer, lock, or power execution.
  **Done.**
- [ ] T016 [US2] Update helper action docs and residual-risk notes in
  `specs/008-apple-remote-desktop-native-support/research.md`.

**Checkpoint**: US1 and US2 both pass independently.

---

## Phase 5: User Story 3 - High Performance Screen Sharing Boundary (Priority: P3)

**Goal**: Naru accurately explains High Performance screen sharing and routes
smooth visual transport to helper video until direct support is legitimate.

**Independent Test**: `swift test --filter AppleRemoteDesktopSupportCatalogTests`

### Tests First

- [x] T017 [P] [US3] Add failing tests that classify High Performance screen
  sharing as `researchOnly`, list fixed blockers, and recommend helper video in
  `NaruRemote/Tests/NaruRemoteCoreTests/AppleRemoteDesktopSupportCatalogTests.swift`.
  **Done.**

### Implementation

- [x] T018 [US3] Add High Performance screen sharing catalog entries in
  `NaruRemote/Sources/NaruRemoteCore/AppleRemoteDesktop/AppleRemoteDesktopSupportCatalog.swift`.
  **Done.**
- [ ] T019 [US3] Integrate fixed explanation labels with visual transport
  selection docs in `NaruRemote/App/AppShell/` after UI design review.
- [ ] T020 [US3] Record benchmark boundary evidence in
  `artifacts/benchmarks/` if implementation changes any visual transport
  selection behavior.

**Checkpoint**: High Performance screen sharing is not exposed as a broken mode.

---

## Phase 6: User Story 4 - Mac-Native Session Controls (Priority: P2)

**Goal**: Active Mac sessions expose compact Mission Control, app/window,
desktop, and Spaces buttons backed by documented keyboard shortcuts.

**Independent Test**:
`swift test --filter 'MacSessionControlTests|MacSessionControlModelTests|RemoteInputDockRenderStateTests'`

### Tests First

- [x] T021 [P] [US4] Add `MacSessionControlTests` covering fixed keysym and
  modifier mappings in `NaruRemote/Tests/NaruRemoteCoreTests/`. **Done.**
- [x] T022 [P] [US4] Add app model and render-state tests covering session
  gating and Compose draft preservation in
  `NaruRemote/Tests/NaruRemoteAppTests/`. **Done.**

### Implementation

- [x] T023 [US4] Implement `MacSessionControl` in
  `NaruRemote/Sources/NaruRemoteCore/AppleRemoteDesktop/` as VNC-compatible
  shortcut emissions. **Done.**
- [x] T024 [US4] Add `NaruRemoteAppModel.sendMacSessionControl(_:)` using the
  existing key-event dispatcher without touching Compose or Direct sticky
  state. **Done.**
- [x] T025 [US4] Render an active-session Mac control strip in
  `NaruRemote/App/Features/RemoteInputDock/RemoteInputDockView.swift` and wire
  it through `NaruRemote/App/AppShell/NaruRemoteAppShell.swift`. **Done.**

**Checkpoint**: US4 works without helper pairing and preserves existing input
paths.

---

## Phase N: Polish & Cross-Cutting

- [ ] TXXX Run all checks listed in `quickstart.md`.
- [ ] TXXX Update `spec.md` if implementation reality changes behavior.
- [ ] TXXX Update `research.md` if Apple docs, protocol findings, or helper
  policy findings change.
- [ ] TXXX Security/privacy review for catalog diagnostics, helper capability
  reports, and action timeline logging.
- [ ] TXXX Accessibility and localization review for visible UI text.
- [ ] TXXX iPhone path verification first; iPad profile editor screenshot only
  after the iPhone row is recorded.
- [ ] TXXX Record residual manual-device risks if physical iPhone/Mac
  verification is unavailable.

## Dependencies & Parallelism

- Phase 1 blocks every other phase.
- Phase 2 blocks all implementation tasks.
- US1 catalog work blocks profile UI copy.
- US2 helper-backed actions must not implement actual shell/file/power
  execution until separate approval and helper permission specs exist.
- US3 HPS explanation must not modify helper-video defaults without benchmark
  evidence.

## Agent Handoff Notes

Each agent task prompt should include:

- Spec path: `specs/008-apple-remote-desktop-native-support`
- User story and requirement IDs
- Owned files
- Forbidden files
- Exact verification command or manual evidence
- Expected final summary format
