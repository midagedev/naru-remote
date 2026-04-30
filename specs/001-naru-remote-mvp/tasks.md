# Tasks: Naru Remote MVP

**Input**: `specs/001-naru-remote-mvp/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/`  
**Product**: Naru Remote

## Phase 1: Spec & Research Readiness

- [x] T001 Read `BRANDING.md`, `PRODUCT_SPEC.md`, `.specify/memory/constitution.md`, and `specs/001-naru-remote-mvp/spec.md`
- [x] T002 Resolve all `[NEEDS CLARIFICATION]` markers in `specs/001-naru-remote-mvp/spec.md`
- [x] T003 [P] Record MVP decisions in `specs/001-naru-remote-mvp/research.md`
- [x] T004 [P] Record verification matrix in `specs/001-naru-remote-mvp/plan.md`

## Phase 2: Project Foundation

- [x] T005 Create initial Swift package layout under `NaruRemote/Sources/NaruRemoteCore/` and `Package.swift`
- [x] T006 Add SwiftUI package app shell target under `NaruRemote/App/`
- [x] T007 [P] Add XCTest target under `NaruRemote/Tests/NaruRemoteCoreTests/`
- [x] T008 [P] Add fake RFB fixture scaffold under `TestFixtures/FakeRFBServer/`
- [x] T009 Update root `AGENTS.md` with actual build/test commands
- [x] T010 Update `specs/001-naru-remote-mvp/quickstart.md` with executable commands

## Phase 3: User Story 1 - Connect To A Private VNC Host (P1)

**Goal**: Create saved private VNC profiles and staged connection diagnostics.

**Independent Test**: Profile persistence tests and fixture diagnostics prove
DNS/TCP/RFB stage output.

- [x] T011 [P] [US1] Add profile persistence tests in `NaruRemote/Tests/NaruRemoteCoreTests/ConnectionProfileStoreTests.swift`
- [x] T012 [US1] Implement `ConnectionProfile` and `ConnectionProfileStore` in `NaruRemote/Sources/NaruRemoteCore/ConnectionHub/`
- [x] T013 [P] [US1] Add diagnostics stage tests in `NaruRemote/Tests/NaruRemoteCoreTests/ConnectionDiagnosticsTests.swift`
- [x] T014 [US1] Implement `ConnectionDiagnostics` stage model in `NaruRemote/Sources/NaruRemoteCore/Diagnostics/`
- [x] T015 [US1] Add initial profile UI shell in `NaruRemote/App/Features/ConnectionHub/`
- [x] T016 [US1] Verify diagnostic export excludes credentials in `NaruRemote/Tests/NaruRemoteCoreTests/DiagnosticExportTests.swift`

## Phase 4: User Story 2 - View A Remote Session Safely (P1)

**Goal**: Open a basic VNC session view and render/track first-frame state.

**Independent Test**: Fake RFB fixture produces known handshake/frame behavior.

- [x] T017 [P] [US2] Add fake RFB handshake transcript fixture in `TestFixtures/FakeRFBServer/Fixtures/`
- [x] T018 [P] [US2] Add RFB first-frame protocol decoder test in `NaruRemote/Tests/NaruRemoteCoreTests/RFBProtocolDecoderTests.swift`
- [x] T019 [US2] Implement minimal `RFBClient` boundary in `NaruRemote/Sources/NaruRemoteCore/VNC/`
- [x] T020 [US2] Implement `RemoteSession` state model in `NaruRemote/Sources/NaruRemoteCore/SessionViewer/`
- [x] T021 [US2] Add session viewport shell and HUD in `NaruRemote/App/Features/SessionViewer/`
- [x] T022 [US2] Add reconnect/error state tests in `NaruRemote/Tests/NaruRemoteCoreTests/RemoteSessionTests.swift`

## Phase 5: User Story 3 - Compose And Send Multilingual Text (P1)

**Goal**: Compose final text locally and send it through VNC clipboard paste mode.

**Independent Test**: Unicode draft is preserved locally; fake RFB fixture sees
the expected UTF-8 clipboard payload and paste command path.

