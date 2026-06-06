# Feature Specification: Host Helper Video Stream

**Feature Branch**: `007-host-helper-video-stream`  
**Created**: 2026-06-06  
**Status**: Draft  
**Product**: Naru Remote  
**Input**: Continue the sustained iPhone VNC performance work after the live
request-pipeline benchmark showed that extra RFB requests do not reduce the
remaining first-byte or startup-payload bottleneck.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Watch A Sustained Mac Session Through A Helper Video Stream (Priority: P1)

An iPhone user connects to their own Mac on a private network and chooses an
experimental "helper video" stream for a sustained terminal or AI CLI session.
VNC remains connected for pointer, keyboard, clipboard, diagnostics, reconnect,
and fallback. The visible framebuffer comes from an optional paired Mac helper
that captures the desktop and sends a low-latency compressed video stream to
the iPhone.

**Why this priority**: The current VNC path has been optimized through
encodings, RGB565, viewport regions, first-visible startup slices, and request
pacing. The latest live benchmark shows request pipelining does not improve the
dominant server first-byte wait, and startup is still payload-read constrained.
The next practical step is a helper-side screen stream that changes the screen
representation rather than sending more RFB requests.

**Independent Test**: A fake helper video server sends a short catalog-labeled
H.264 access-unit stream to the app transport; the app accepts safe stream
metadata, starts the helper-video render path, keeps VNC control state active,
and records only fixed status labels in diagnostics.

**Acceptance Scenarios**:

1. **Given** an active VNC session and a paired reachable video-capable helper,
   **When** the user enables helper video for the next connection, **Then**
   Naru uses helper video for visual frames and keeps VNC available for control
   and fallback.
2. **Given** helper video is active, **When** the helper stream stalls or
   becomes unhealthy, **Then** Naru returns to the VNC framebuffer without
   dropping the session or losing the local Compose draft.
3. **Given** helper video is active on iPhone, **When** diagnostics are
   exported, **Then** the report includes only fixed helper-video state,
   codec/profile, quality bucket, and failure labels, with no pixels,
   coordinates, byte counts, host identity, endpoints, tokens, or exact
   timings.

---

### User Story 2 - Prove It Beats The VNC Poor-Network Gate Before Promotion (Priority: P2)

A developer running the benchmark harness can compare the existing VNC
low-traffic path against helper video under the same constrained-cellular
profile. The result explains whether helper video improves first useful paint,
sustained content update rate, thermal pressure proxy, and traffic pressure
without weakening privacy.

**Why this priority**: A helper stream is a larger trust and implementation
boundary than VNC-only tuning. It must earn promotion through the same
benchmark-first, physical-iPhone-second contract already used by
`specs/004-rfb-encodings`.

**Independent Test**: `VNCLiveBenchmark` gains a helper-video transport shape
that can run against a fake stream source and produce schema-safe aggregate
results without exporting bytes, pixels, coordinates, endpoints, or exact
helper timing samples.

**Acceptance Scenarios**:

1. **Given** a helper-video benchmark run, **When** the report is rendered,
   **Then** it includes fixed transport labels and aggregate bands for startup,
   sustained update health, decode/render pressure, and fallback count.
2. **Given** helper video fails to meet a poor-network target, **When** the
   benchmark gate evaluates the run, **Then** the gate reports fixed issue
   codes and keeps product defaults unchanged.

---

### User Story 3 - Keep Helper Video Optional, Revocable, And Private-Network Only (Priority: P3)

A user who does not install or enable the helper still gets the existing VNC
viewer. A user who does enable helper video can revoke it, see permission
state, and keep the helper off public internet paths.

**Why this priority**: Screen capture and video streaming cross a stronger
privacy boundary than VNC viewing alone. Constitution principle IV requires
optional, observable, revocable helper behavior.

**Independent Test**: Helper video capability state and revocation state are
modeled as fixed catalog values; disabling or revoking helper video prevents
stream attempts while leaving VNC connect/view/control tests green.

**Acceptance Scenarios**:

