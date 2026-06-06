---
description: "Tasks: Host Helper Video Stream"
---

# Tasks: Host Helper Video Stream

**Input**: Design documents from `/specs/007-host-helper-video-stream/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, verification matrix  
**Product**: Naru Remote

## Phase 1: Spec & Research Readiness

- [x] T001 Read `BRANDING.md`, `PRODUCT_SPEC.md`,
  `.specify/memory/constitution.md`, `specs/004-rfb-encodings/research.md`,
  and this feature's `spec.md`. **Done for spec PR.**
- [x] T002 Confirm all `[NEEDS CLARIFICATION]` markers are resolved or
  explicitly deferred. **Done; none remain.**
- [x] T003 [P] Complete risky API/protocol/policy decisions in
  `specs/007-host-helper-video-stream/research.md`. **Done for spec PR.**
- [x] T004 [P] Record the required verification matrix in
  `specs/007-host-helper-video-stream/plan.md`. **Done for spec PR.**
- [x] T005 [P] Add helper-video data model and transport contract under
  `specs/007-host-helper-video-stream/`. **Done for spec PR.**

**Checkpoint**: No implementation coding starts until this phase passes.

---

## Phase 2: Foundation / Test Harness

- [x] T006 [US1] Add `HelperVideoProfileState`,
  `HelperVideoStreamDescriptor`, and `HelperVideoStreamHealth` value types in
  `NaruRemote/Sources/NaruRemoteCore/HelperVideo/`; verify with
  `swift test --filter HelperVideo`. **Done.**
- [ ] T007 [US1] Add fake helper video stream client/server test harness in
  `NaruRemote/Tests/NaruRemoteCoreTests/`; verify start, access-unit, stall,
  and stop messages without a real helper.
- [ ] T008 [US3] Extend diagnostic export model with helper-video state in
  `NaruRemote/Sources/NaruRemoteCore/Diagnostics/`; add privacy tests proving
  no frames, dimensions, endpoints, byte counts, exact timings, tokens, host
  names, Compose text, or clipboard contents are exported.
- [ ] T009 [US2] Add benchmark report fixtures for helper-video schema fields
  in `NaruRemote/Tests/VNCLiveBenchmarkKitTests/`.
- [ ] T010 Update `quickstart.md` with exact test names after implementation
  test classes exist.

**Checkpoint**: Verification tools exist and fail for missing implementation
where applicable.

---

## Phase 3: User Story 1 - Visual Stream With VNC Control (Priority: P1)

**Goal**: Helper video can be selected as the visual source while VNC remains
connected for control/input/fallback.

**Independent Test**: XCTest with fake helper video stream proves helper video
visual state and VNC control state coexist.

### Tests First

- [ ] T011 [P] [US1] Add failing app-model test for selecting helper video on
  a paired reachable profile in `NaruRemote/Tests/NaruRemoteAppTests/`.
- [ ] T012 [P] [US1] Add failing fallback test for helper stream stall
  returning to VNC visual state without clearing Compose draft.

### Implementation

- [ ] T013 [US1] Add `VisualTransportMode` or equivalent app model state in
  `NaruRemote/App/AppShell/`.
- [ ] T014 [US1] Wire fake helper video visual source into the session snapshot
  without changing VNC control/input paths.
- [ ] T015 [US1] Add health-driven fallback from helper video to VNC visual
  source.

**Checkpoint**: US1 works independently with fake helper video.

---

## Phase 4: User Story 2 - Benchmark Gate (Priority: P2)

**Goal**: Helper video can be compared against the VNC low-traffic candidate
without unsafe report fields.

### Tests First

- [ ] T016 [P] [US2] Add failing benchmark CLI/report tests for a fixed
  helper-video visual transport label.
- [ ] T017 [P] [US2] Add privacy fixture tests proving helper-video reports
  omit frames, dimensions, endpoints, byte counts, exact timings, and tokens.

### Implementation

- [ ] T018 [US2] Add benchmark-only helper-video transport shape to
  `NaruRemote/Tools/VNCLiveBenchmark/`.
- [ ] T019 [US2] Add fixed gate issue labels for helper-video startup,
  sustained, decode/render, and fallback health.
- [ ] T020 [US2] Record a benchmark artifact comparing fake-helper output to
  the existing VNC report shape before any live run.

**Checkpoint**: Helper-video benchmark artifacts are privacy-safe.

---

## Phase 5: User Story 3 - Optional, Revocable, Private-Network Only (Priority: P3)

- [ ] T021 [US3] Add tests proving no-helper VNC connect/view/control,
  Compose, Direct mode, PiP, and diagnostics paths do not require helper-video
  state.
- [ ] T022 [US3] Add fixed helper-video enable/disable/revoked states to app
  settings or profile state.
- [ ] T023 [US3] Prevent helper-video attempts for public-host profiles.
- [ ] T024 [US3] Add safe UI/session status copy for helper-video unavailable,
  revoked, permission-missing, and fallback-to-VNC states.

**Checkpoint**: No-helper baseline remains intact.

---

## Phase 6: macOS Helper Prototype

- [ ] T025 [P] [US1] Add ScreenCaptureKit capture capability probe to
  `NaruHelper/Sources/NaruHelper/`; verify permission catalog states with
  `swift test --filter NaruHelperVideo`.
- [ ] T026 [US1] Add VideoToolbox H.264 encoder prototype behind a helper
  feature flag.
- [ ] T027 [US1] Add authenticated helper-video transport messages according
  to `contracts/helper-video-stream.md`.
- [ ] T028 [US1] Add iOS decode/display prototype using platform video APIs.
- [ ] T029 [US2] Run the constrained-cellular helper-video live benchmark using
  environment-sourced live credentials only.
- [ ] T030 [US1] Record physical iPhone + Mac manual verification evidence.

---

## Cross-Cutting

- [ ] TXXX Run all checks listed in `quickstart.md`.
- [ ] TXXX Update `research.md` if Apple API, permission, codec, or helper
  transport findings change.
- [ ] TXXX Security/privacy review for helper video capture, transport,
  diagnostics, benchmark reports, and logs.
- [ ] TXXX Record residual manual-device risks if physical iPhone/Mac
  verification cannot be completed in the current environment.