- [x] T023 [P] [US3] Add Unicode draft tests in `NaruRemote/Tests/NaruRemoteCoreTests/ComposeDraftTests.swift`
- [x] T024 [US3] Implement `ComposeDraft` in `NaruRemote/Sources/NaruRemoteCore/RemoteInputDock/`
- [x] T025 [P] [US3] Add text injection adapter tests in `NaruRemote/Tests/NaruRemoteCoreTests/TextInjectionAdapterTests.swift`
- [x] T026 [US3] Implement `TextInjectionAdapter` MVP path in `NaruRemote/Sources/NaruRemoteCore/RemoteInputDock/`
- [x] T027 [US3] Add Remote Input Dock UI shell in `NaruRemote/App/Features/RemoteInputDock/`
- [x] T028 [US3] Add failed-send retention test in `NaruRemote/Tests/NaruRemoteCoreTests/ComposeDraftTests.swift`
- [ ] T029 [US3] Record manual iPad IME checklist result in `specs/001-naru-remote-mvp/quickstart.md`

## Phase 6: User Story 4 - Understand Failures (P2)

**Goal**: User-facing diagnostics explain where connection or paste failed.

**Independent Test**: Fixture failures map to distinct user-safe messages.

- [x] T030 [P] [US4] Add user-safe diagnostic message tests in `NaruRemote/Tests/NaruRemoteCoreTests/ConnectionDiagnosticsTests.swift`
- [x] T031 [US4] Implement diagnostic message mapping in `NaruRemote/Sources/NaruRemoteCore/Diagnostics/`
- [x] T032 [US4] Add diagnostic summary UI shell in `NaruRemote/App/Features/Diagnostics/`
- [x] T033 [US4] Verify diagnostic export privacy in `NaruRemote/Tests/NaruRemoteCoreTests/DiagnosticExportTests.swift`

## Phase 7: Polish & Gates

- [x] T034 Run all currently executable checks from `specs/001-naru-remote-mvp/quickstart.md`
- [x] T035 Update `specs/001-naru-remote-mvp/research.md` with final VNC/RFB implementation choice
- [x] T036 Update `specs/001-naru-remote-mvp/spec.md` after unknown paste-confirmation behavior changed user-visible status
- [x] T037 Review user-facing text against `BRANDING.md`
- [x] T038 Record residual compatibility risks for macOS/Linux/Windows VNC servers

## Phase 8: Review Remediation Sync

- [x] T039 [US4] Make `DiagnosticExport` omit stage details by default in `NaruRemote/Sources/NaruRemoteCore/Diagnostics/DiagnosticExport.swift`
- [x] T040 [US4] Add default export privacy and explicit-detail redaction tests in `NaruRemote/Tests/NaruRemoteCoreTests/DiagnosticExportTests.swift`
- [x] T041 [US3] Report VNC clipboard paste as `unknown` when remote app acceptance cannot be confirmed in `NaruRemote/Sources/NaruRemoteCore/RemoteInputDock/`
- [x] T042 [US3] Add unknown-state text injection tests in `NaruRemote/Tests/NaruRemoteCoreTests/TextInjectionAdapterTests.swift`
- [x] T043 [US2] Split framebuffer metadata from update rectangle dimensions in `NaruRemote/Sources/NaruRemoteCore/VNC/RFBProtocolDecoder.swift`
- [x] T044 [US2] Add dirty-rectangle metadata regression test in `NaruRemote/Tests/NaruRemoteCoreTests/RFBProtocolDecoderTests.swift`
- [x] T045 [US1] Add lock-based isolation to mutable profile stores in `NaruRemote/Sources/NaruRemoteCore/ConnectionHub/ConnectionProfileStore.swift`
- [x] T046 [US1] Add concurrent profile save regression test in `NaruRemote/Tests/NaruRemoteCoreTests/ConnectionProfileStoreTests.swift`
- [x] T047 Sync `spec.md`, `plan.md`, `data-model.md`, `research.md`, and `quickstart.md` with current implementation behavior

## Phase 9: Roadmap And App Shell

- [x] T048 Create `ROADMAP.md` with current phase, next engineering priorities, and deferred post-MVP input expansion
- [x] T049 Add `NaruRemoteApp` SwiftPM target and `NaruRemoteAppTests` in `Package.swift`
- [x] T050 Add app shell presentation model and tests in `NaruRemote/App/AppShell/` and `NaruRemote/Tests/NaruRemoteAppTests/`
- [x] T051 Sync `AGENTS.md`, `plan.md`, `research.md`, and `quickstart.md` with the app shell target and 24-test baseline

## Phase 10: Next Roadmap Tasks

- [x] T052 Add installable iOS/iPadOS app bundle target and launch entry point
- [x] T053 Add simulator, screenshot, or UI automation verification for the app shell
- [x] T054 Build a networked fake RFB server executable from `TestFixtures/FakeRFBServer/Fixtures/noauth-first-frame.hex`
- [x] T055 Add initial RFB decoder/probe integration tests against the networked fake RFB server

