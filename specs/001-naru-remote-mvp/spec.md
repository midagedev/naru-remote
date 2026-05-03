# Feature Specification: Naru Remote MVP

**Feature Branch**: `001-naru-remote-mvp`  
**Created**: 2026-04-29  
**Status**: Draft  
**Product**: Naru Remote  
**Input**: Product direction from `PRODUCT_SPEC.md`, branding decision `Naru Remote`, and spec-driven setup request.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Connect To A Private VNC Host (Priority: P1)

A developer or power user opens Naru Remote on iPad, enters a MagicDNS hostname
or private host address, saves it as a profile, and reaches a VNC server without
needing to remember raw connection details later.

**Why this priority**: Without a reliable private connection path, none of the
input bridge features can be verified in a real session.

**Independent Test**: Configure a local or tailnet-reachable fake/real VNC host,
create a profile, run connection diagnostics, and confirm that Naru Remote reaches
the VNC handshake stage or reports the exact blocked stage.

**Acceptance Scenarios**:

1. **Given** Tailscale is connected and a MagicDNS hostname resolves, **When**
   the user creates a VNC profile and taps Connect, **Then** Naru Remote attempts
   DNS, TCP, and VNC handshake checks in order and shows progress.
2. **Given** the hostname cannot resolve, **When** the user taps Connect,
   **Then** Naru Remote stops before TCP and shows a MagicDNS/DNS failure with
   a suggested next action.
3. **Given** TCP succeeds but the VNC handshake fails, **When** diagnostics
   finish, **Then** Naru Remote reports that the host is reachable but the VNC
   service is not available or incompatible.

---

### User Story 2 - View A Remote Session Safely (Priority: P1)

After a successful VNC handshake, the user sees the remote screen in a full
iPad-first session view with basic pan/zoom and a compact connection HUD.

**Why this priority**: Compose & Send needs a real target focus area and visible
feedback from the remote session.

**Independent Test**: Connect to a fixture VNC server that displays known test
content and verify the session viewport renders the expected frame and stays
responsive to pan/zoom.

**Acceptance Scenarios**:

1. **Given** a profile can complete VNC authentication, **When** the session
   opens, **Then** the remote frame is visible full-bleed with a compact HUD.
2. **Given** the connection drops during an active session, **When** Naru Remote
   detects the drop, **Then** the session shows a reconnect/error state without
   losing the saved profile.
3. **Given** the user switches iPad orientation, **When** the session resizes,
   **Then** the viewport preserves remote aspect ratio and controls remain usable.

---

### User Story 3 - Compose And Send Multilingual Text (Priority: P1)

The user clicks a text field in the remote session, writes a complete Korean or
mixed-language sentence in the local compose surface, reviews it, and sends the
finished text to the remote computer without relying on per-key IME events.

**Why this priority**: This is the main product differentiation against normal
mobile VNC viewers.

**Independent Test**: With a remote text target focused, compose a sentence such
as `한글과 English 😊를 같이 입력합니다`, send it, and verify the remote app receives
the same Unicode string or a precise failure reason.

**Acceptance Scenarios**:

1. **Given** a remote text field is focused, **When** the user enters a sentence
   in the local compose bar and taps Send, **Then** Naru Remote sends the final
   string using VNC clipboard paste mode and displays whether the result is
   confirmed, failed, or unknown.
2. **Given** the remote paste shortcut fails or focus is lost, **When** Send is
   attempted, **Then** Naru Remote shows a recoverable failure and keeps the
   composed text locally.
3. **Given** the remote clipboard must be changed to paste text, **When** sending
   completes, **Then** Naru Remote indicates whether clipboard restore was
   attempted, succeeded, failed, or unsupported.

---

### User Story 4 - Understand Why Input Or Connection Failed (Priority: P2)

When connection or text sending fails, the user sees a short diagnostic path
instead of a generic error.

**Why this priority**: Early VNC/Tailnet/clipboard compatibility will vary by
remote OS and server. Clear diagnostics are necessary for beta feedback.

**Independent Test**: Run fixture failures for DNS, TCP, VNC handshake, auth,
clipboard unavailable, and paste blocked, then verify each produces a distinct
user-facing state.

**Acceptance Scenarios**:

1. **Given** a failure occurs in a known stage, **When** diagnostics are shown,
   **Then** the user can see the failed stage, likely cause, and next action.
2. **Given** a beta tester exports a diagnostic summary, **When** the summary is
   generated, **Then** it excludes composed user text and sensitive credentials.

---

### User Story 5 - Monitor A Session In PiP Watch Mode (Priority: P2)

The user starts a watch-only Picture in Picture monitor for a remote session,
switches to another iPhone/iPad app, and keeps a small live view of the remote
desktop visible until they tap it to return to Naru Remote.