1. **Given** helper video is disabled, revoked, or missing screen-recording
   permission, **When** the user connects, **Then** Naru uses the existing VNC
   visual path and explains helper-video unavailability with a fixed state.
2. **Given** a profile uses a public host classification, **When** helper video
   is configured, **Then** the app refuses helper-video transport unless a
   future security review explicitly adds an advanced public mode.

### Edge Cases

- The helper has Screen Recording permission revoked during a session.
- The Mac display resolution changes while helper video is active.
- The helper stream loses parameter sets, emits an unsupported codec, or the
  iPhone decoder rejects a sample.
- VNC remains connected but helper video stalls, reconnects, or sends an
  end-of-stream marker.
- The user enters PiP Watch while helper video is active.
- The remote screen contains sensitive content; logs and diagnostics must not
  capture frames, thumbnails, coordinates, endpoints, byte counts, or raw
  timing samples.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST model helper video as a distinct visual transport
  from the existing RFB framebuffer path.
- **FR-002**: System MUST keep VNC connected for control, input, clipboard,
  diagnostics, reconnect, and fallback while helper video is active.
- **FR-003**: User MUST be able to enable helper video only as an opt-in
  per-profile or per-session candidate; the default visual transport remains
  VNC until benchmark and physical gates pass.
- **FR-004**: System MUST fall back to the VNC framebuffer when helper video is
  disabled, unavailable, permission-blocked, unhealthy, or revoked.
- **FR-005**: System MUST model helper video capability, permission,
  codec/profile, stream health, and fixed failure codes without exposing raw
  endpoints, tokens, host names, frame content, byte counts, coordinates, or
  exact timing samples.
- **FR-006**: Helper video benchmark reports MUST compare VNC and helper-video
  candidates using fixed labels, aggregate bands, and permille-style privacy
  proxies only.
- **FR-007**: System MUST preserve no-helper VNC viewing, Compose & Send,
  Direct mode, pointer control, diagnostics, and PiP Watch behavior.
- **FR-008**: Helper video transport MUST be authenticated and scoped to saved
  private profiles. Public internet exposure is out of scope.
- **FR-009**: The first helper-video codec candidate SHOULD be H.264 using
  platform hardware encode/decode where available, with HEVC or AV1 considered
  later only after compatibility review.
- **FR-010**: Product promotion MUST require benchmark-green evidence and
  physical iPhone evidence for startup readability, sustained smoothness,
  Compose reliability, fallback behavior, and thermal comfort.

### Naru Input Requirements *(mandatory if feature handles input)*

- **IN-001**: Local composition path: unchanged. Text, voice, image, and file
  composition stay on iPhone/iPad.
- **IN-002**: Remote injection behavior: unchanged. Helper video does not carry
  user text, key events, clipboard contents, files, or agent actions.
- **IN-003**: Fallback behavior: VNC remains the authoritative control and
  input path; helper video is visual-only.
- **IN-004**: Clipboard impact: none. Helper video must not read or write
  local or remote pasteboards.
- **IN-005**: User confirmation: enabling helper video is explicit; no hidden
  upgrade from VNC to helper video.

### Tailnet / Connection Requirements

- **TN-001**: Helper video is private-network first and scoped to saved
  profiles with private host classification.
- **TN-002**: Reachability and failure diagnostics use fixed labels such as
  `notConfigured`, `permissionMissing`, `codecUnsupported`, `streamStalled`,
  `authFailed`, and `revoked`.
- **TN-003**: The app must not imply official Tailscale affiliation and must
  not encourage opening helper-video ports to the public internet.

### Security & Privacy Requirements *(mandatory)*

- **SP-001**: Data crossing helper to app: encoded screen frames, fixed stream
  metadata, fixed status labels, and authenticated transport framing.
- **SP-002**: Data retained on device: helper-video enabled state, safe fixed
  capability labels, pairing fingerprint, and last fixed failure code. Encoded
  frames and decoded frames are in-memory only.
- **SP-003**: Data retained on helper: pairing metadata, fixed recent status,
  and no raw screen frames by default.
