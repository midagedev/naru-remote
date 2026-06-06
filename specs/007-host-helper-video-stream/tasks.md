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
- [x] T007 [US1] Add fake helper video stream client/server test harness in
  `NaruRemote/Tests/NaruRemoteCoreTests/`; verify start, access-unit, stall,
  and stop messages without a real helper. **Done.**
- [x] T008 [US3] Extend diagnostic export model with helper-video state in
  `NaruRemote/Sources/NaruRemoteCore/Diagnostics/`; add privacy tests proving
  no frames, dimensions, endpoints, byte counts, exact timings, tokens, host
  names, Compose text, or clipboard contents are exported. **Done.**
- [x] T009 [US2] Add benchmark report fixtures for helper-video schema fields
  in `NaruRemote/Tests/VNCLiveBenchmarkKitTests/`. **Done.**
- [x] T010 Update `quickstart.md` with exact test names after implementation
  test classes exist. **Done.**

**Checkpoint**: Verification tools exist and fail for missing implementation
where applicable.

---

## Phase 3: User Story 1 - Visual Stream With VNC Control (Priority: P1)

**Goal**: Helper video can be selected as the visual source while VNC remains
connected for control/input/fallback.

**Independent Test**: XCTest with fake helper video stream proves helper video
visual state and VNC control state coexist.

### Tests First

- [x] T011 [P] [US1] Add failing app-model test for selecting helper video on
  a paired reachable profile in `NaruRemote/Tests/NaruRemoteAppTests/`.
  **Done.**
- [x] T012 [P] [US1] Add failing fallback test for helper stream stall
  returning to VNC visual state without clearing Compose draft. **Done.**

### Implementation

- [x] T013 [US1] Add `VisualTransportMode` or equivalent app model state in
  `NaruRemote/App/AppShell/`. **Done.**
- [x] T014 [US1] Wire fake helper video visual source into the session snapshot
  without changing VNC control/input paths. **Done.**
- [x] T015 [US1] Add health-driven fallback from helper video to VNC visual
  source. **Done.**

**Checkpoint**: US1 works independently with fake helper video.

---

## Phase 4: User Story 2 - Benchmark Gate (Priority: P2)

**Goal**: Helper video can be compared against the VNC low-traffic candidate
without unsafe report fields.

### Tests First

- [x] T016 [P] [US2] Add failing benchmark CLI/report tests for a fixed
  helper-video visual transport label. **Done.**
- [x] T017 [P] [US2] Add privacy fixture tests proving helper-video reports
  omit frames, dimensions, endpoints, byte counts, exact timings, and tokens.
  **Done.**

### Implementation

- [x] T018 [US2] Add benchmark-only helper-video transport shape to
  `NaruRemote/Tools/VNCLiveBenchmark/`. **Done.**
- [x] T019 [US2] Add fixed gate issue labels for helper-video startup,
  sustained, decode/render, and fallback health. **Done.**
- [x] T020 [US2] Record a benchmark artifact comparing fake-helper output to
  the existing VNC report shape before any live run. **Done.**

**Checkpoint**: Helper-video benchmark artifacts are privacy-safe.

---

## Phase 5: User Story 3 - Optional, Revocable, Private-Network Only (Priority: P3)

- [x] T021 [US3] Add tests proving no-helper VNC connect/view/control,
  Compose, Direct mode, PiP, and diagnostics paths do not require helper-video
  state. **Done.**
- [x] T022 [US3] Add fixed helper-video enable/disable/revoked states to app
  settings or profile state, including profile-store persistence across reload.
  **Done.**
- [x] T023 [US3] Prevent helper-video attempts for public-host profiles.
  **Done.**
- [x] T024 [US3] Add safe UI/session status copy for helper-video unavailable,
  revoked, permission-missing, and fallback-to-VNC states. **Done.**

**Checkpoint**: No-helper baseline remains intact.

---

## Phase 6: macOS Helper Prototype

- [x] T025 [P] [US1] Add ScreenCaptureKit capture capability probe to
  `NaruHelper/Sources/NaruHelper/`; verify permission catalog states with
  `swift test --filter NaruHelperVideo`. **Done.**
- [x] T026 [US1] Add VideoToolbox H.264 encoder prototype behind a helper
  feature flag. **Done.**
- [x] T027 [US1] Add authenticated helper-video transport messages according
  to `contracts/helper-video-stream.md`. **Done.**
- [x] T028 [US1] Add iOS decode/display prototype using platform video APIs.
  **Done.**
- [x] T029 [US2] Record the current constrained-cellular visual-transport
  comparison using environment-sourced live credentials only. **Evidence
  recorded; helper video still reports as benchmark-only disabled.**
- [x] T029A [US1] Add authenticated helper-video access-unit frame pipeline
  that emits `startStream`, `videoAccessUnit`, and safe `streamStalled`
  frames, with an iOS decode-path integration test. **Done.**
- [x] T029B [US1] Add prototype TCP helper-video stream server/client harness
  for authenticated start response, access-unit, and safe stall frames. **Done.**
- [x] T029C [US2] Add a benchmark CLI helper-video probe mode that exercises
  the synthetic TCP harness and reports safe aggregate helper-video state.
  **Done.**
- [x] T029D [US1] Add a VideoToolbox-backed synthetic H.264 access-unit source
  and verify it through helper TCP framing and the iOS sample-buffer path.
  **Done.**
- [x] T029E [US1] Add a finite ScreenCaptureKit pixel-buffer access-unit source
  and expose it through an explicit benchmark TCP probe mode. **Done.**
- [x] T029F [US1] Add an app-side helper-video stream session runner that
  applies finite network start results to the iOS access-unit renderer, helper
  visual transport state, and VNC fallback health without exporting endpoints,
  payloads, byte counts, or raw errors. **Done.**
- [ ] T030 [US1] Record physical iPhone + Mac manual verification evidence.
- [ ] T031 [US2] Run a true live helper-video access-unit benchmark after the
  helper sender/listener is connected to the iOS decode path.

---

## Cross-Cutting

- [ ] TXXX Run all checks listed in `quickstart.md`.
- [ ] TXXX Update `research.md` if Apple API, permission, codec, or helper
  transport findings change.
- [ ] TXXX Security/privacy review for helper video capture, transport,
  diagnostics, benchmark reports, and logs.
- [ ] TXXX Record residual manual-device risks if physical iPhone/Mac
  verification cannot be completed in the current environment.
