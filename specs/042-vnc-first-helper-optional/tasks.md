# Tasks: VNC-First, Helper-Optional Presentation

**Feature**: `specs/042-vnc-first-helper-optional` · plan: `plan.md` · 2026-09-07

Wave 1 runs A, B, C, E-inv in parallel — their write sets are disjoint.
Wave 2 (D) starts after B, C, and E-inv have landed, because D edits
`NaruRemoteAppModel.swift` and `SessionViewportView.swift` (B's files) and
consumes C's wire field and E-inv's failing test. Every round: no git
state changes; the lead reviews the diff, re-runs gates, commits.

## Round A — entry hierarchy and copy (P1, P4; FR-001..003)

Writable: `NaruRemote/App/Features/Home/EmptyHomeView.swift`,
`NaruRemote/App/Features/ConnectionHub/ConnectionGridView.swift`,
`NaruRemote/App/Features/ConnectionHub/NaruPairingFlowView.swift`,
`NaruRemote/UITests/QrPairingScreenshotsUITests.swift`,
new `NaruRemote/UITests/VncFirstScreenshotsUITests.swift`,
`NaruRemote/Tests/NaruRemoteAppTests/NaruPairingProfileFactoryTests.swift` (only if a
factory string changes). Everything else read-only; the shell wiring of the
new callback is the lead's (plan decision 6).

- **T-A1 [FR-001]** Empty home: "Add a Computer" stays the single
  `.borderedProminent` action; the QR affordance becomes a secondary
  text/`.bordered` button labelled `Add by QR (Naru Helper)` with a caption
  "Optional — for Macs running Naru Helper". Grid toolbar: the QR item
  keeps its icon but its `help`/accessibility label say "Add by QR (Naru
  Helper, optional)". No string anywhere on these two surfaces says or
  implies the helper is required.
- **T-A2 [FR-002]** Scanner screen: first paragraph states the helper is
  optional and that any VNC host can be added by address; a button
  `Enter VNC details instead` calls a new `onEnterManually: (() -> Void)?`
  (default `nil`; hidden when nil). Error and hint copy: replace every
  `NaruHelper --pair` mention with "Pair with iPhone… in the Naru Helper
  menu bar app"; keep the GitHub Releases link for the helper.
- **T-A3 [FR-003]** Confirmation sheet: VNC endpoint row first
  (`Computer`, `Screen sharing port`), helper ports under a
  `DisclosureGroup("Helper (optional)")` collapsed by default; keep the
  constitution line "Basic viewing keeps working without the helper".
- **T-A4** UI tests: update `QrPairingScreenshotsUITests` assertions to the
  new copy; add `VncFirstScreenshotsUITests` capturing empty home, scanner,
  and confirmation on iPhone 17 Pro to `artifacts/screenshots/vnc-first/`
  (`01-empty-home.png`, `02-scanner.png`, `03-confirm.png`). The GLM round
  does not judge the PNGs; an opus vision round does.

## Round B — transport marker and fallback notice (P2, P3; FR-004, FR-005, FR-010)

Writable: `NaruRemote/App/AppShell/NaruRemoteAppModel.swift`,
`NaruRemote/App/AppShell/NaruRemoteAppSnapshot.swift`,
`NaruRemote/App/AppShell/NaruRemoteAppShell.swift`,
`NaruRemote/App/Features/SessionViewer/SessionViewportView.swift`,
`NaruRemote/Tests/NaruRemoteAppTests/NaruRemoteAppModelTests.swift`,
new `NaruRemote/Tests/NaruRemoteAppTests/HelperVideoFallbackNoticeTests.swift`.