## Phase 11: Fresh Review Remediation

- [x] T056 [US4] Omit diagnostic next actions from default export and add explicit next-action redaction coverage
- [x] T057 [US3] Map generic clipboard and paste errors to stable user-safe messages
- [x] T058 [US3] Separate unknown send status message from failure reason in `ComposeDraft`
- [x] T059 [US1] Fall back to the first available profile when app shell selection is stale
- [x] T060 [US4] Use unique diagnostic row identifiers for repeated diagnostic stages
- [x] T061 Sync `data-model.md`, `contracts/diagnostics.md`, `research.md`, `quickstart.md`, and `ROADMAP.md` with fresh review changes

## Phase 12: Fake RFB Server Integration

- [x] T062 Add `FakeRFBServerKit` and `FakeRFBServer` executable targets in `Package.swift`
- [x] T063 Implement hex transcript loader in `TestFixtures/FakeRFBServer/ServerKit/FakeRFBTranscript.swift`
- [x] T064 Implement TCP fake RFB server in `TestFixtures/FakeRFBServer/ServerKit/FakeRFBServer.swift`
- [x] T065 Implement TCP probe client in `TestFixtures/FakeRFBServer/ServerKit/FakeRFBProbeClient.swift`
- [x] T066 Add networked no-auth first-frame integration test in `NaruRemote/Tests/FakeRFBServerKitTests/`
- [x] T067 Update fake RFB server README and Spec Kit artifacts with the executable command
- [x] T068 Add production `RFBClientBoundary` integration test against `FakeRFBServerKit`

## Phase 13: Current Review Remediation

- [x] T069 Clear stale `RFBNetworkClient.lastFrame` when a reconnect attempt fails
- [x] T070 Reject too-short RFB network transcripts with a typed error instead of fixed-slice precondition traps
- [x] T071 Sync Spec Kit artifacts after current review remediation

## Phase 14: Simulator Smoke Verification

- [x] T072 Embed `NaruRemoteCore` directly in the generated iOS app target so standalone simulator launch resolves all app frameworks
- [x] T073 Capture iPad simulator app-shell screenshot after standalone install/launch
- [x] T074 Capture iPad simulator Korean/English/emoji local compose screenshot with the iPad keyboard visible
- [x] T075 Re-run `swift test` and the iPad simulator UI test after the launch/screenshot fix

## Phase 15: Keyboard-Adjacent Compose Bar

- [x] T076 Pin the Remote Input Dock to the bottom safe-area inset so it moves directly above the iPad keyboard while composing
- [x] T077 Add XCUITest coverage for keyboard-adjacent compose editor placement
- [x] T078 Sync MVP spec, quickstart, and roadmap with keyboard-adjacent compose behavior

## Phase 16: PiP Watch Mode Foundation

- [x] T079 [US5] Promote PiP Watch Mode in product spec, MVP spec, plan, data model, research, roadmap, and contract docs
- [x] T080 [P] [US5] Add PiP Watch Mode core tests in `NaruRemote/Tests/NaruRemoteCoreTests/PiPWatchSessionTests.swift`
- [x] T081 [US5] Implement watch-only PiP state and adaptive frame policy in `NaruRemote/Sources/NaruRemoteCore/PiPWatchMode/PiPWatchSession.swift`
- [x] T082 [US5] Add PiP Watch presentation status and app shell entry point in `NaruRemote/App/`
- [x] T083 [US5] Add app snapshot and launch UI coverage for the PiP Watch affordance
- [x] T084 Re-run SwiftPM and generated Xcode project checks after PiP Watch foundation work

## Phase 17: PiP Review And Spec Sync

- [x] T085 [US5] Add profile-level PiP Watch opt-out to `ConnectionProfile` with legacy decode defaulting
- [x] T086 [US5] Gate PiP Watch preparation on profile policy, allowed session state, and received frame metadata
- [x] T087 [US5] Prevent unprepared or zero-size PiP frame snapshots from entering `watching`
- [x] T088 [US5] Keep the app-shell PiP affordance disabled until a real renderer action is wired
- [x] T089 [US5] Add XCTest/XCUITest coverage for profile opt-out, frame-gated availability, invalid frame rejection, and disabled no-op affordance
- [x] T090 Sync product spec, MVP spec, plan, data model, contract, research, quickstart, and roadmap with PiP review changes

## Phase 18: First-Run Onboarding Foundation

