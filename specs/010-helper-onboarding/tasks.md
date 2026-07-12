# Tasks: Naru Helper Guided Onboarding

**Feature**: `010-helper-onboarding` | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)
**Status**: Implemented (founder-directed 2026-07-05; fast track). Residual: T014 and the named single-profile probe gap.

Task IDs map to spec FR/US and declare file ownership. Write set is disjoint
from the parallel `009` work: this feature owns `specs/010-helper-onboarding/**`,
`NaruRemote/App/Features/ConnectionHub/**`, one new `NaruRemoteAppModel`
extension file, one new `NaruRemoteCore/ConnectionHub` file, and new test files.
FORBIDDEN: `NaruRemoteAppModel.swift`, `NaruRemoteAppShell.swift`,
`RemoteInputDockView.swift`, `Sources/NaruRemoteCore/RemoteInputDock/**`,
`scripts/`.

## User Story 1 — Guided pairing (P1)

- [x] **T001** [Core] `Sources/NaruRemoteCore/ConnectionHub/HelperOnboarding.swift` (NEW): `HelperOnboardingStep`, `HelperOnboardingCapabilities`, `HelperPairingSecret.generate()` (CSPRNG base64url ≥256-bit), `HelperPairingSecret.fingerprint(for:)` (`sha256:`+hex), `HelperOnboardingSnippet.build(...)`, `HelperOnboardingState`, `HelperOnboardingVerification`. Satisfies FR-004/FR-005/FR-006/FR-007/FR-015. Tests: T010.
- [x] **T002** [App/view] `App/Features/ConnectionHub/HelperOnboardingView.swift` (NEW): step sheet (intro/configure/permissions/verify/done); **Copy secret** + **Copy commands** distinct actions; transient secret in `@State`. Satisfies FR-002/FR-003/FR-008. Tests: screenshots T012.
- [x] **T003** [App/edit] `App/Features/ConnectionHub/ProfileEditorView.swift` (EDIT): **Set up Naru Helper** entry for private hosts (FR-001); present the sheet; on finish stage secret into `helperPairingSecret`/`helperVideoPairingSecret` `@State` + enable toggle(s) (FR-012); add optional `onTestHelper` closure (default nil). Tests: T011.

## User Story 2 — Permissions explained (P1)

- [x] **T004** [App/view] Permissions step in `HelperOnboardingView`: Accessibility (text) + Screen Recording (video), plain language, macOS-prompts-on-Mac note, independent-degradation copy. Satisfies FR-009. Tests: screenshot T012.

## User Story 3 — Verify reachability (P2)

- [x] **T005** [App/view] Verify step wired to the editor's existing `onTest` reachability runner; fixed-catalog status only; honest "host reachable ≠ helper live" disclosure. Satisfies FR-010/FR-011. Tests: T011.
- [x] **T006** [App/model-ext] `App/AppShell/NaruRemoteAppModel+HelperOnboarding.swift` (NEW): `testHelperTextBridge(for:) async -> HelperTextBridgeProfileState` on public surface (`refreshProfileReachability()` + bounded poll of `helperTextBridgeState`). Ready-to-wire helper-handshake test (FR-013). Report the shell-wiring gap (Named API Gap in plan.md).

## User Story 4 — Teardown / revocation (P3)

- [x] **T007** [App/view+edit] Teardown pointer: how to disable (toggle off + Save) vs revoke (clear secret), and what stops working. Reuse existing `disableHelperTextBridge`/`revokeHelperTextBridge`. Satisfies FR-014. Tests: screenshot / checklist.

## Cross-cutting / verification

- [x] **T010** [Core tests] `Tests/NaruRemoteCoreTests/HelperOnboardingTests.swift` (NEW): secret entropy/format/distinctness; fingerprint determinism + parity with editor algorithm; snippet contains install script + both permission flags + `--listen`/`--video-listen` + ports 5974/5975 and NO secret + env-var reference; step ordering; `HelperOnboardingState` encodes without a secret (SP-002/SC-004).
- [x] **T011** [App tests] `Tests/NaruRemoteAppTests/HelperOnboardingStagingTests.swift` (NEW): finishing the flow stages the secret so a subsequent editor Save emits `ProfileEditorCredentialUpdate.helperPairingSecret` and the profile carries the fingerprint (not the secret); verify step maps reachability outcomes to fixed catalog.
- [x] **T012** [Screenshots] iPhone 17 Pro simulator screenshots of each step (`xcrun simctl io screenshot`); iPad graceful-scaling screenshot after iPhone passes.
- [x] **T013** [Build gates] `swift build`; `swift test`; `xcodegen generate --spec project.yml`; `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`.
- [ ] **T014** [Residual, manual] Real-Mac end-to-end pairing (run snippet, grant Accessibility + Screen Recording, helper `reachable`, Korean insert observed via spec 006 probe). Physical iPhone + Mac. Tracked as residual per constitution §III.

## Residual risks

- In-flow helper-handshake auto-test is blocked on 2 lines of shell wiring (Named API Gap, plan.md) — v1 verify covers host reachability only.
- ~~Text `--listen` secret reaches argv~~ — resolved 2026-07-05: `--listen` requires `--token-env` (direct `--token` rejected) and the silent listener-exit bug (`RunLoop.main.run()` with no sources) is fixed; snippet/tests/spec-006 quickstart updated.
- Real-Mac pairing (T014) not runnable in this environment; simulator + unit evidence is necessary but not sufficient per §III/§VI.
