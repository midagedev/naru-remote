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
- [x] T029G [US1] Add a `NaruHelper --video-listen` entrypoint backed by the
  authenticated helper-video TCP server, with explicit token/profile
  fingerprint/port/source configuration, env indirection for sensitive inputs,
  and finite ScreenCaptureKit or synthetic-encoded access-unit sources.
  **Done.**
- [x] T029H [US2] Add an external-helper benchmark probe that launches
  `NaruHelper --video-listen` with env-indirected synthetic pairing state and
  connects through the helper-video network client while keeping reports
  privacy-safe. **Done.**
- [x] T029I [US2] Add an external-helper ScreenCaptureKit benchmark probe that
  launches `NaruHelper --video-listen --video-source screen-capturekit` when
  Screen Recording permission is available and otherwise reports the fixed
  permission-missing issue code. **Done.**
- [x] T029J [US1] Add an explicit
  `NaruHelper --video-request-screen-recording-permission` CLI that requests
  macOS Screen Recording permission only when invoked directly and reports only
  fixed helper-video catalog labels. **Done.**
- [x] T029K [US2] Record env-backed live helper-video readiness evidence that
  separates runnable VNC credentials, passing external synthetic helper-video,
  ScreenCaptureKit permission-missing, and the current constrained-cellular VNC
  receive-path blocker. **Done.**
- [x] T029L [US2] Add helper-video ScreenCaptureKit readiness and fixed setup
  action labels to `VNCLiveBenchmark --environment-preflight` so permission
  blockers are reported before capture benchmarks run. **Done.**
- [x] T029M [US2] Delegate external-helper ScreenCaptureKit permission checks
  to the helper process so helper-video capture benchmarks are not false-blocked
  by the benchmark process's macOS Screen Recording permission state. **Done.**
- [x] T029N [US2] Add fixed helper permission identity labels to
  `NaruHelper --video-capability` and
  `--video-request-screen-recording-permission` so live benchmark setup can
  distinguish a stable helper target from a SwiftPM build artifact without
  exposing executable paths or bundle identifiers. **Done.**
- [x] T029O [US2] Add a development helper app wrapper installer that builds
  `NaruHelper`, installs a stable `NaruHelperDev.app`, optionally sets
  `NARU_HELPER_EXECUTABLE` through `launchctl`, and preserves fixed-label
  helper diagnostics for live ScreenCaptureKit setup. **Done.**
- [x] T029O1 [US2] Prefer a single local Apple Development signing identity
  for `NaruHelperDev.app` installation so Screen Recording permission targets
  remain more stable across local rebuilds, while reporting only fixed signing
  labels. **Done.**
- [x] T029P [US2] Extend `VNCLiveBenchmark --environment-preflight` schema `5`
  to query the selected external helper's `--video-capability` fixed labels
  before ScreenCaptureKit benchmark runs, mapping helper permission identity to
  precise setup actions without exposing helper paths. **Done.**
- [x] T029Q [US2] Bound external helper capability and probe cleanup waits so
  helper hangs become fixed `timedOut` diagnostics instead of blocking
  preflight or smoke-run cleanup. **Done.**
- [x] T029R [US2] Add `VNCLiveBenchmark --helper-video-probe-only` so external
  synthetic and ScreenCaptureKit helper-video probes can run without live VNC
  target credentials while preserving privacy-safe report labels. **Done.**
- [x] T029S [US2] Add a launchctl-backed live benchmark runner script for
  repeated preflight, helper-video probe-only, permission-request, and short
  constrained-cellular comparison runs without printing live credential values.
  **Done.**
- [x] T029T [US2] Refresh launchctl-backed live startup glance scale evidence
  for `0.35` and `0.25`, keeping `0.25` as a benchmark/physical-gate candidate
  until physical iPhone validation passes. **Done.**
- [x] T029U [US2] Add a launchctl-backed `helper-readiness-sweep` runner mode
  that emits one safe JSON object for helper capability, environment preflight,
  external synthetic helper-video, and external ScreenCaptureKit helper-video
  probes; record the current live result showing credentials configured,
  synthetic helper-video passing, and true ScreenCaptureKit capture blocked by
  helper app bundle Screen Recording permission. **Done.**