- [x] T091 [US6] Add first-run onboarding requirements to product spec, MVP spec, plan, data model, research, roadmap, and quickstart
- [x] T092 [US6] Implement safe `OnboardingGuide` and `OnboardingStep` models in `NaruRemote/Sources/NaruRemoteCore/Onboarding/`
- [x] T093 [US6] Add onboarding model tests for private target next step, failed diagnostic safe display, composed-text non-disclosure, and PiP opt-out
- [x] T094 [US6] Add first-run checklist UI in `NaruRemote/App/Features/Onboarding/` and wire it into `NaruRemoteAppShell`
- [x] T095 [US6] Add app snapshot and launch UI coverage for onboarding visibility and non-disclosure
- [x] T096 Re-run SwiftPM and generated Xcode project checks after onboarding work

## Phase 19: Live Connection Foundation And Export Hardening

- [x] T097 [US1] Add app-shell model tests for adding a profile and connecting through an injected RFB first-frame connector
- [x] T098 [US1] Implement `NaruRemoteAppModel` as the app-shell coordinator for profile selection, Add Profile, Checks, and Connect
- [x] T099 [US1] Add `ProfileEditorView` and wire Add Profile/Profile selection into `NaruRemoteAppShell`
- [x] T100 [US2] Add interactive fake-server coverage for an RFB 3.8 no-auth first-frame handshake
- [x] T101 [US2] Implement `RFBFirstFrameConnecting.connectNoAuthFirstFrame` with client writes for version negotiation, security selection, ClientInit, and framebuffer update request
- [x] T102 [US3] Add RFB client message encoder coverage for UTF-8 `ClientCutText` and paste key events
- [x] T103 [US3] Keep `RFBNetworkClient` connected after the first frame and implement `RemoteClipboardTextClient` writes for clipboard text and paste command delivery
- [x] T104 [US3] Extend the fake RFB server with client-message recording and verify network clipboard/paste writes after handshake
- [x] T105 [US4] Replace caller-dependent diagnostic export detail redaction with a fixed safe stage-detail catalog
- [x] T106 [US3] Wire Remote Input Dock Send into `NaruRemoteAppModel` and preserve local text when no active RFB text client exists
- [x] T107 Sync `spec.md`, `plan.md`, `data-model.md`, `contracts/diagnostics.md`, `research.md`, `quickstart.md`, and `ROADMAP.md` with live connection foundation status

## Phase 20: Persisted Launch And Raw Frame Decode Foundation

- [x] T108 [US1] Add file-backed profile persistence and missing-file/round-trip tests for app-local saved profiles
- [x] T109 [US1] Replace static iOS launch seed with an Application Support profile store and empty first-run launch state
- [x] T110 [US1] Add app-model tests for loading saved profiles and persisting newly added profiles
- [x] T111 [US1] Update iPad launch UI tests to isolate profile storage and verify empty first-run plus Add Profile editor behavior
- [x] T112 [US2] Add 32-bit true-color raw framebuffer decoder and regression tests for RGBA pixels, unsupported encodings, out-of-bounds rectangles, and incomplete payloads
- [x] T113 Sync product spec, MVP spec, plan, data model, research, quickstart, and roadmap with persisted launch and raw frame decode status

## Phase 21: Repeated Raw Frame Network Primitive

- [x] T114 [US2] Add a no-auth session path to `RFBNetworkClient` that keeps the connection active without consuming an initial frame update
- [x] T115 [US2] Add raw framebuffer update request/receive/decode support over the active RFB connection
- [x] T116 [P] [US2] Extend `FakeRFBServer` with scripted raw framebuffer updates after repeated framebuffer update requests
- [x] T117 [US2] Add fake-server integration coverage for two sequential raw framebuffer updates on one connection
- [x] T118 Sync product spec, MVP spec, plan, data model, research, quickstart, and roadmap with repeated raw frame network primitive status

## Phase 22: Frame Pump And First Frame Preview

- [x] T119 [US2] Add `RFBFramebufferUpdating`/`RFBStreamingClient` contracts for streaming-capable RFB clients
- [x] T120 [P] [US2] Add `RFBFramePump` tests for full-then-incremental requests, callback stop, cancellation, and source errors
- [x] T121 [US2] Implement `RFBFramePump` as the cancellable repeated framebuffer update loop boundary
- [x] T122 [US2] Update `NaruRemoteAppModel` to use the streaming client path and store the first decoded framebuffer when available
- [x] T123 [US2] Add sampled SwiftUI framebuffer preview support to `SessionViewportView`
- [x] T124 Sync product spec, MVP spec, plan, data model, research, quickstart, and roadmap with frame pump and first-frame preview status

## Phase 23: App Frame Streaming Task

