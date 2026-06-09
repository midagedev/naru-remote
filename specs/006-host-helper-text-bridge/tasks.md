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
- [x] T008 [US2] Add profile-level helper enabled/revoked state tests in `NaruRemote/Tests/NaruRemoteAppTests/`. **Done.**
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

- [x] T016 [P] [US2] Add failing tests for disabled/revoked helper state in app snapshot/model tests. **Done.**
- [x] T017 [P] [US2] Add diagnostic export tests for permission and revocation catalog values. **Done.**

### Implementation

- [x] T018 [US2] Add profile/helper state to `NaruRemote/App/AppShell/NaruRemoteAppSnapshot.swift` or profile state as selected by implementation design. **Done.**
- [x] T019 [US2] Surface helper availability in session/input UI with concise fixed copy. **Done.**
- [x] T020 [US2] Add helper revocation handling that prevents helper requests before transport creation. **Done.**

**Checkpoint**: Revocation blocks helper insert and diagnostics remain safe.

---

## Phase 5: User Story 3 - Keep Basic VNC And Diagnostics Honest (Priority: P3)

- [ ] T021 [US3] Add tests proving no-helper VNC viewing, Direct mode, PiP, and diagnostics paths do not require helper state.
- [x] T022 [US3] Add safe failure copy for unconfirmed VNC UTF-8 + helper unavailable in `TextInjectionClipboardPolicy` or successor policy. **Done.**
- [x] T023 [US3] Update diagnostics schema docs/contracts if schema version changes; schema v23 now includes pre-send Compose route encoding/path/UTF-8-support/blocker fields using fixed catalogs only. **Done.**

**Checkpoint**: No-helper baseline remains intact.

---

## Phase 6: macOS Helper Implementation (Future PRs)

- [x] T024 [P] [US1] Add `NaruHelper/` macOS target skeleton with no text insertion yet; verify build/test target. **Done.**
- [x] T025 [US2] Implement helper capability response using fixed permission catalog states. **Done.**
- [x] T026 [US1] Implement first text insertion strategy with privacy-preserving tests. **Done.**
- [x] T027 [US1] Implement pasteboard fallback only with restore attempt and restore-failure reporting. **Done.**
- [x] T030 [US1] Add authenticated length-prefixed helper network transport, macOS listen mode, and client/server tests. **Done.**
- [x] T031 [US1] Persist per-profile helper endpoint metadata and keychain-backed pairing secret references, then route Compose through the stored network helper transport from `NaruRemoteAppModel`. Verify with profile JSON, credential-store, load-state, and loopback helper transport tests. **Done.**
- [x] T032 [US2] Probe stored helper capability before advertising readiness or sending raw Compose text, and keep permission/reachability failures in fixed catalog state. **Done.**
- [x] T033 [US3] Remove best-effort legacy VNC clipboard sends for
  UTF-8-required Compose when Extended Clipboard UTF-8 is unconfirmed. Keep the
  draft, report the helper/confirmed-clipboard requirement with fixed safe copy,
  and preserve ASCII/Latin-1 VNC paste as best-effort. **Done.**
- [x] T034A [US1] Make the macOS helper text inserter native-first: try
  focused Accessibility value insertion and bounded Unicode events when
  available, advertise `nativeInsert` only when permission/capability allows
  it, and fall back to pasteboard-restore only when requested. Verify with
  helper unit tests. **Done.**
- [x] T034B [US2] Split the helper capability permission catalog so
  Accessibility value insertion, bounded Unicode event insertion, and
  pasteboard-restore fallback are reported separately while preserving legacy
  capability decoding. Verify with helper protocol/capability tests. **Done.**
- [x] T034C [US2] Preserve the helper's granular capability summary in app
  state, user-visible helper status text, and diagnostic export so fallback-only
  helpers are not shown as direct native insert endpoints. Verify with helper
  state, app snapshot, app model, and diagnostic export tests. **Done.**
- [x] T034D [US2] Gate automatic Compose helper routing on known native insert
  capability so a reachable helper that only advertises pasteboard fallback does
  not receive raw Compose text when automatic requests are `nativeInsert`-only.
  Verify active-helper and stored-helper app-model paths plus user-visible
  permission status text. **Done.**
- [x] T034E [US1] Add a bounded Compose text key-event transcoder foundation
  without enabling it as the default send route. ASCII/Latin-1 use direct
  keysyms, tab/newlines use named keysyms, and non-ASCII committed scalars use
  X11 Unicode keysyms (`0x01000000 | codepoint`) for future live compatibility
  probes. Hangul jamo/remote-IME decomposition remains rejected by default.
  Verify with `TextKeystrokeTranscoderTests`. **Done.**