- [x] T029V [US2] Add a launchctl-backed `screen-recording-setup` runner mode
  that checks helper capability, runs the explicit Screen Recording permission
  request, opens the macOS Screen Recording settings pane, rechecks capability,
  and records only fixed setup/status labels. **Done.**
- [x] T029W [US2] Add an opt-in helper-video app-runner benchmark that measures
  finite H.264 access units through visual transport selection and CoreMedia
  sample-buffer creation while normal test loops skip by default. **Done.**
- [x] T029X [US1] Connect helper-video bootstrap to the app-model VNC connect
  path so an enabled private-network profile starts helper-video after the first
  VNC frame, keeps VNC input/control active, and falls back to VNC on helper
  start failure. **Done.**
- [x] T029Y [US1] Add an opt-in network-backed app bootstrap smoke benchmark
  that proves the app-model first-frame helper-video bootstrap can call a real
  authenticated TCP helper-video server/client path and still keep VNC
  framebuffer/control active. **Done.**
- [x] T029Z [US1] Add a safe physical-device preflight mode to the launchctl
  runner so T030/T031 can distinguish connected iPhone, signing team, Xcode
  account, and provisioning blockers without printing device IDs or raw
  xcodebuild logs. Discovery must filter to physical iPhones rather than any
  physical iOS device. **Done.**
- [x] T029AA [US2] Add a combined
  `remote-desktop-10fps-readiness` runner that emits the fixed VNC 10fps gate
  plus helper capability/preflight, external synthetic H.264, and external
  ScreenCaptureKit helper-video checks in one privacy-safe JSON object. Use it
  to decide when VNC is a fallback-only path and helper-video is the primary
  smoothness candidate. **Done.**
- [x] T029AB [US1] Split the live VNC frame loop from MainActor by running
  session connect, framebuffer requests, decode waits, and pacing sleeps in a
  detached worker while hopping to the app model only for current-session
  checks, framebuffer publication, diagnostics, and stats. This is the first
  physical-iPhone freeze mitigation after real connections made gestures and
  keyboard input stop responding. **Done.**
- [x] T029AC [US1] Keep foreground VNC frames out of the PiP sample-buffer
  conversion path and move profile-preview thumbnail sampling off MainActor;
  PiP sample conversion now runs only while PiP watch is preparing/active/stale.
  **Done.**
- [x] T029AD [US2] Make the helper-video session runner non-MainActor and wrap
  the AVSampleBuffer renderer in an explicit main-actor box so helper start
  networking and result state-machine work do not inherit the app chrome
  executor. **Done.**
- [x] T029AE [US1] Split live framebuffer publication into a dedicated
  viewport-observed frame store so content frames after session activation do
  not invalidate the app shell, compose dock, direct keyboard, or connection
  chrome. Keep snapshot/diagnostic frame state memory-only on the app model and
  verify the second streaming frame publishes through `SessionFrameStore`
  without `NaruRemoteAppModel.objectWillChange`. **Done.**
- [x] T029AF [US1] Route same-size steady VNC frames from `SessionFrameStore`
  to the Metal host through a frame-event side channel, leaving SwiftUI
  presentation refreshes for first frame, dimension changes, and clear only.
  Verify frame events continue while both app-model and frame-store
  `objectWillChange` stay quiet after session activation. **Done.**
- [x] T029AG [US1] Add privacy-safe outbound input responsiveness diagnostics
  for the shared key/pointer queue so live iPhone freezes can be triaged as
  queue delay, wire-operation delay, or timeout without exporting coordinates,
  keysyms, text, endpoints, byte counts, or exact timings. **Done.**
- [x] T029AH [US1] Move shared key/pointer outbound input serialization,
  timeout racing, and queue/write timing measurement into a dedicated
  dispatcher outside MainActor so live VNC frame pressure has less opportunity
  to stall gestures, direct keys, and trackpad pointer commands. Preserve one
  ordered RFB input queue across key and pointer messages. **Done.**
- [x] T030A [US1] Let physical-device preflight infer a single local Apple
  Development team for the captured build check while reporting only a fixed
  `developmentTeamStatus=inferred` label. **Done.**
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