**Why this priority**: PiP Watch Mode is a visible product differentiator for
agent work, long-running builds, installs, tests, and remote server monitoring.
It should not block the first connection/text MVP, but it should be designed
early because it changes session state, frame rendering, privacy, and resource
policy.

**Independent Test**: Start PiP Watch Mode from a frame-bearing active,
degraded, or reconnecting session and verify that local remote input is
disabled for the PiP surface, the watch state is represented distinctly from
active control, and stale/unsupported states produce user-safe messages.

**Acceptance Scenarios**:

1. **Given** a remote session has a frame stream, **When** the user starts PiP
   Watch Mode, **Then** Naru Remote creates a watch-only monitor for that
   session and keeps normal remote control in the main app.
2. **Given** the user leaves Naru Remote while PiP Watch Mode is active, **When**
   the PiP window remains visible, **Then** it shows remote frames or a stale
   frame state without accepting pointer, keyboard, clipboard, or Compose & Send
   input from the PiP surface.
3. **Given** PiP is unsupported, blocked, or the frame stream stalls, **When**
   the user tries to start or continue watching, **Then** Naru Remote shows a
   recoverable status and keeps the main session available.

---

### User Story 6 - Reach Profile Entry On First Launch Without Guidance (Priority: P1)

A new user opens Naru Remote, sees an empty home with a single primary
"add a computer" call-to-action, taps it to enter a host (MagicDNS or private
IP) plus optional credential, and is ready to connect.  The app must not
pre-announce features the user has not asked about (PiP Watch, compose path,
diagnostics tour).

**Why this priority**: The first action a user wants is to connect to their
computer.  An up-front feature checklist that previews capabilities (PiP,
compose, diagnostics readiness) before the user has even saved a profile is
noise that delays the only path that matters at first launch.  Features become
discoverable when the user actually reaches them.

**Independent Test**: Launch the app shell with zero profiles and verify that
the empty home shows exactly one primary CTA leading to the profile editor;
launch with one or more saved profiles and verify the empty-state CTA is gone.

**Acceptance Scenarios**:

1. **Given** no profile exists, **When** the app launches, **Then** the home
   surface shows a single "add a computer" primary action and does not render
   any feature checklist, capability preview, or status row.
2. **Given** the user taps the empty-state CTA, **When** the profile editor
   appears, **Then** the host field is the focused entry point so the user can
   start typing immediately.
3. **Given** at least one profile exists, **When** the app launches, **Then**
   the empty-state CTA is hidden and the home surface goes straight to the
   profile list and session viewport.
