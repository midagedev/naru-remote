---
description: "Tasks: Host Helper Video Stream"
---

# Tasks: Host Helper Video Stream

**Input**: Design documents from `/specs/007-host-helper-video-stream/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, verification matrix  
**Product**: Naru Remote

## Phase 1: Spec & Research Readiness

- [x] T001 Read `docs/BRANDING.md`, `docs/PRODUCT_SPEC.md`,
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
- [x] T030B [US1] Split helper-video H.264 sample-buffer preparation from
  display-layer enqueue by making the access-unit renderer async, moving
  Annex-B parsing / AVCC conversion / CoreMedia sample-buffer creation into a
  dedicated actor, and keeping only `AVSampleBufferDisplayLayer` mutation on
  MainActor. Also move the VNC frame-application worker loop/pacing sleeps to a
  detached task so it hops to the app model only for the bounded commit.
  **Done.**
- [x] T030C [US1] Add privacy-safe MainActor responsiveness heartbeat
  diagnostics to active frame streams so physical-iPhone freeze reports can be
  triaged as UI-executor stalls versus network/decode/input queue pressure
  without exporting exact timings, endpoints, framebuffer data, coordinates,
  keysyms, or text. **Done.**
- [x] T030D [US1] Tighten `physical-device-preflight` so a known but unavailable
  physical iPhone is reported as a discovery blocker and the build check is
  skipped, instead of collapsing the setup issue into a generic physical build
  failure. Current local run reports `physical-iphone-device-unavailable`,
  which routes the next manual action to unlock/connect/developer-mode setup
  before T030/T031 evidence collection. **Done.**
- [x] T031A [US2] Add an opt-in
  `helper-screen-app-bootstrap-benchmark` launchctl runner and benchmark smoke
  that routes finite ScreenCaptureKit access units through helper TCP framing,
  app-model helper-video bootstrap, and the H.264 sample-buffer factory while
  emitting only fixed JSON labels. Current local run reports `skipped` because
  the benchmark host still needs Screen Recording/capture setup, so this is a
  readiness gate for T031 rather than T031 completion. **Done.**
- [x] T031B [US2] Upgrade `remote-desktop-10fps-readiness` to schema `2` with
  physical iPhone preflight and a product-oriented `readinessGateSummary` that
  separates wrapper execution success from the inner 10fps product verdict.
  Current local run now reports `blockedByHelperScreenCapture`,
  `helper-video-screen-capture-gate-blocked`, and
  `vnc-10fps-product-gate-failed`, with VNC still failing at about 2 content
  FPS from first-byte wait dominance; T031I records the action-order
  correction that made helper Screen Recording setup the primary next action.
  **Done.**
- [x] T030E [US1] Keep Direct key-event emission recoverable after a write
  timeout by recording timeout diagnostics without cancelling the active key
  event client or emitter; add a regression that a later key still emits
  down/up events after the first write times out. **Done.**
- [x] T030F [US1] Add fixed physical device-class labels to
  `physical-device-preflight` so T030 reruns can prove whether the resolved
  physical device is `iPhone`, `iPad`, or `unknown` without printing device
  names or identifiers. The physical iPhone helper-video gate now forces its
  nested preflight to the iPhone target class and blocks explicit non-iPhone
  class configuration with `physical-iphone-target-class-required`. Covered by
  device-id resolution and physical gate self-tests plus a current safe
  preflight run reporting `targetDeviceClass=iPhone` and
  `resolvedDeviceClass=iPhone`. **Done.**
- [x] T030G [US1] Add fixed lock/backlight readiness labels to
  `physical-device-preflight` so a device that has not been unlocked after
  boot, or a known inactive backlight state, blocks the long physical iPhone
  helper-video UI gate before it can time out. The runner reports
  `deviceUnlockedSinceBootStatus` and `deviceBacklightState` without exporting
  device identifiers or raw OS errors, and maps blockers to
  `unlock-physical-iphone`. Covered by JSON parser self-tests plus a current
  safe preflight run reporting `deviceUnlockedSinceBootStatus=true` and
  `deviceBacklightState=activeOn`. **Done.**
- [x] T030H [US1] Add an iPad-specific physical-device preflight so connected
  iPad launch/test failures can be separated from the iPhone-first T030 gate.
  The new `physical-ipad-device-preflight` mode selects only physical iPads,
  reports fixed target/resolved device-class and lock labels, and classifies
  Xcode account/provisioning blockers before claiming app launch failure.
  Current live evidence reports `targetDeviceClass=iPad`,
  `resolvedDeviceClass=iPad`, `deviceDiscoveryStatus=connected`,
  `deviceUnlockedSinceBootStatus=true`, `xcode-account-missing`, and
  `ios-provisioning-profile-missing`, so the iPad app has not reached launch in
  this execution context. Covered by a live iPad preflight run and
  `physical-ipad-device-preflight-self-test`, which pins `No Accounts` /
  `No profiles for` xcodebuild patterns to fixed safe labels. **Done.**
- [x] T030I [US1] Add fixed physical signing inventory labels so repeated
  physical iPhone signing blockers can distinguish team/certificate mismatch
  from missing local provisioning inventory without printing team IDs,
  certificate names, profile filenames, profile UUIDs, account IDs, raw
  xcodebuild logs, or device identifiers. `physical-device-preflight`,
  `physical-ipad-device-preflight`, `helper-video-live-gate` summary, and
  `remote-desktop-10fps-readiness` summary now report
  `developmentTeamCertificateMatchStatus` and
  `localProvisioningProfileInventoryStatus`. Current live helper-video gate
  reports helper-video probes and app bootstrap passing, then blocks only on
  physical iPhone signing with `developmentTeamCertificateMatchStatus=matched`,
  `localProvisioningProfileInventoryStatus=none`, `xcode-account-missing`, and
  `ios-provisioning-profile-missing`. Covered by self-tests and live preflight
  / helper-video gate evidence. **Done.**
- [x] T030J [US1] Add a connected iPad launch-smoke gate that does not rely on
  XCTest application lifetime: `physical-ipad-launch-smoke` installs the
  existing `NaruRemote.app`, foreground-launches `com.naruremote.app`, and
  verifies the launched process remains running after a short observation
  window. The gate also records fixed lock/backlight labels and blocks with
  `unlock-physical-ipad` before install/launch if the iPad is locked or the
  screen is inactive. Current connected-iPad evidence reports connected,
  unlocked, active screen, app bundle present, install passed, launch passed,
  launch PID present, and running passed, so short XCTest completion should not
  be triaged as an app launch failure. **Done.**
- [x] T030K [US1] Add a connected iPad app-state marker smoke gate so physical
  device runs can prove the launched app applied safe seed profile and helper
  video test state without XCTest owning application lifetime. The app writes a
  privacy-safe marker only when `NARU_TEST_WRITE_DEVICE_STATE_MARKER` is set;
  `physical-ipad-state-marker-smoke` launches with fixed non-secret seed
  values, copies the marker from the app data container, and reports only fixed
  labels. Current simulator evidence verifies marker writing; current physical
  iPad evidence verifies install/launch/running but reports marker missing
  because CLI signing/provisioning still prevents installing a fresh physical
  app bundle with this hook. **Done.**
- [x] T030L [US1] Add a privacy-safe `physical-provisioning-doctor` so
  "Xcode has a profile" versus "non-interactive xcodebuild can see a matching
  installed profile" is diagnosed without printing profile paths, filenames,
  UUIDs, team IDs, device IDs, bundle identifiers, account IDs, raw xcodebuild
  logs, or credentials. The doctor reports project signing settings, caller
  versus launchctl team-env presence, local Apple Development identity bucket,
  standard provisioning inventory, optional candidate-profile match labels, and
  a single recommended action. Current iPhone and iPad evidence both report
  connected devices, matched local certificate/team, expected app bundle, but
  missing project team/profile specifier and zero standard installed
  provisioning profiles, so the next action is to download/install a development
  profile visible to CLI or point the doctor at the candidate profile path.
  **Done.**
- [x] T031C [US2] Add a sustained external synthetic H.264 helper-video probe,
  frame-budget-aware helper timeouts, deterministic synthetic VideoToolbox
  batch encoding, and fixed external-helper transport issue labels. Current
  local run reports healthy/smooth/high-profile helper-video after the
  launchctl helper path is refreshed to the current SwiftPM helper artifact.
  **Done.**
- [x] T031D [US2] Add a privacy-safe `helper-dev-app-setup` runner that
  installs the stable dev helper app wrapper, sets launchctl helper executable,
  requests Screen Recording, and emits only fixed setup/status labels. Current
  local run reports app-bundle identity, synthetic/sustained helper-video pass,
  and Screen Recording permission still missing. **Done.**
- [x] T031E [US1] Reproduce the focused Compose freeze as a
  `connecting -> active` session-transition render-state change, then defer
  live-session dock layout and quick-key accessory invalidation while UIKit
  owns Compose focus. Send-result status is now handled by a detached status
  line so the focused editor host stays stable, and unfocused docks still adopt
  the compact live layout. **Done.**
- [x] T031F [US3] Surface helper-video readiness on connection-grid cards with
  fixed safe labels, and preserve an existing helper-video opt-in when a
  profile is edited through the current profile editor. Current live readiness
  still routes the smooth visual path to `Screen Recording` setup while VNC
  remains the control/input/fallback path. **Done.**
- [x] T031G [US1] Reproduce the post-send focused Compose freeze where typing
  a Korean syllable clears `latestInjectionAttempt`, then prevent that status
  clear from invalidating the UIKit editor host. Keep actionable status visible
  in a sibling focused-status line and verify simulator Compose still accepts a
  second Korean syllable in both profile-detail and active compact layouts.
  **Done.**
- [x] T031H [US2] Add a fixed VNC transport-cadence drilldown before spending
  more work on VNC profile flips. The new runner compares request/response and
  ContinuousUpdates under the exact 10fps local `0.25` visible-glance shape,
  records that request/response still fails at about 6 content FPS from
  first-byte wait, records that ContinuousUpdates fails before usable samples
  on the current Mac Screen Sharing target, and confirms Screen Recording
  permission is still missing for helper-video. **Done.**
- [x] T031I [US2] Correct the `remote-desktop-10fps-readiness` primary action
  order so helper ScreenCaptureKit permission failure reports
  `blockedByHelperScreenCapture` and
  `grant-helper-video-app-screen-recording-permission` before physical iPhone
  setup. Current local run still records the physical iPhone and VNC 10fps
  gates as blocked/failed, but routes the next practical benchmark step to
  helper Screen Recording because true helper-video capture cannot run without
  it. **Done.**
- [x] T031J [US1] Re-evaluate Compose delivery after physical feedback showed
  `Remote app confirmation unavailable` could still mean no remote text. A
  reachable helper text bridge is now the first Compose delivery route for all
  non-empty payloads; VNC clipboard + paste remains fallback only when helper is
  absent or not known reachable. Covered by focused app-model routing tests.
  **Done.**
- [x] T031K [US2] Add a bounded `screen-recording-watch` setup runner so the
  human-in-the-loop macOS Screen Recording grant can be detected without
  repeatedly hand-running helper capability and readiness commands. The mode
  requests permission, opens Settings unless skipped, polls safe helper
  capability JSON, and routes granted results to the true helper-video live
  benchmark action. Covered by `screen-recording-watch-self-test` and a short
  live helper run that still reports `permissionMissing`. **Done.**
- [x] T031L [US2] Upgrade helper-video benchmark reports to schema v2 with
  fixed `readinessState` and `recommendedAction` labels, and make
  `remote-desktop-10fps-readiness` require sustained synthetic helper-video
  before physical iPhone promotion. Current live evidence reports sustained
  synthetic helper-video pass/ready, true ScreenCaptureKit permission-blocked,
  and VNC still below the 10fps iPhone product gate. Covered by helper-video
  report tests, comparison/preflight tests, summary self-test, and launchctl
  live helper/readiness probes. **Done.**
- [x] T031M [US1] Replace the app's helper-video bootstrap fast path with a
  long-lived authenticated event stream: the helper server can forward Async
  access units as they are produced, the iOS client can consume
  start/access-unit/stall events without a finite batch cap, and the app runner
  publishes healthy state once while continued access units flow only through
  the renderer. **Done.**
- [x] T031N [US1] Replace helper-video source-side finite batches with
  sustained source streams: VideoToolbox synthetic and ScreenCaptureKit
  injected/live pixel-buffer paths now feed a streaming H.264 encoder, helper
  `--video-listen` defaults to continuous streaming unless a benchmark passes a
  positive `--video-frame-count`, and the client treats stream timeout as an
  idle timeout refreshed by each event. Covered by encoder, ScreenCaptureKit
  injected-stream, helper network, and listen-runtime tests. **Done.**
- [x] T031O [US1] Make the helper-video sender backpressure-aware by opening
  access-unit sources only after an accepted start response is framed, sending
  the start response before capture/encode stream startup on the TCP path,
  awaiting each `NWConnection.send` before consuming the next access unit, and
  coalescing continuous raw synthetic/ScreenCaptureKit pixel-buffer streams to
  newest-one under pressure while preserving encoded access-unit order. Covered
  by helper frame-pipeline and network-service tests. **Done.**
- [x] T031P [US1] Promote helper-video to a true foreground visual path: start
  helper-video in parallel with VNC connect instead of waiting for the first VNC
  framebuffer, allow helper visual selection while the session is connecting,
  share a model-owned helper-video `AVSampleBufferDisplayLayer` with the
  foreground viewport, force SwiftUI direct/trackpad overlays when the
  sample-buffer layer is primary, and route pointer input through VNC
  `ServerInit` coordinate space before the first VNC framebuffer is published.
  Covered by slow-VNC-first-frame app-model, pre-first-frame pointer input, and
  helper-primary overlay policy tests. Current live readiness still needs macOS
  Screen Recording permission before true ScreenCaptureKit helper-video can
  clear T031. **Done.**
- [x] T031Q [US1] Generalize frame delivery priority from Compose-only editing
  to active session interaction: Compose focus, viewport zoom/pan gestures, and
  transient direct-key / hardware-key / pointer / trackpad input now switch
  steady VNC frame delivery to an input-friendly coalescing cadence, with
  pending steady frames rescheduled and focus/gesture reasons preserving the
  priority across transient lease expiry. This reduces frame-event contention
  with UIKit input and local viewport navigation while helper-video Screen
  Recording and physical iPhone gates are still blocked. **Done.**
- [x] T031R [US1] Gate session-scoped helper-video callbacks on the current
  session lifecycle state so late stream health/profile updates for failed or
  closed sessions cannot mutate the active visual transport, helper-video
  health, or profile availability. This gives the video path an explicit
  lifecycle boundary from UI/input state while reproducing the stale-callback
  failure as an app-model regression test. **Done.**
- [x] T031S [US2] Rerun the product-level 10fps readiness gate after the
  focused Compose hot-path fix and stale helper-video lifecycle guard. Current
  live evidence still shows VNC failing the 10fps product gate from
  first-byte-wait-dominated receive cadence while helper-video synthetic and
  sustained synthetic H.264 pass. True ScreenCaptureKit helper-video remains
  blocked by macOS Screen Recording permission for the helper app bundle; the
  next required action is grant permission, quit/relaunch helper, rerun
  `screen-recording-watch`, then run the true helper-video live capture gate.
  **Done.**
- [x] T031T [US1] Reproduce the remaining physical-feel issue as a missing
  service-level split between IME text input, viewport navigation, and ordinary
  visual frame delivery. Add separate frame-delivery cadences, make Compose
  focus win over viewport/transient interactions, publish viewport transforms
  live for view-aware request regions, and increase zoomed trackpad
  cursor-follow pan coupling while preserving finger-paced visible cursor
  travel. **Done.**
- [x] T031U [US2] Add a `helper-video-live-gate` runner that chains the
  Screen Recording watch, helper readiness sweep, and app bootstrap smoke into
  one privacy-safe report. When Screen Recording is still missing, the runner
  skips impossible helper capture work and reports
  `blockedByScreenRecordingPermission`; once permission is granted, the same
  command proceeds toward the true helper-video app decode gate and physical
  iPhone handoff. Covered by `helper-video-live-gate-self-test` and a short
  live permission-missing run. **Done.**
- [x] T031V [US2] Add an explicit helper-video rate-control policy that maps
  safe quality/frame-rate buckets to VideoToolbox average bitrate and
  one-second hard data-rate caps, then apply it to synthetic and ScreenCaptureKit
  H.264 encoder sessions without exporting raw traffic counters in diagnostics
  or benchmark JSON. Covered by helper encoder policy tests and a live
  permission-gated helper-video run. **Done.**
- [x] T031W [US1] Add an app-side helper-video start request policy so nominal
  sessions request `readability/upTo30`, while app power saver, iOS Low Power
  Mode, or elevated thermal state request `readability/upTo15` before the stream
  reaches the helper encoder. Covered by policy and bootstrap routing tests.
  **Done.**
- [x] T031X [US1] Apply input-aware cadence before MainActor frame application,
  not only after frames reach the viewport store. Compose focus caps repeated
  content frame application at 10fps-class cadence, viewport navigation keeps a
  20fps-class cap, and ordinary visual playback keeps the 60fps-class floor so
  queued frames coalesce to the newest frame before they can compete with
  UIKit IME, local zoom/pan, or trackpad sampling. After a pacing sleep,
  replace stale dequeued content with the newest pending content frame. **Done.**
- [x] T031Y [US1] Split helper-video primary visual transport from VNC visual
  request cadence. When helper-video is the healthy foreground visual path, VNC
  remains connected for input/control and fallback but samples framebuffer
  updates at the fixed helper-primary fallback cadence; if helper-video falls
  back or the stream/session changes, the next VNC request resumes ordinary
  cadence. Diagnostics now count helper-primary VNC sampling pacing samples.
  Covered by pacing policy, app-model control-path, fallback-resume, and
  diagnostic report tests. **Done.**
- [x] T031Z [US2] Make `helper-video-live-gate` collect physical iPhone
  preflight even when Screen Recording permission blocks true helper capture.
  The summary now reports helper permission and physical signing/provisioning
  blockers together, with fixed setup action labels, so Screen Recording and
  Xcode account/profile setup can be resolved in parallel before the next true
  helper-video physical run. Covered by live-gate self-test and a current live
  permission-missing run. **Done.**
- [x] T031AA [US1] Reproduce the remaining input freeze class as VNC
  request/decode overwork during active interaction, not only MainActor frame
  application churn. Focused Compose now paces the next VNC framebuffer request
  at a 10 Hz-class floor, transient direct-key/pointer/trackpad activity at a
  20 Hz-class floor, while viewport gestures keep their existing
  viewport-aware policy. Diagnostic schema v33 adds safe
  `activeInputPacingSampleCount` so physical logs can prove this protection
  engaged without exporting text, keysyms, coordinates, pixels, endpoints, byte
  counts, or exact timings. Covered by policy, app-model reproduction, snapshot,
  diagnostic, and delivery-priority tests. **Done.**
- [x] T031AB [US1] Add app-side helper-video render backpressure before
  CoreMedia sample-buffer preparation. `AVSampleBufferDisplayLayer`
  readiness now lets the foreground renderer drop only H.264 delta access units
  when its queue is full, while parameter sets and keyframes still pass through
  for decoder state and visible recovery. Dropped deltas downgrade helper-video
  health to fixed `usable/medium` labels instead of replaying stale frames and
  increasing sustained iPhone heat/latency. Covered by event-stream, finite
  start-result, H.264 renderer, and opt-in static app-runner benchmark tests.
  **Done.**
- [x] T031AC [US2] Treat Screen Recording permission-missing helper-video
  reports as setup blockers, not invented stream-health failures. When an
  explicit `helper-video-permission-missing` issue is present, benchmark
  reports now normalize the issue list to that single setup blocker, suppressing
  both derived and mixed explicit `stream-unhealthy`, `startup-failed`,
  `sustained-stalled`, `transport-failed`, and `fallback-observed` labels so
  live readiness routes to the single actionable permission step before true
  capture starts. Covered by helper-video report tests, readiness summary
  self-test, helper live-gate self-test, and current launchctl-backed readiness
  runs. **Done.**
- [x] T031AD [US2] Make the ScreenCaptureKit app bootstrap smoke use the
  selected external helper executable instead of capturing inside the XCTest
  benchmark host. The smoke now preflights the helper app's Screen Recording
  capability, launches `--video-listen --video-source screen-capturekit`, and
  drives the app-model TCP/decode/bootstrap path against that process. The
  launchctl runner imports `NARU_HELPER_EXECUTABLE` for standalone bootstrap
  runs and maps skipped output to fixed helper-executable or helper app Screen
  Recording setup actions rather than asking for benchmark-host capture
  permission. Current granted live run reports true ScreenCaptureKit
  helper-video and app bootstrap passing; the remaining blocker is the physical
  iPhone signing/provisioning gate. **Done.**
- [x] T031AE [US1] Add a privacy-safe
  `physical-iphone-helper-video-gate` runner that turns the current manual
  physical-device xcodebuild recipe into a repeatable handoff from helper-video
  readiness. The runner imports launchctl/current-shell physical E2E values,
  falls back to live VNC host/password when needed, requires sustained candidate
  labels explicitly, runs physical preflight first, launches the sustained
  iPhone UI/input gate only after signing/provisioning is ready, and summarizes
  the final safe `sustainedSessionAssessment` instead of printing raw xcodebuild
  logs. Its initial live run with explicit candidate labels was blocked only by
  `xcode-account-missing` and `ios-provisioning-profile-missing`. **Done.**
- [x] T031AF [US1] Make the physical helper-video gate seed a helper-video
  configured app profile instead of accepting a VNC-only visual path. The
  runner now requires helper-video pairing secret/fingerprint input, maps the
  Mac-side `NARU_HELPER_VIDEO_TOKEN` /
  `NARU_HELPER_VIDEO_PROFILE_FINGERPRINT` into physical E2E variables when
  needed, exposes only `helperVideoProfileMode` as a safe candidate label, and
  the iOS launch hook writes both VNC and helper-video credentials into the test
  keychain before starting from the connection grid. Current live runner output
  is blocked by `physical-e2e-helper-video-pairing-missing`,
  `xcode-account-missing`, and `ios-provisioning-profile-missing`. **Done.**
- [x] T031AG [US1] Make the physical helper-video gate own helper listener
  bootstrap. The runner defaults to auto listener mode, generates ephemeral
  helper-video pairing, starts the selected `NARU_HELPER_EXECUTABLE` as
  `NaruHelper --video-listen --video-source screen-capturekit` on port `5975`,
  suppresses helper output, tears the process down after xcodebuild, and leaves
  manual mode for externally managed listeners. Current live runner output is
  blocked only by `xcode-account-missing` and
  `ios-provisioning-profile-missing`. **Done.**
- [x] T031AH [US1] Make `remote-desktop-10fps-readiness` prioritize physical
  iPhone signing/provisioning once helper-video is ready. The summary now treats
  a connected device with failed build/account/provisioning checks as
  `blockedByPhysicalIPhoneGate`, keeps the VNC 10fps failure as a secondary
  blocked label, and now delegates the exact next step to the physical signing
  setup summary. Current live readiness shows helper-video pass, VNC about
  1.98 content FPS, and physical blockers `xcode-account-missing` plus
  `ios-provisioning-profile-missing`. **Done.**
- [x] T031AI [US1] Add an operator-facing physical signing setup summary. The
  preflight now emits `signingSetupSummary` with
  `primaryBlockedGateLabel`, `recommendedPrimaryAction`,
  `operatorActionSequence`, and privacy-safe `diagnosticLabels`, and the
  helper-video live/readiness summaries prefer that recommendation when
  physical signing is the active blocker. Current live preflight reports
  `development-team-supplied-by-environment`,
  `development-team-supplied-but-xcode-account-missing`,
  `primaryBlockedGateLabel=xcode-account`, and
  `recommendedPrimaryAction=open-xcode-account-settings`. **Done.**
- [x] T031AJ [US1] Route helper ScreenCaptureKit degraded failures to stream
  diagnosis instead of permission setup. `remote-desktop-10fps-readiness` still
  recommends `run-screen-recording-watch` for `permissionBlocked` / missing
  Screen Recording, but now follows the screen probe's fixed
  `recommendedAction` such as `inspect-helper-video-sustained-cadence` when
  Screen Recording is already `granted` and the screen probe is
  `sustainedDegraded` or `stalled`. **Done.**
- [x] T031AK [US2] Add a sustained external ScreenCaptureKit helper-video gate
  and tune the capture path for live cadence. `helper-readiness-sweep` and
  `remote-desktop-10fps-readiness` now include
  `sustainedScreenProbe`, driven by a local stimulus window and routed through
  the external helper TCP path. The benchmark client can return a safe partial
  result on idle timeout after a start response, and the ScreenCaptureKit
  capture policy prefers the main display, readability-scaled output, finite
  queue depth `5`, continuous queue depth `3`, and newest-one buffering for
  unbounded streams. Current live evidence moved sustained screen capture from
  timeout/degraded to `pass` with `sustainedUpdateBand=smooth`. **Done.**
- [x] T031AL [US2] Make continuous helper-video delivery demand-aware so slow
  iPhone/UI consumers do not build a stale pre-render backlog. The helper-video
  network client now returns a small event sequence backed by a bounded mailbox,
  preserves required start/sync/stall ordering, coalesces repeated sync/control
  roles and pending delta access units to the newest useful state, and applies
  a short receive backoff when coalescing indicates consumer pressure. Covered
  by slow-consumer delta and repeated-sync stream regressions, helper-video
  session/app-model tests, synthetic 90-frame app-runner benchmark, and real
  ScreenCaptureKit-backed 90-frame app-model smoke. **Done.**
- [x] T031AM [US2] Strengthen the helper-video app bootstrap gate from a
  two-frame smoke to a sustained default of 30 displayable ScreenCaptureKit
  frames through external helper TCP, app-model bootstrap, and H.264
  sample-buffer creation. The launchctl runner imports
  `NARU_HELPER_VIDEO_APP_BENCHMARK_FRAMES`, clamps it to `1...120`, passes the
  clamped value into the XCTest benchmark, and reports the same
  `requestedFrameCount` in both the bootstrap report and helper-video live gate
  summary. **Done.**
- [x] T031AN [US2] Make the app bootstrap gate assert the requested
  displayable frame count through the app-model runner outcome instead of only
  checking the first healthy helper-video transition. The app model now exposes
  a test/benchmark-only outcome observer and injectable finite-stream frame
  limit while preserving the production default of `16`; the benchmark raises
  that limit to `requestedFrameCount + 2` and verifies the outcome before VNC
  control-path checks. Covered by app-model outcome/limit regression, current
  30-frame ScreenCaptureKit app bootstrap, current 90-frame ScreenCaptureKit
  app bootstrap, and helper-video live gate. **Done.**
- [x] T031AO [US2] Move helper-video primary zoom/pan/input onto the same
  local hot path as the Metal framebuffer. The sample-buffer display layer now
  applies viewport transforms through Core Animation, helper-video primary uses
  a rendererless UIKit input overlay for direct touch, pinch, trackpad cursor,
  and auto-pan when Metal input is available, and SwiftUI direct/trackpad
  overlays remain only as the no-Metal fallback. Covered by viewport geometry
  policy tests, existing trackpad hot-path regressions, sample-buffer layer
  transform coverage, and the iOS simulator app build. **Done.**
- [x] T031AP [US2] Add a UIKit-free helper-video viewport/input hot-path
  benchmark seam so pan, pinch, and zoomed trackpad auto-pan can be measured
  without constructing `UIView`/`MTKView` inside XCTest. This keeps the
  simulator benchmark stable after direct rendererless-host instantiation
  proved prone to hanging the test runner, and it makes future alternatives
  comparable before physical-device promotion. Covered by Core driver tests,
  SwiftPM benchmark smoke, and iOS simulator opt-in benchmark evidence. Current
  2026-06-15 refresh realigns the long-running worktree with `main`'s cached
  `ViewportTransform` geometry baseline: the restored cache reduces the
  50,000-sample hot-path benchmark from `46679.512 kI` to `40968.283 kI`
  retired CPU instructions, and the file now matches `main`, so no new PR is
  needed for this cache itself.
  **Done.**
- [x] T031AQ [US1] Bound helper-video display-layer backpressure queries during
  delta bursts. After the renderer reports a backpressured delta, the app drops
  a short run of following deltas without re-entering the renderer/MainActor
  for each one, while parameter sets, keyframes, and end-of-stream units reset
  the window and still render for decoder sync/recovery. Covered by pure gate
  tests, helper-video stream runner regressions, and iOS simulator compile
  smoke. **Done.**
- [x] T031AR [US1] Use low-latency TCP parameters for interactive VNC and
  helper transports. RFB sessions, helper-video streams, and helper text insert
  requests now create `NWConnection` instances with TCP `noDelay` enabled so
  small framebuffer requests, input events, helper control frames, and text
  insert requests are not held behind Nagle-style packet coalescing. Covered by
  a pure Network-parameter test plus fake-server RFB handshake/key-event
  regressions and the helper-video runner/input smoke tests. **Done.**
- [x] T031AS [US2] Preserve ScreenCaptureKit source failures as typed
  helper-video stream stalls across the real TCP helper path and benchmark
  reports. Capture source unavailable, timeout, and capture failure now become
  fixed helper-video issue codes and route live/readiness summaries to
  `inspect-helper-video-capture-source` instead of generic sustained-cadence or
  permission setup. Covered by frame-pipeline, network-service, benchmark
  report, app-bootstrap wrapper, live-gate self-test, and current launchctl
  live evidence showing permission `granted` with capture source `unavailable`.
  **Done.**
- [x] T031AT [US2] Recover true helper ScreenCaptureKit capture when the live
  session exposes windows but no displays. The helper now prefers displays,
  falls back to a usable foreground window selected through CoreGraphics
  front-to-back ordering, initializes AppKit before
  `desktopIndependentWindow` capture, and the sustained helper-screen
  benchmark launches a titled normal animation window so the fallback measures
  a real app-window stream. Current launchctl evidence moves capability,
  short screen probe, sustained 30-frame screen probe, and app-bootstrap
  benchmark from capture-source/stall failures to `pass` /
  `readyForPhysicalGate`. **Done.**
- [x] T031AU [US2] Hold a short display wake assertion during finite and
  streaming helper ScreenCaptureKit startup so live app sessions are not
  blocked by a sleeping or still-recovering display. The helper retries
  shareable-content discovery once before the existing window fallback, and the
  scoped evidence artifact records the live gate moving from helper
  screen-capture blocker labels to the physical iPhone handoff. **Done.**
- [x] T031AV [US1] Remove avoidable full-payload `Data` concatenation from the
  helper-video client access-unit receive path. The wire codec now decodes
  access units from the separately received JSON frame, binary header, and H.264
  payload, and both finite `startStream` and sustained `streamEvents` use that
  split decode. The opt-in benchmark shows about 39% lower wall time, 45% fewer
  CPU cycles, and 35% fewer retired instructions for 1,000 decodes with a 256 KiB
  payload. Covered by split-codec round-trip, helper-video network-service,
  session-runner regressions, and `HelperVideoWireCodecBenchmarkTests`. **Done.**
- [x] T031AW [US1] Remove the full-payload `Data` to `[UInt8]` copy from the
  app-side helper-video Annex-B parser. The sample-buffer factory now scans the
  received `Data` with `withUnsafeBytes` while preserving owned NAL payloads,
  parameter-set caching, AVCC payload creation, and CoreMedia sample-buffer
  semantics. The opt-in benchmark shows about 62% lower CPU time, 62% fewer CPU
  cycles, and 71% fewer retired instructions for 500 delta access-unit
  preparations with a 256 KiB payload. A follow-up filter/capacity tweak was
  rejected after noisier benchmark results. Covered by parser/sample-buffer
  renderer regressions and `HelperVideoSampleBufferFactoryBenchmarkTests`.
  **Done.**
- [x] T031AX [US1] Remove the avoidable whole-frame `Data` to `[UInt8]` copy
  from VNC Raw full-frame decode by adding `RFBByteReader.readData(_:)` and
  decoding full-frame raw pixels through `Data.withUnsafeBytes`. The opt-in
  1920x1080 benchmark shows about 40% lower peak physical memory, 3% fewer CPU
  cycles, and 6% fewer retired instructions. Covered by byte-reader, raw
  framebuffer, protocol-decoder, frame-pump regressions, and
  `RFBRawDecodeBenchmarkTests`. **Done.**
- [x] T031AY [US1] Remove per-sample task cancel/recreate churn from the
  MainActor transient input/viewport frame-delivery lease. Repeated direct-key,
  quick-key, pointer, trackpad, and viewport marks now refresh one expiration
  deadline while a single sleeper task owns expiry, and unchanged reason sets
  skip redundant priority writes. The opt-in 5,000-mark benchmark shows about
  70% fewer CPU cycles, 64% fewer retired instructions, and 79% lower peak
  physical memory. Covered by frame-delivery priority
  regressions and `TransientFrameDeliveryInteractionBenchmarkTests`. **Done.**
- [x] T031AZ [US1] Remove avoidable intermediate arrays from active-session
  connection-grid preview thumbnail generation. Thumbnails now downsample live
  framebuffers directly into the final RGBA `Data` buffer and decode stored
  thumbnails through `Data.withUnsafeBytes`, avoiding the prior `[RFBColor]`
  sampling array, `flatMap` byte array, and readback copy. The opt-in 200
  thumbnail benchmark shows about 69% fewer CPU cycles, 69% fewer retired
  instructions, and 6% lower peak physical memory. Covered by preview store
  regressions and `ProfilePreviewThumbnailBenchmarkTests`. **Done.**
- [x] T031BA [US1] Avoid full-frame staged Metal buffers for same-size small
  dirty-rectangle updates. The staged renderer now prepares compact region
  payloads for partial upload plans and replaces those regions in the texture,
  while first-frame, texture-recreation, invalid, scattered, and high-area
  updates still use a full buffer. The opt-in 1920x1080 / 320x180 dirty-rect
  benchmark shows about 95% lower CPU cycles, 90% fewer retired instructions,
  and 19% lower peak physical memory versus the legacy full staged buffer.
  Covered by Metal renderer regressions and
  `SyntheticFramePipelineBenchmarkTests`. **Done.**
- [x] T031BB [US1] Skip identity row/column lookup arrays in the PiP Watch
  full-frame sample-buffer write path. Full-frame PiP pixel-buffer creation now
  writes directly from framebuffer pixel storage, while zoomed/cropped
  viewports keep the existing resampling path. The opt-in 1920x1080 benchmark
  shows about 14% lower CPU time/cycles and 11% fewer retired instructions; the
  rejected 32-bit packed-write variant is recorded to avoid repeating it.
  Covered by PiP renderer regressions and
  `PiPWatchSampleBufferFactoryBenchmarkTests`. **Done.**
- [x] T031BC [US1] Remove the full source snapshot from VNC CopyRect
  terminal-like scroll updates. CopyRect now chooses row/column direction and
  copies in place with memmove-style overlap safety, preserving existing
  CopyRect behavior while avoiding another near-full-frame `[RFBColor]`
  allocation. The opt-in 1920x1080 scroll benchmark shows about 74-75% lower
  clock/CPU time, about 77% fewer retired instructions, and about 27% lower
  peak physical memory. Covered by mixed-encoding CopyRect regressions and
  `RFBCopyRectBenchmarkTests`. **Done.**
- [x] T031AU [US2] Instrument ScreenCaptureKit no-frame timeout by callback
  stage. The helper now classifies no output callbacks, non-screen callbacks,
  non-displayable screen frames, missing image buffers, and insufficient
  displayable image-buffer frames into fixed `streamStalled` reasons; benchmark
  and app-bootstrap reports map them to privacy-safe issue labels. Current live
  evidence reports Screen Recording/capability ready, synthetic helper-video
  pass, true ScreenCaptureKit smoke/sustained/app bootstrap pass, physical
  preflight ready, and live gate routing to
  `run-physical-iphone-helper-video-gate`. **Done.**
- [x] T031AV [US2] Add fixed physical device-class labels to
  `physical-device-preflight` so T030 reruns can prove whether the configured
  target and resolved physical device are `iPhone` or `iPad` without printing
  device names or identifiers. The current safe preflight reports
  `targetDeviceClass=iPhone` and `resolvedDeviceClass=iPhone`; device-id
  resolution self-test now covers iPhone match, iPad rejection for the iPhone
  gate, and iPad match when the target class is intentionally set to iPad. The
  physical iPhone helper-video gate also forces its nested preflight to the
  iPhone target class and blocks explicit non-iPhone class configuration with
  `physical-iphone-target-class-required`. **Done.**
- [x] T031AW [US2] Keep helper ScreenCaptureKit capture alive when the Mac
  display is asleep. The helper now declares user activity, holds a
  no-display-sleep assertion during capture, retries shareable content once
  when the first snapshot has no displays, and accepts `SCFrameStatus.started`
  only when an image buffer is present. Current evidence moves the Mac-side
  helper live gate from `blockedByHelperScreenCapture` /
  `helper-video-capture-non-displayable-frames` to screen-capture and app
  bootstrap `pass`, leaving only `physical-iphone-device-unavailable`. **Done.**
- [x] T031AX [US2] Make `physical-device-preflight` signing summaries
  target-aware so iPad graceful smoke diagnostics no longer import stale iPhone
  ids or recommend the iPhone helper-video promotion gate. The default iPhone
  preflight still reports `physical-iphone-device-unavailable`, while
  `NARU_PHYSICAL_IOS_DEVICE_CLASS=ipad` now ignores the stale launchctl iPhone
  id, auto-selects the connected iPad, reports `targetDeviceClass=iPad`,
  `resolvedDeviceClass=iPad`, signing blockers, and
  `rerun-physical-ipad-smoke` as the safe follow-up label. Added
  `physical-signing-variant-probe` so the iPad signing boundary can be
  rechecked with fixed redacted labels across `allowProvisioningUpdates`,
  `localProfilesOnly`, and `allowUpdatesAndDeviceRegistration`; the current
  iPad result shows all three variants failing, including local profiles only
  with `hasNoProfiles=true`. The follow-up local profile inventory explains the
  apparent mismatch and is now reproducible with
  `physical-provisioning-profile-inventory`: scanned profiles are team-matching
  wildcard development profiles, but `bundleExactMatchCount=0`,
  `primaryBlockedGateLabel=ios-exact-provisioning-profile`, and explicitly
  selecting the wildcard profile fails with fixed `hasSpecifierMismatch=true`.
  The next useful action is exact app-bundle development profile
  creation/download or Xcode account access for automatic signing, not another
  device-id experiment. **Done.**
- [x] T031AY [US1] Refresh the simulator input/viewport gate after folding the
  focused Compose safe-area/layout fix back into the long-running
  trackpad/helper-video worktree. Focused render-state/sync policy tests pass,
  the iPhone simulator verifies profile-detail Korean Compose and real
  trackpad viewport drag burst followed by Korean Compose, and
  `simulator-input-viewport-gate` passes for iPhone and iPad simulators.
  Evidence recorded in
  `artifacts/benchmarks/2026-06-17-simulator-input-viewport-gate-after-foldin-summary.md`.
  This is simulator regression evidence only; T030 physical iPhone + Mac
  verification remains open. **Done.**
- [x] T031AZ [US2] Refresh the non-physical quickstart foundation slice and
  remove two harness traps before broader physical reruns. The readiness check
  now searches only bracketed clarification markers in spec/plan/research and
  contracts, not the quickstart/tasks prose that documents the check. The
  external helper process sustained synthetic stream test now uses a
  frame-budget-aware startup timeout instead of a fixed `3s` client timeout.
  Rerun evidence passed the non-physical helper-video foundation/app-model
  slice with 234 executed tests, 7 skips, and 0 failures in
  `artifacts/benchmarks/2026-06-17-quickstart-nonphysical-foundation-refresh-summary.md`.
  The full quickstart item remains open because physical/live permission and
  signing gates are still environment-bound. **Done.**
- [x] T031BA [US1] Recheck the helper-native text insertion observed gate so
  Compose delivery failures are separated from iOS editor responsiveness. The
  observed-probe and live-gate summary self-tests pass, but the initial real
  `unicode-hangul` observed probe reported `permissionMissing`,
  `insertStatus=failed`, and `observationStatus=no-input` with fixed setup
  actions to grant helper text Accessibility/value-insert permission and
  relaunch the helper. Evidence recorded in
  `artifacts/benchmarks/2026-06-17-helper-text-observed-permission-gate-summary.md`.
  **Done.**
- [x] T031BA1 [US1] Refresh helper-native text insertion after stable helper
  app setup and helper text permission watch. The helper text live gate now
  reports `readyForPhysicalComposeGate`, and observed native insertion passes
  for `ascii`, `latin1`, and `unicode-hangul` with `strategyUsed=nativeInsert`,
  `observationStatus=matched`, and `safeFailureCode=none`. Evidence recorded
  in `artifacts/benchmarks/2026-06-17-helper-text-observed-ready-summary.md`.
  **Done.**
- [x] T031BB [US1] Recheck the VNC KeyEvent fallback observed-delivery path
  before relying on decomposed composed text as an alternative to helper-native
  insertion. The observed probe now sends a privacy-safe pointer focus prelude
  before key events, but both `ascii` and `unicode-hangul` payloads still pass
  connect/first-frame/transcode/send and fail observation with `no-input`.
  Because ASCII also fails, the current blocker is not Hangul Unicode keysym
  transcoding alone. Evidence recorded in
  `artifacts/benchmarks/2026-06-17-text-keystroke-observed-no-input-summary.md`.
  **Done.**
- [x] T031BC [US2] Map the current implementation evidence back to
  `docs/PRODUCT_QUALITY_TARGETS.md` so release-gate status is explicit before more
  long-running experiments. The current checkpoint records helper-video
  ScreenCaptureKit/app bootstrap ready for physical promotion, helper-native
  text insertion ready for physical Compose promotion, VNC still below the
  10fps product gate at about `1.98` content FPS, request/response cadence
  below target at about `6.87` content FPS, ContinuousUpdates unsupported for
  the current Mac Screen Sharing target, and physical iPhone promotion blocked
  by Xcode account / exact app development provisioning. Evidence recorded in
  `artifacts/benchmarks/2026-06-17-product-quality-target-status.md`. **Done.**
- [x] T031BD [US2] Test whether cached wildcard development profiles can be
  safely promoted into the command-line signing path before asking for more
  physical iPhone reruns. A direct copy into the standard profile directory was
  not durable, `profiles -i -F` reported the cached profile as not compatible
  with macOS, inventory still reported `standardProfileCount=0` and
  `exactDevelopmentProfileCount=0`, and physical signing variants still failed.
  The current blocker remains Xcode account access or an exact app development
  profile for the app bundle. Evidence recorded in
  `artifacts/benchmarks/2026-06-17-physical-profile-install-attempt-summary.md`.
  **Done.**
- [x] T031BE [US2] Narrow the physical provisioning inventory setup action for
  wildcard-only profile states so it asks for
  `install-exact-profile-to-standard-provisioning-directory` instead of the
  ambiguous generic profile install action. The self-test now fails if the
  generic label returns, and the current live inventory reports exact-profile
  install beside `create-exact-ios-development-profile`. This prevents cached
  wildcard profile copy/install from being repeated as a plausible next step.
  The same exact-profile vocabulary now flows through
  `physical-device-preflight`, `physical-signing-variant-probe`, and
  `physical-iphone-helper-video-gate` profile-missing setup labels, covered by
  the signing/profile/live-gate/readiness self-tests.
  **Done.**
- [x] T031BF [US2] Switch the active quality loop to simulator-only after the
  physical iPhone was removed, and harden `simulator-input-viewport-gate` with
  per-step timeouts, progress output, fixed `.timedOut` labels, and watchdog
  child cleanup. Current simulator evidence passes the gate self-test, the
  iPhone simulator gate, and the iPhone+iPad simulator gate without claiming
  physical-device promotion. Evidence recorded in
  `artifacts/benchmarks/2026-06-17-simulator-only-timeout-hardened-gate-summary.md`.
  **Done.**
- [x] T031BG [US2] Add a nonphysical quickstart gate for simulator-only
  continuation work so available quickstart checks can be run as one repeatable
  unit without retrying physical-device setup. The new gate reports
  `physicalDevicePolicy=excluded`, passes its self-test, passes the fast
  non-simulator real run, and passes the default run including the actual
  iPhone+iPad simulator input/viewport gate. Evidence recorded in
  `artifacts/benchmarks/2026-06-17-nonphysical-quickstart-gate-summary.md`.
  **Done.**
- [x] T031BH [US2] Record helper-video wire codec split-decode benchmark
  evidence for the client receive path. The opt-in SwiftPM benchmark compares
  the historical full-frame access-unit decode against decoding from already
  split JSON/header/payload frames. With `262144` byte access-unit payloads,
  `200` samples, and `5` iterations, split decode reduced wall clock by about
  `47.7%`, CPU time by about `44.8%`, CPU cycles by about `41.8%`, and retired
  instructions by about `32.3%`. Evidence recorded in
  `artifacts/benchmarks/2026-06-17-helper-video-wire-codec-split-decode-benchmark-summary.md`.
  **Done.**
- [ ] T030 [US1] Record physical iPhone + Mac **real-screen** manual
  verification evidence. Signing/provisioning is no longer the blocker: the
  2026-07-05 120-second physical iPhone gate passed with the
  `synthetic-encoded` helper source. The remaining promotion gate is the same
  physical path with ScreenCaptureKit real-screen capture after one-time Screen
  Recording approval, extended to the 30-minute RSS/thermal target. Evidence:
  `artifacts/benchmarks/2026-07-05-physical-iphone-release-hud-and-helper-gate-summary.md`.
- [x] T031 [US2] Run a true live helper-video access-unit benchmark after the
  helper sender/listener is connected to the iOS decode path. Current
  2026-06-14 evidence reports `helper-video-live-gate` as
  `readyForPhysicalIPhoneGate`, with sustained ScreenCaptureKit helper-video
  passing and the 30-frame app bootstrap path passing through helper TCP,
  app-model bootstrap, and the H.264 sample-buffer factory. The follow-on
  physical iPhone gate timed out with fixed `physical-ios-device-locked`
  labels, so T030 remains open.

---

## Cross-Cutting

- [ ] TXXX Run all checks listed in `quickstart.md`.
- [x] TXXX Update `research.md` if Apple API, permission, codec, or helper
  transport findings change.
- [x] TXXX Security/privacy review for helper video capture, transport,
  diagnostics, benchmark reports, and logs. Evidence recorded in
  `artifacts/benchmarks/2026-06-17-helper-video-security-privacy-review-summary.md`;
  the review also fixed a selected-suite synthetic H.264 benchmark timeout
  flake by applying frame-budget-aware local probe timeouts. **Done.**
- [x] TXXX Record residual manual-device risks if physical iPhone/Mac
  verification cannot be completed in the current environment. The 2026-06-17
  signing residual was superseded by the successful 2026-07-05 synthetic-source
  physical gate; the still-open residual is real-screen Screen Recording plus
  the 30-minute sustained run. **Done.**

## Release-readiness review fixes (2026-07-12)

- [x] T031BI [US2] Bound both Toolbox and ScreenCaptureKit encoded H.264
  access-unit streams (default capacity 8, oldest-prefix retention). When a
  producer outruns its consumer, terminate with a typed backpressure failure
  instead of dropping a parameter set/keyframe/delta out of the reference
  chain. Map the typed overflow to the existing `transportBackpressure` wire
  stall so the real server/client/session runner selects VNC while preserving
  the active session and Compose draft. Covered by encoder, frame-pipeline,
  network-service, and real TCP session-runner tests. The 30-minute real-screen
  RSS/thermal gate remains open.