- **T-B1 [FR-005]** Snapshot: `HelperVideoFallbackNotice` (catalog enum:
  `permissionMissing`, `helperUnreachable`, `streamStalled`, `revoked`,
  `codecUnsupported`, `privateNetworkRequired`, `other`) with a fixed
  `title` per case (e.g. "Helper video off — Mac needs Screen Recording
  permission"); a pure `static func notice(for: HelperVideoFailureCode)`.
  No address, no error text.
- **T-B2 [FR-005]** Model: `@Published var helperVideoFallbackNotice:
  HelperVideoFallbackNotice?`, set at most once per `sessionID` when the
  profile has helper video enabled and not revoked and the transport is
  `.vncFramebuffer` because of a refused start or a mid-session fallback
  (`fallbackToVNCVisualTransport`, the `permissionMissing` branch of the
  bootstrap). `dismissHelperVideoFallbackNotice()`. Cleared in
  `resetVisualTransportState()`. **FAIL-first** test: the notice is nil
  today after a `permissionMissing` start.
- **T-B3 [FR-004]** View: a compact marker (`Label("Helper", systemImage:
  "play.rectangle")`-style, ≤ 22 pt tall, top-leading, 8 pt inset,
  identifier `naru.session.transportMarker`) rendered only when
  `visualTransportMode == .helperVideo`; a one-line dismissible notice
  (identifier `naru.session.helperVideoFallbackNotice`) rendered when the
  model publishes one; neither overlaps the input dock or the trackpad
  cursor glyph. VNC sessions render neither (assert absence).
- **T-B4** Shell passes the two values into `SessionViewportView`.
- **T-B5** Tests: marker state follows transport mode; notice appears once
  and not again after a second fallback in the same session; a VNC-only
  profile (no helper config) never gets a notice; no notice when the
  profile's helper video is disabled.

## Round C — pointer mode on the wire, cursor off in trackpad (P5; FR-007)

Writable: `NaruRemote/Sources/NaruRemoteCore/HelperVideo/HelperVideoTransport.swift`,
`NaruRemote/Tests/NaruRemoteCoreTests/HelperVideoTransportTests.swift` (or the
existing transport codec test file),
`NaruHelper/Sources/NaruHelperKit/NaruHelperVideoTransportRequestHandler.swift`,
`NaruHelper/Sources/NaruHelperKit/NaruHelperVideoScreenCaptureKitAccessUnitSource.swift`,
`NaruHelper/Sources/NaruHelperKit/NaruHelperVideoListenRuntime.swift`,
`NaruHelper/Tests/NaruHelperKitTests/**` (new test file preferred).

- **T-C1 [FR-007]** `HelperVideoPointerMode: String, Codable` (`trackpad`,
  `directTouch`); `HelperVideoStartStreamRequestBody.pointerMode:
  HelperVideoPointerMode?` decoded with `decodeIfPresent`; encoding omits
  nil. Round-trip tests + a decode test of a body without the key.
- **T-C2 [FR-007]** Kit: the configuration policy takes `pointerMode` and
  yields `showsCursor` (`trackpad` ⇒ false, else true); both capture sites
  apply it. Unit test on the policy, FAIL-first (today always true).
- **T-C3 [R1]** Measure `SCStream.updateConfiguration` toggling
  `showsCursor` live on this Mac (the round may use the existing benchmark
  probe path; it must not run `--pair` or touch `~/.naru`). Record the
  answer in `specs/042-vnc-first-helper-optional/research.md` §R1 and
  expose one Kit method (`updatePointerMode(_:)`) that does the measured
  right thing.

## Round E-inv — pinch parity root cause (P5; FR-009; R2) — investigation only

Writable: new `NaruRemote/Tests/NaruRemoteAppTests/HelperVideoPreviewGestureTests.swift`
and/or new `NaruRemote/UITests/HelperVideoPinchUITests.swift`;
`specs/042-vnc-first-helper-optional/research.md` §R2. All product files
read-only.

- **T-E1** Reproduce on the iPhone 17 Pro simulator with the helper-video
  primary preview (fixture: `FakeRFBServer` + the fake helper video
  transport used by `HelperVideoStreamSessionRunnerTests`) that a pinch does
  not change `zoomScale`, or prove that it does and enumerate what differs
  on a device (Metal support flag, `isPiPWatching`, pointer mode).
- **T-E2** Name the branch and the line where the gesture is lost; write the
  failing test that D must turn green; fill §R2.

## Round D — after B, C, E-inv (P5, P6; FR-006, FR-008, FR-009)

Writable: `NaruRemote/App/AppShell/NaruRemoteAppModel.swift`,
`NaruRemote/App/Features/SessionViewer/SessionViewportView.swift`,
`NaruRemote/App/Features/SessionViewer/MetalFramebufferView.swift`,
`NaruRemote/App/Features/HelperVideo/HelperVideoStreamSessionRunner.swift`,
`NaruRemote/Sources/NaruRemoteCore/ConnectionHub/ConnectionProfile.swift`,
`NaruRemote/App/Features/ConnectionHub/ProfileEditorView.swift`,
`NaruRemote/Tests/**` as needed, `NaruRemote/Tests/FakeRFBServerKitTests/**`.

- **T-D1 [FR-009]** Fix the pinch against E-inv's failing test.
- **T-D2 [FR-008]** Pump: no `FramebufferUpdateRequest` while
  `isHelperVideoHealthyPrimaryVisualTransport`; resume with a full request
  on fallback. `FakeRFBServerKit` test counting requests per state; R3
  live check recorded in `research.md`.
- **T-D3 [FR-006]** `HelperVideoTransportPreference` on the profile
  (`automatic` default via `decodeIfPresent`), editor picker shown only
  when a helper pairing exists, `vncOnly` suppresses the start request,
  the marker, and the notice.
- **T-D4 [FR-007 phone side]** Start request carries
  `pointerControlMode`; a mode switch calls the Kit-mirrored
  `updatePointerMode` through the stream client (restart if R1 says so).
- **T-D5** Shell wiring of `onEnterManually` (plan decision 6) if the lead
  has not already done it.

## Lead-owned after each wave

- Diff review, `swift test` from cold with the count compared to CI, iPhone
  simulator build.
- Opus vision verdict on `artifacts/screenshots/vnc-first/*.png` (hierarchy:
  is manual add unmistakably primary? does any line read as "helper
  required"?).
- Founder device pass for one cursor, pinch, and bandwidth (SC-2, SC-3).
- `NEXT_STEPS.md` 00m and the spec Status line.
