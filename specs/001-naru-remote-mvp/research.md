# Research: Naru Remote MVP

**Date**: 2026-04-29  
**Spec**: `specs/001-naru-remote-mvp/spec.md`

## Decision 1: MVP Starts With Manual Private Host Entry

**Decision**: Support MagicDNS hostname and private host/IP entry first. Defer
Tailscale API inventory.

**Rationale**: Manual host entry proves the private VNC connection and Compose &
Send workflow without needing OAuth, tailnet inventory permissions, or API quota
decisions. This keeps the MVP focused and App Store review simpler.

**Alternatives considered**:

- Tailscale API inventory first: better discovery, but adds auth scope and
  privacy decisions before the core input bridge is proven.
- Public IP wizard: rejected because it conflicts with the product posture.

## Decision 2: Text MVP Uses VNC Clipboard Paste Mode

**Decision**: Compose & Send uses VNC clipboard text transfer plus remote paste
command for MVP.

**Rationale**: This directly tests the product thesis: compose locally, inject
finished text remotely. It also works without a helper and is more realistic for
IME-heavy text than per-key events.

**Alternatives considered**:

- Per-key event replay: rejected as the default because it does not handle
  Korean/Japanese/Chinese IME composition reliably.
- Helper-native insert: deferred because it requires separate install, trust,
  permissions, and revocation UX.

## Decision 3: Fake RFB Server Is Required Before Broad Compatibility Claims

**Decision**: Add a fake RFB server or fixture harness early enough to verify
handshake, clipboard payloads, failure stages, and first-frame behavior.

**Rationale**: VNC server behavior varies across macOS, Linux, Windows, and
third-party servers. Agents must have a deterministic test target before
claiming protocol behavior works.

**Alternatives considered**:

- Manual testing only: rejected because it is too slow and weak for agent work.
- Full compatibility matrix before MVP: deferred because it would delay the
  first vertical slice.

## Decision 4: Diagnostics Must Be Stage-Based

**Decision**: Diagnostics are ordered stages: DNS/MagicDNS, TCP, RFB handshake,
auth, first frame, clipboard text.

**Rationale**: Stage-based diagnostics are easier for users to understand and
for agents to test. They also produce safer beta reports than raw logs.

**Alternatives considered**:

- Generic connection error: rejected because it creates support burden.
- Raw log export first: rejected because it can leak hostnames, credentials, or
  user-entered text.

## Decision 5: Manual Device Verification Is Required For IME

**Decision**: Automated tests must cover Unicode preservation and adapter calls,
but real iPhone/iPad checks remain required for IME, dictation, hardware
keyboard, Stage Manager, and split view behavior.

**Rationale**: The painful product problem is user-perceived text entry. Unit
tests cannot fully prove iOS IME UX correctness.

**Alternatives considered**:

- XCTest only: useful but incomplete for keyboard/IME behavior.
- Delay IME checks until beta: rejected because this is the core differentiator.

## Open Technical Questions For Implementation

- What real-server compatibility matrix is required before beta for macOS,
  Linux, and Windows VNC servers?
- How should paste shortcut selection be represented for macOS, Windows, and
  Linux remotes before remote OS detection exists?
- Which iOS minimum version should be targeted for Stage Manager and modern
  keyboard behavior?

These questions should be closed during implementation planning before broad
coding begins.

## Implementation Review Update - 2026-04-29

**Decision**: Begin implementation with a testable Swift Package core
(`NaruRemoteCore`) before creating the iOS app target.

**Rationale**: The highest-risk product claims are data and protocol boundaries:
saved private profiles, staged diagnostics, local compose state, UTF-8 clipboard
payload intent, failed-send retention, diagnostic redaction, and session state.
Those can be tested faster in SwiftPM than in a simulator-first app shell.

**Evidence so far**:

- `swift test` passes 32 XCTest tests covering the core model, adapter layer,
  first RFB transcript decoding path, networked fake RFB serving, and app shell
  presentation state.
- `ConnectionProfileStore`, `ConnectionDiagnostics`, `DiagnosticExport`,
  `ComposeDraft`, `TextInjectionAdapter`, `RemoteSession`, and `RFBClient`
  boundary types exist under `NaruRemote/Sources/NaruRemoteCore/`.
- `NaruRemoteApp` exists as a SwiftUI package shell for profile list, session
  viewport, Remote Input Dock, and diagnostics summary views.
- `TestFixtures/FakeRFBServer/Fixtures/noauth-first-frame.hex` captures a
  deterministic RFB 3.8 no-auth transcript with server init and one framebuffer
  update header.
- `FakeRFBServer` serves that transcript over TCP and is covered by
  `FakeRFBServerIntegrationTests`.
- `RFBNetworkClient` connects to the fake server, parses the no-auth first-frame
  transcript, and updates `RFBClientBoundary` state plus last-frame metadata.