- [x] T125 [US2] Expose delivered frame count and next-frame stepping on `RFBFramePump` for app-owned frame tasks
- [x] T126 [US2] Add app-model tests proving later streaming frames replace earlier framebuffers
- [x] T127 [US2] Add app-model tests proving profile changes cancel stale frame streams and clear framebuffer state
- [x] T128 [US2] Wire a long-lived streaming frame task into `NaruRemoteAppModel` for streaming-capable connectors
- [x] T129 Sync product spec, MVP spec, plan, data model, research, quickstart, and roadmap with app frame streaming task status

## Phase 24: VNC Password Authentication Primitive

- [x] T130 [US2] Add VNC authentication response generation with bit-reversed DES password keys in `NaruRemoteCore`
- [x] T131 [US2] Extend `RFBNetworkClient` security negotiation to choose `None` or `VNC Authentication` based on available credentials
- [x] T132 [P] [US2] Extend `FakeRFBServer` with deterministic VNC authentication challenge, success, and rejection behavior
- [x] T133 [US2] Add fake-server integration tests for authenticated sessions, missing-password reporting, and rejected-password failures
- [x] T134 Sync product spec, MVP spec, plan, data model, research, quickstart, and roadmap with VNC password authentication status

## Phase 25: Credential Store And App Credential Lookup

- [x] T135 [US1] Add credential store boundary with in-memory and Keychain-backed password stores
- [x] T136 [US1] Capture optional VNC password in Profile Editor without writing plaintext into `ConnectionProfile`
- [x] T137 [US1] Save profile passwords through the credential store and persist only `credentialRef`
- [x] T138 [US2] Resolve `credentialRef` before Connect and pass VNC password credentials into authenticated streaming connections
- [x] T139 [US2] Add app-model tests for credentialRef-only save, authenticated credential lookup, and missing credential failure
- [x] T140 Sync product spec, MVP spec, plan, data model, research, quickstart, and roadmap with credential store/app lookup status

## Phase 26: PiP Lifecycle And Optimized Frame Pipeline

- [x] T141 [US5] Wire the app-shell PiP Watch action into `NaruRemoteAppModel` and add start/stop/staleness tests
- [x] T142 [US2] Add raw framebuffer update result, dirty-region metadata, incremental compositing, and change-activity tests
- [x] T143 [US2] Persist the previous framebuffer inside `RFBNetworkClient` and add fake-server partial incremental update coverage
- [x] T144 [US2/US5] Preserve damage/change metadata through `RFBFramePump` and drive PiP Watch activity from actual frame changes
- [x] T145 Sync product spec, MVP spec, plan, data model, contract, research, quickstart, and roadmap with the optimized frame pipeline

## Phase 27: Sample Buffer PiP Renderer Boundary

- [x] T146 [US5] Add a tested `RFBRawFramebuffer` to `CVPixelBuffer`/`CMSampleBuffer` conversion boundary in `NaruRemoteApp`
- [x] T147 [US5] Add `AVSampleBufferDisplayLayer` renderer coverage for aspect display and presentation timestamps
- [x] T148 [US5] Add an iOS-only `AVPictureInPictureController` content-source wrapper for sample-buffer PiP startup
- [x] T149 [US5] Verify SwiftPM tests and generated iOS simulator build/UI tests after the PiP renderer boundary
- [x] T150 Sync product spec, MVP spec, plan, data model, contract, research, quickstart, and roadmap with sample-buffer PiP renderer status

## Phase 28: System PiP Controller Wiring Review Pass

- [x] T151 [US5] Add a `PiPWatchControlling` app-layer protocol and inject the iOS `AVPictureInPictureController` wrapper into the app model
- [x] T152 [US5] Start system PiP through the app model only when the active session has a frame and the device reports PiP support
- [x] T153 [US5] Enqueue the initial and subsequent streaming framebuffers into the active PiP controller and stop the controller when PiP/session state is cleared
- [x] T154 [US5] Add tests for PiP controller prepare/start/enqueue, unsupported-device handling, render failure handling, and streaming-frame forwarding
- [x] T155 Sync product spec, MVP spec, plan, data model, contract, research, quickstart, and roadmap with system PiP controller wiring status

## Parallel Notes

- T029 still requires physical iPhone/iPad access and cannot be delegated to a
  code-only agent.
- `RFBClient`, `TextInjectionAdapter`, and diagnostic privacy work touch shared
  boundaries and should not be edited by multiple agents at the same time.
- Manual iPad IME verification cannot be delegated to a code-only agent without
  device access.