- **SP-004**: Sensitive actions needing approval: helper pairing, helper-video
  enable/disable, helper revocation, and any future recording or file output.
- **SP-005**: Logs and diagnostics MUST NOT include raw screen frames,
  screenshots, thumbnails, frame hashes, coordinates, display dimensions, byte
  counts, endpoint addresses, auth tokens, host names, passwords, exact
  per-frame timings, Compose text, clipboard contents, or raw OS errors.
- **SP-006**: The helper MUST request only the screen-capture and networking
  permissions needed for this feature; text insertion permissions from
  `006-host-helper-text-bridge` are not required for video-only use.

### Key Entities

- **HelperVideoProfileState**: Per-profile opt-in and availability state,
  including enabled flag, pairing fingerprint, permission catalog, codec
  support catalog, stream health catalog, and last safe failure code.
- **HelperVideoStreamDescriptor**: Safe negotiated stream metadata, including
  codec label, profile label, color-space label, max frame-rate bucket,
  quality bucket, and feature flags. No dimensions, endpoints, or byte counts.
- **HelperVideoAccessUnit**: One encoded video unit plus fixed sequence state
  needed by the decoder. Payload stays process-local and is never logged.
- **HelperVideoBenchmarkReport**: Aggregate benchmark output for helper video,
  using fixed labels, startup bands, sustained update bands, decode/render
  pressure labels, fallback counts, and no raw content or byte counters.

## Acceptance Test Matrix *(mandatory)*

Per constitution principle VI, iPhone evidence appears before iPad evidence.

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| Helper video state models opt-in, permission, revocation, and fallback labels | Unit | iPhone simulator | `swift test --filter HelperVideo` |
| Fake helper stream can start visual path while VNC control remains active | XCTest + fake helper | iPhone simulator | app-model test proving visual transport state and VNC control state coexist |
| Diagnostics omit frames, dimensions, endpoints, byte counts, exact timings, and tokens | Unit | iPhone simulator / N/A | diagnostic JSON assertions |
| Helper-video benchmark schema emits only fixed labels and aggregate bands | Unit | iPhone simulator / N/A | benchmark report fixture test |
| macOS helper captures screen through ScreenCaptureKit and encodes H.264 | Helper integration | physical Mac | redacted helper integration log |
| iPhone decodes helper video and falls back to VNC after stream stall | Manual device | physical iPhone + Mac | redacted manual log and screenshot/recording notes with no captured frame artifacts committed |
| PiP Watch uses the active visual source without sending input | UI/manual | physical iPhone first, iPad graceful | PiP enter/exit checklist |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Helper video reaches first useful paint faster than the current
  VNC low-traffic candidate under the constrained-cellular app-low-traffic
  benchmark, without leaking unsafe data in reports.
- **SC-002**: Helper video sustains readable terminal/AI CLI updates on a
  physical iPhone for a 30 minute session with lower thermal discomfort than
  the current VNC candidate.
- **SC-003**: Helper video stream stall, permission loss, codec rejection, and
  auth failure all fall back to VNC or safe failure with fixed catalog states.
- **SC-004**: No-helper VNC behavior remains unchanged and fully testable.
- **SC-005**: Diagnostics and benchmark artifacts pass privacy tests for frame
  content, coordinates, dimensions, endpoints, tokens, byte counts, and exact
  per-frame timings.

## Assumptions

- The first helper target is macOS because the current live target is Apple
  Screen Sharing to a Mac.
- VNC remains installed and connected; helper video augments the visual stream
  but does not replace control/input in the first milestone.
- The first codec candidate is H.264 because iPhone/iPad/macOS hardware paths
  and app rendering APIs are broadly available.
- Physical iPhone evidence is required before default promotion.

## Non-Goals

- Replacing VNC control/input with a full custom remote desktop protocol.
- Public internet helper exposure.
- Remote audio, microphone, file transfer, image paste, agent automation, or
  screen recording output files.
- Shipping helper video as a production default in the first implementation
  PR.