- `RFBNetworkClient` clears stale frame metadata when a later reconnect fails
  and rejects short transcripts with a typed `incompleteTranscript` error
  before fixed protocol slices are read.
- `NaruRemote.xcodeproj` is generated from `project.yml`; the iPad simulator
  build and one launch XCUITest pass.
- `NaruRemoteAppModel` now drives profile selection, profile creation,
  connection checks, the Connect action, and Remote Input Dock Send instead of
  relying only on a static launch snapshot.
- `ProfileEditorView` lets the app shell create MagicDNS/private profiles and
  choose the profile-level PiP Watch policy.
- `NaruRemoteApplication` now starts from app-local file-backed profile
  persistence instead of a hard-coded launch seed. UI tests inject an empty
  store path to keep first-run assertions deterministic.

**RFB/VNC implementation status**:

- Product implementation stance: borrow protocol and UX constraints from VNC
  viewers and Apple's PiP APIs, but keep the Naru renderer pipeline optimized
  around local composition, private-network sessions, dirty-region framebuffer
  updates, and watch-only PiP. External implementations are references, not the
  app architecture.
- Final MVP implementation choice: keep a first-party Swift RFB boundary and
  minimal client subset for MVP, using RFC 6143 as the protocol baseline and
  deterministic fake-server tests as the gate. This keeps the no-auth
  first-frame, state, diagnostics, and clipboard/text boundary under direct
  test control while the product thesis is still being proven.
- RoyalVNC remains the preferred post-MVP replacement/evaluation candidate
  because it is MIT-licensed, Swift-based, lists iOS/iPadOS compatibility,
  supports common authentication methods and bidirectional text clipboard
  redirection, and has richer encodings. It is not adopted for this MVP slice
  because the repository itself marks the iOS/iPadOS framebuffer view as a
  work in progress, and we still need to verify build integration, Unicode
  clipboard behavior, and focused-app paste confirmation against our own tests.
- LibVNCClient is not selected for the iOS MVP because it is a GPL-2.0 C
  library, which adds license and bridge complexity before Naru Remote has
  proven the local-composition input path.
- RFC 6143 remains the baseline protocol reference for the fake server and
  client boundary. The networked fake RFB executable and `RFBNetworkClient`
  now prove both the initial no-auth first-frame transcript over TCP and an
  interactive no-auth first-frame handshake that writes the client version,
  security selection, ClientInit, and framebuffer update request.
- Raw framebuffer decoding has started for the simplest compatible case:
  32-bit true-color raw rectangles are converted into an RGBA framebuffer model
  with typed failures for unsupported encodings, out-of-bounds rectangles, and
  incomplete payloads.
- `RFBNetworkClient` now has a no-auth session path that keeps the connection
  open and requests repeated raw framebuffer updates; the fake server verifies
  two sequential update requests and decoded RGBA output on the same connection.
- `RFBFramePump` adds the cancellable repeated request loop boundary: first
  request full frame, later requests incremental, with stop-by-limit,
  stop-by-callback, cancellation, and source-error propagation covered by unit
  tests.
- Raw incremental updates are now applied onto the previous local framebuffer.
  The update result carries dirty rectangles, changed pixel count, capture time,
  and derived change activity so the future Metal renderer can upload only
  changed regions and PiP can adapt FPS from real frame activity instead of a
  fixed timer.
- `NaruRemoteAppModel` now uses the streaming client path when available, runs
  a long-lived app frame task, updates `latestFramebuffer` as later frames
  arrive, and cancels stale streams plus framebuffer state when the profile
  changes.
- `RFBNetworkClient` now negotiates `VNC Authentication` security type 2 when a
  password is supplied, generates the bit-reversed DES challenge response, and
  has deterministic fake-server coverage for authenticated sessions,
  missing-password reporting, and rejected-password failures.
- The app profile flow now captures optional VNC passwords through a credential
  store, persists only `credentialRef` in profile metadata, and resolves the
  stored password before authenticated streaming connections. Full-rate app
  rendering, clipboard receive/restore, pointer events, and real-server
  credential verification remain blocked from compatibility claims until they
  have their own fixtures and app-layer/device verification.

**Clipboard compatibility risk**:

- MVP tests currently prove that Naru preserves a Unicode draft locally, encodes
  an RFB `ClientCutText` message with the UTF-8 byte length, writes the expected
  paste key-event sequence over the active fake-server connection, and reports
  the result as `unknown` when remote app acceptance cannot be confirmed.
- They do not yet prove that real macOS, Linux, or Windows VNC servers accept
  the clipboard payload, preserve Unicode normalization, or paste into the
  focused remote app. That requires the fake RFB fixture plus real-server
  compatibility checks.
- Remote clipboard restoration is explicitly marked `unsupported` in the first
  adapter implementation; restoration must become a separate capability after
  server support is known.

**PiP Watch Mode decision**:

- PiP Watch Mode is promoted from a distant experiment to a near-MVP
  differentiator because it makes Naru useful while the user is in another
  iPhone/iPad app. The product contract is watch-only: PiP shows the remote
  framebuffer and status, while remote input remains in the main app.
- The first implementation step is a platform-neutral state model and adaptive
  frame policy in `NaruRemoteCore`. The AVKit renderer remains an iOS app-layer
  boundary because Picture in Picture depends on Apple media APIs and App Store
  behavior.
- The foundation implementation gates PiP availability on profile policy,
  allowed session state, and a received remote frame. The app shell now wires
  the PiP action into the core `PiPWatchSession` lifecycle so the state can
  start, refresh stale frames, and stop from active frame metadata. This is
  still not the system PiP window until the AVKit renderer is implemented and
  verified on iOS/iPadOS.
- The likely renderer direction is `AVPictureInPictureController` with a custom
  player/source backed by remote frame sample buffers. The renderer should use
  the same composed framebuffer pipeline as the main viewport, downsample for
  PiP, and throttle by `idle`/`moderate`/`high` change activity. The
  implementation must verify this with real iOS/iPadOS behavior before claiming
  full PiP support.
- The first renderer boundary now exists in `NaruRemoteApp`: it converts
  `RFBRawFramebuffer` into 32-bit BGRA `CVPixelBuffer`, wraps it in ready
  `CMSampleBuffer` values, enqueues those frames on `AVSampleBufferDisplayLayer`,
  and provides an iOS-only `AVPictureInPictureController` content-source wrapper.
  The wrapper is now injected into `NaruRemoteAppModel`, which gates by device
  support, starts/stops the controller, and forwards initial/subsequent VNC
  framebuffers into the renderer while PiP Watch is active. This proves the
  app-layer media bridge compiles against the iOS SDK and is unit-tested, but it
  is not yet a physical-device PiP acceptance result.
- Remaining PiP risks are platform behavior, layer hosting, background-mode
  policy, battery/network throttling, and whether App Review expects explicit
  media/background justification for a remote desktop monitor.
- PiP must be user-initiated and must not log/export remote frames by default.

Sources:

- Apple AVPictureInPictureController:
  https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/
- Apple adopting Picture in Picture in a custom player:
  https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-custom-player
- Apple AVSampleBufferDisplayLayer:
  https://developer.apple.com/documentation/AVFoundation/AVSampleBufferDisplayLayer

**First-run onboarding decision**:

- Onboarding is a state-derived checklist, not a marketing landing page. It
  explains the next setup action for private target, diagnostics, local compose,
  and PiP Watch without blocking the app shell.
- The guide is generated from safe model state and intentionally does not accept
  `ComposeDraft.text`; app snapshot tests verify draft contents are not echoed.
- Diagnostic onboarding uses stage `safeTitle` only. Raw diagnostic detail,
  credential material, clipboard payloads, and framebuffer pixels remain outside
  onboarding content.
- Public endpoint profiles are surfaced as advanced/manual instead of being
  treated as the first-run happy path.

**Review remediation sync**:

- Diagnostic exports now omit stage details by default. Details are available
  only through an explicit safe stage catalog, not caller-provided raw
  diagnostic detail.
- Diagnostic exports now also omit raw next actions entirely, including in
  explicit detail mode.
- `TextInjectionAdapter` no longer treats successful paste-command emission as
  confirmed text insertion. The state remains `unknown` unless a future adapter
  can prove remote app acceptance.
- Generic thrown errors from the remote clipboard/paste client are mapped to
  stable safe messages instead of exposing localized system error descriptions.
- RFB framebuffer size now comes from `ServerInit`; framebuffer update
  rectangles are treated as update regions, not viewport dimensions.
- `ConnectionProfileStore` and in-memory profile persistence now use lock-based
  isolation for mutable state.
- App shell state now falls back to the first available profile if selection is
  stale and uses unique diagnostic row identifiers for repeated stages.
- `ConnectionProfile` now includes a profile-level PiP opt-out that defaults to
  enabled for legacy decoded profiles.
- `PiPWatchSession` rejects unprepared frame display, zero-size frame metadata,
  frame-less active sessions, and profile policy opt-out with user-safe states.
- The installable app shell now wires profile selection, Add Profile, Checks,
  Connect, and Send into `NaruRemoteAppModel`; real connection support is still
  limited to the MVP no-auth first-frame path.

**Sources**:

- RFC 6143, The Remote Framebuffer Protocol:
  https://www.rfc-editor.org/rfc/rfc6143
- RoyalVNC Swift RFB/VNC implementation:
  https://github.com/royalapplications/royalvnc
- LibVNCServer/LibVNCClient:
  https://github.com/LibVNC/libvncserver
- Spec Kit documentation:
  https://github.github.com/spec-kit/index.html