- [x] T034F [US1] Add a privacy-safe `VNCLiveBenchmark`
  `--text-keystroke-probe-only` mode for live VNC compatibility evidence.
  The probe connects, requests a first frame, and enqueues fixed committed-text
  KeyEvent payloads using the transcoder without enabling the route as the
  app's default Compose send behavior. Reports omit raw text, keysyms, target
  identity, credentials, bytes, dimensions, pixels, raw errors, and exact
  timings. Verify with `BenchmarkTextKeystrokeProbeReportTests` and
  `swift build --product VNCLiveBenchmark`. **Done.**
- [x] T034G [US1] Add a controlled observed text-keystroke probe using
  `VNCLiveStimulusWindow --text-probe` plus
  `VNCLiveBenchmark --text-keystroke-observed-probe-only`. The observed mode
  reports `observed-inserted` only when the local AppKit text target returns a
  fixed-label `matched` result, and current live evidence records `no-input`
  for both ASCII and Hangul payloads after connect/first-frame/send pass.
  Verify with `BenchmarkTextKeystrokeProbeReportTests`,
  `swift build --product VNCLiveBenchmark`, `swift build --product
  VNCLiveStimulusWindow`, and live `text-keystroke-observed-probe` runs.
  **Done.**
- [x] T034H [US1] Add a controlled observed helper nativeInsert probe using
  `VNCLiveStimulusWindow --text-probe` plus
  `scripts/run-naru-live-benchmark.sh helper-text-observed-probe`. The helper
  probe keeps `nativeInsert` as the only strategy preference, reports helper
  capability/insert status separately from the controlled target observation,
  and emits fixed labels only. Current local evidence reaches target readiness
  but reports `helper.permissionMissing` and `no-input` for `.build/debug/NaruHelper`
  until macOS text insertion permissions are granted. Verify with
  `helper-text-observed-probe-self-test`, `bash -n`, product builds, and the
  live helper observed probe. **Done.**
- [x] T034I [US2] Add a helper text dev-app setup gate that installs the stable
  `NaruHelperDev.app` wrapper, sets `NARU_HELPER_EXECUTABLE`, requests text
  insertion permission, and reports the app-bundle permission identity before
  rerunning observed nativeInsert probes. Current local evidence reports
  `installStatus=passed`, `helperProcessKind=appBundle`, `grantHint=grantAppBundle`,
  `requestResult=notGranted`, and `finalAvailability=permissionMissing`, so the
  next manual action is granting Accessibility or event-posting permission to
  the helper app bundle. Verify with installer/script syntax checks and live
  `helper-text-dev-app-setup` plus `helper-text-observed-probe`. **Done.**
- [x] T034J [US2] Add a combined helper text live gate that runs dev-app setup,
  permission watch, and controlled observed nativeInsert in one privacy-safe
  report. The summary reports `blockedByHelperTextPermission` until native
  insert permission is granted, then `readyForPhysicalComposeGate` only after
  the observed target reports `matched`. Verify with
  `helper-text-live-gate-summary-self-test`, `bash -n`, and live
  `helper-text-live-gate` with bounded polling. **Done.**
- [x] T034K [US2] Surface granular helper text route permission states in
  `helper-text-live-gate` summary. The summary now carries
  `permissionRouteStates`, `missingPermissionRouteLabels`, and
  `nativeInsertReady`, so compact diagnostics show whether AX value insertion,
  Unicode event posting, paste command fallback, or all three are missing.
  Current live evidence reports all three route states missing for
  `NaruHelperDev.app`, with the helper app bundle as the permission target.
  **Done.**
- [ ] T028 [US2] Implement helper revoke/disable from Mac helper side.
- [ ] T034 [US1] Implement and physically verify the Mac helper `nativeInsert`
  strategy without relying on VNC `ClientCutText`, using Accessibility direct
  value insertion where supported and a bounded Unicode event/pasteboard-restore
  fallback chain where direct insertion is unavailable.
- [ ] T029 [US1] Record physical iPhone + Mac manual verification evidence.

---

## Cross-Cutting

- [ ] TXXX Run all checks listed in `quickstart.md`.
- [ ] TXXX Update `research.md` if Apple API or permission findings change.
- [ ] TXXX Security/privacy review for helper pairing, transport, diagnostics, and logs.
- [ ] TXXX Record residual manual-device risks if physical iPhone/Mac verification cannot be completed in the current environment.