4. **Given** a connection attempt fails, **When** diagnostics render, **Then**
   the failed stage shows safe-catalog detail without echoing composed text or
   credentials (covered by US 1's diagnostic privacy scenario).

### Edge Cases

- Tailscale is installed but disconnected.
- MagicDNS is disabled or hostnames do not resolve.
- VNC server accepts TCP but speaks an unsupported RFB/security variant.
- Authentication fails repeatedly.
- Remote OS uses a different paste shortcut or blocks paste into the focused app.
- Remote clipboard supports text but not UTF-8 correctly.
- Local composed text contains Korean, Japanese, Chinese, emoji, newline, tab,
  and combining marks.
- iPad orientation, Stage Manager, split view, and external keyboard change the
  available viewport.
- The user leaves and returns to the app during an active connection attempt.
- A sensitive profile has PiP Watch Mode disabled even when the session is active
  and has received frames.
- No saved profile exists yet — the first-launch home must offer one direct
  path to profile entry without implying public-internet setup or pre-listing
  feature capabilities.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow users to create, edit, delete, and select saved
  private VNC profiles with name, host, port, and optional username metadata.
- **FR-002**: System MUST accept MagicDNS hostnames and private IP/host:port
  entries without requiring public IP addresses.
- **FR-003**: System MUST run staged diagnostics for DNS/MagicDNS, TCP reachability,
  VNC handshake, authentication, and clipboard capability when applicable.
- **FR-004**: System MUST open a VNC session view after successful connection and
  render remote frames in an iPad-first full-bleed viewport.
- **FR-005**: System MUST provide a keyboard-adjacent local compose surface that
  accepts iOS/iPadOS multilingual text input before sending the finished string.
- **FR-006**: System MUST send composed text through VNC clipboard paste mode for
  MVP.
- **FR-007**: System MUST preserve local composed text when send fails.
- **FR-008**: System MUST display the actual send path and confidence, such as
  `Paste command sent; remote app confirmation unavailable` or
  `Paste blocked by remote app`.
- **FR-009**: System MUST avoid storing composed text in diagnostic exports by
  default.
- **FR-010**: System MUST keep host helper, voice compose, image paste, file drop,
  and agent handoff outside the MVP implementation scope except as documented
  extension points.
- **FR-011**: System MUST model PiP Watch Mode separately from interactive
  remote control.
- **FR-012**: System MUST keep PiP watch surfaces view-only; pointer, keyboard,
  clipboard, and Compose & Send actions MUST remain in the main app.
- **FR-013**: System MUST expose user-safe PiP states such as unavailable,
  preparing, watching, stale, failed, and stopped.
- **FR-014**: System MUST enforce profile-level PiP Watch opt-out before
  enabling any PiP start action.
- **FR-015**: When zero profiles exist, the home surface MUST present exactly
  one primary action — entry into the profile editor — and MUST NOT render a
  feature checklist, capability preview, or staged setup tour.  When at least
  one profile exists, the empty-state action MUST be hidden.
- **FR-016**: First-launch surfaces MUST NOT display composed text, credentials,
  raw clipboard payloads, or framebuffer contents.  Diagnostic detail rendered
  after a connect attempt comes from the safe catalog (FR-008).
- **FR-017**: Public endpoint setup remains advanced/manual; the first-launch
  empty-state CTA MUST NOT route users into a public-IP entry path or imply
  that public IPs are the expected default (constitution §II).

### Naru Input Requirements *(mandatory if feature handles input)*

- **IN-001**: Local composition path: local iOS/iPadOS text field in the Remote
  Input Dock, pinned to the bottom safe area so it sits directly above the
  keyboard while composing.
- **IN-002**: Remote injection behavior: set remote VNC clipboard to UTF-8 text
  and send the remote OS paste command for the active target.
- **IN-003**: Fallback behavior: if paste cannot be confirmed, keep local text
  and show a recoverable error; key-event fallback is not a silent default.
- **IN-004**: Clipboard impact: temporary remote clipboard use; restore is
  attempted only when server capabilities and implementation support it.
- **IN-005**: User confirmation: user explicitly taps Send after reviewing text.

### Tailnet / Connection Requirements *(mandatory if feature touches connection)*

- **TN-001**: Private-network assumption: MagicDNS hostname or private host:port
  is the normal path; public endpoints are manual advanced input only.
- **TN-002**: Diagnostics shown to user: DNS/MagicDNS, TCP reachability, VNC
  handshake, auth, frame receive, clipboard text.
- **TN-003**: Public internet posture: not encouraged in MVP copy and never
  presented as the primary setup.

### Security & Privacy Requirements *(mandatory)*

- **SP-001**: Data crossing the local/remote boundary: host/port, VNC credential
  material, composed text, pointer/keyboard events, framebuffer data, clipboard
  status.
- **SP-002**: Data retained on device: saved profile metadata and user-approved
  credentials; credential storage MUST use platform secure storage when
  implemented.
- **SP-003**: Data retained on helper/remote host: none for MVP because helper is
  out of scope.
- **SP-004**: Sensitive actions needing approval: saving credentials and sending
  composed text.
- **SP-005**: Logging rule: logs and diagnostic exports MUST NOT include composed
  text, credentials, or framebuffer screenshots by default.
- **SP-006**: PiP privacy rule: PiP Watch Mode MUST be user-initiated, must not
  log or export remote frames, and must provide an opt-out path for sensitive
  profiles.

### Key Entities

- **ConnectionProfile**: User-saved VNC target with display name, host, port,
  optional username, last connection status, favorite/recent metadata, and
  profile-level PiP Watch permission.
- **ConnectionDiagnosticRun**: Ordered result of DNS, TCP, handshake, auth, frame,
  and clipboard checks with timestamps and user-safe messages.
- **RemoteSession**: Active VNC session state, selected profile, connection HUD
  state, framebuffer status, and reconnect state.
- **ComposeDraft**: Local unsent text, send status, selected injection path, and
  last failure reason.
- **PiPWatchSession**: Watch-only monitor state for one remote session, including
  availability, stale-frame state, and whether local remote input is disabled.
- **PiPFrameSnapshot**: Metadata for the latest frame offered to PiP rendering,
  including size, timestamp, and change activity without storing screenshots in
  logs or diagnostic exports.
- **EmptyHome**: View-level state for the first-launch surface — `.empty`
  (zero saved profiles → one CTA into the profile editor) or `.populated`
  (≥ 1 saved profile → no first-launch chrome).  No persisted "dismissed"
  flag; visibility is derived purely from `profiles.isEmpty`.

## Acceptance Test Matrix *(mandatory)*

| Scenario | Verification Type | Required Evidence |
| --- | --- | --- |
| Save MagicDNS/private VNC profile | XCTest | Passing profile persistence test |
| DNS failure before TCP | Unit/integration fixture | Diagnostic stage reports DNS failure |
| TCP reachable but no VNC | Fake server integration | Diagnostic stage reports handshake failure |
| Successful RFB handshake and first frame | Fake RFB server integration | Known fixture frame renders or frame event captured |
| Compose Korean/English/emoji string | XCTest plus manual device check | Exact Unicode string preserved locally and clipboard/paste command path requested |
| Paste blocked/focus lost | Fake/session fixture or manual remote app check | Local text retained and recoverable error shown |
| Diagnostic export privacy | Unit test | Export excludes credentials and composed text |
| PiP watch-only state | Unit/UI test | PiP state disables remote input and reports stale/unsupported states safely |
| PiP sensitive profile opt-out | Unit/UI test | Profile-level opt-out prevents PiP availability and shows a safe status |
| First-launch empty home | Unit/UI test | Zero profiles → one CTA into profile editor, no checklist or feature preview; ≥ 1 profile → CTA hidden |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A tester can create a private VNC profile and identify the failed
  connection stage within 30 seconds.
- **SC-002**: For a compatible VNC server fixture, the app completes handshake
  and receives the first frame without crashing.
- **SC-003**: A multilingual string containing Korean, ASCII, emoji, newline, and
  punctuation is preserved exactly through local compose state.
- **SC-004**: A failed or unconfirmed send never clears the local draft.
- **SC-005**: Diagnostic export contains no composed text or credential material.
- **SC-006**: A sensitive profile can disable PiP Watch Mode, and the app does
  not enable a PiP start action for that profile.
- **SC-007**: First launch with zero profiles surfaces exactly one primary
  action (profile editor entry) and does not render any feature checklist,
  capability preview, or staged setup tour.

## Assumptions

- Users already have Tailscale or another private network configured outside
  Naru Remote.
- MVP can start with manual host entry plus saved profiles before Tailscale API
  inventory.
- MVP may use a fake RFB server for automated verification before broad remote
  server compatibility is proven.
- Clipboard restore may be partial in MVP and must be reported honestly.

## Current Implementation Boundary

- The app shell has a model-driven profile list, Add Profile sheet, Checks
  action, Connect action wired to the RFB first-frame boundary, and Send action
  wired to the active RFB text client when a connection exists.
- The installable app starts from app-local saved profiles in Application
  Support instead of a hard-coded demo profile.  With no saved profiles, the
  home surface renders an empty state with one primary "add a computer" CTA
  (FR-015) and no feature checklist or capability preview.
- Automated RFB compatibility currently proves an interactive RFB 3.8 no-auth
  first-frame handshake against the fake server and captures framebuffer
  metadata. The same fake-server path verifies outgoing UTF-8 `ClientCutText`
  and paste key-event writes. `RFBNetworkClient` can keep a no-auth session
  open, request repeated raw framebuffer updates on the same connection, and
  decode 32-bit true-color raw rectangles into RGBA pixels. It can also
  negotiate `VNC Authentication` security type 2 when a password is supplied,
  generate the challenge response, and report missing or rejected passwords
  without preserving stale session state. Profile creation captures an optional
  VNC password through a credential store, persists only `credentialRef` in
  profile metadata, and resolves the password before authenticated streaming
  connections. `RFBFramePump` provides the cancellable loop boundary. The app
  model runs a long-lived frame task for streaming-capable connectors, keeps
  later frames flowing into `latestFramebuffer`, composites incremental raw
  updates onto the previous framebuffer, preserves dirty rectangles and changed
  pixel counts through the frame pump, cancels stale streams on profile changes,
  and exposes the sampled SwiftUI viewport preview. Full-rate Metal rendering,
  clipboard restore/receive, broader pointer/keyboard events, and real-device
  credential verification are still future implementation work.
- PiP Watch Mode currently has core state, policy, and an app-shell start/stop
  lifecycle wired to frame-bearing sessions. The core watch state uses frame
  change activity from the VNC pipeline for idle/moderate/high policy decisions.
  The app layer now includes a sample-buffer renderer boundary and an iOS
  `AVPictureInPictureController` content-source wrapper. The iOS app injects
  that wrapper into the app model, and the model now starts/stops the controller
  and forwards initial/subsequent framebuffers when PiP is active. It is not
  full system PiP support until real iPhone/iPad behavior, background-mode
  policy, and user-visible start/stop flow are verified.
- Multi-session, session parking, multi-view, and PiP-plus-multiple-live-session
  behavior are not part of this MVP spec and need a dedicated follow-up spec.

## Non-Goals

- Tailscale VPN embedding or replacement.
- Tailscale API inventory.
- Direct Keystroke Streaming Mode (peer input mode to Compose & Send;
  documented at `PRODUCT_SPEC.md` §6.3.6 and tracked in `ROADMAP.md` Phase 9).
- Voice Compose.
- Image Paste Bridge.
- File Drop.
- macOS Naru Helper.
- Agent Handoff.
- Interactive control inside the PiP window.
- Indefinite background execution without user-visible PiP.
- RDP/SSH/NoMachine support.
- Public internet remote desktop setup wizard.
