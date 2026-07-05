# Feature Specification: Apple Remote Desktop Native Support Strategy

**Feature Branch**: `008-apple-remote-desktop-native-support`
**Created**: 2026-06-17
**Status**: Partially implemented (reconciled 2026-07-05 — MacSessionControl landed; open: diagnostics-catalog integration T011–T012, helper action docs T016, transport labels/benchmark evidence T019–T020, quickstart checks).
**Product**: Naru Remote
**Input**: User description: "Can we add more support for Apple Remote Desktop native features?"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Connect To Macs With Apple-Aware Guidance (Priority: P1)

An iPhone user wants to connect to their own Mac that has Apple Remote Desktop
or macOS Remote Management enabled. Naru should make this feel like a Mac-aware
profile instead of a generic host:port VNC entry by using correct default ports,
safe setup hints, extra-display port hints, and diagnostics that distinguish
VNC-compatible Screen Sharing from deeper Apple Remote Desktop administration.

**Why this priority**: This is the lowest-risk ARD improvement. Apple's public
documentation confirms that non-Apple VNC viewers can control Remote Desktop
clients when allowed, but VNC access does not grant the broader Remote Desktop
administrator privileges. Naru can improve setup and diagnostics without
claiming a private Apple protocol implementation.

**Independent Test**: A profile model test classifies an Apple Screen Sharing
profile, shows port `5900` as the default control/observe path, offers
additional-display ports `5901` and `5902`, and emits fixed diagnostics when
TCP is reachable but VNC auth, first frame, or helper capability fails.

**Acceptance Scenarios**:

1. **Given** a user creates an Apple Screen Sharing profile, **When** they leave
   the port blank, **Then** Naru uses TCP `5900` and labels the profile as
   VNC-compatible Apple Screen Sharing, not full ARD administration.
2. **Given** a Mac has multiple VNC display ports, **When** the user opens
   display options, **Then** Naru can suggest `5901` and `5902` as fixed
   additional-display candidates without exposing host identity in logs.
3. **Given** a connection fails, **When** diagnostics are exported, **Then** the
   report uses fixed labels such as `tcp.closed`, `vnc.authFailed`,
   `firstFrame.timedOut`, `appleRemoteManagement.vncViewerNotAllowed`, or
   `appleRemoteManagement.adminPrivilegesNotAvailable`.

---

### User Story 2 - Offer Helper-Backed ARD-Class Actions Safely (Priority: P2)

A user with the optional Naru Helper paired to their Mac wants ARD-like
convenience actions from the iPhone session: wake/keep-awake status, safe
system status, file staging, user message, and tightly approved restart/log out
or lock-screen actions. These actions must be explicit, observable, and
revocable.

**Why this priority**: Apple Remote Desktop includes management features such
as copy files, system status, messages, lock/unlock, sleep/wake/restart, and
remote UNIX commands. The public VNC path cannot provide these. Naru can support
the subset that aligns with its optional helper model and private-network
posture.

**Independent Test**: A fake helper advertises a fixed ARD-class capability
catalog. The app renders only actions allowed by the current profile, helper
permission state, and user approval policy. Dangerous actions remain disabled
until confirmed.

**Acceptance Scenarios**:

1. **Given** a paired Mac helper advertises `systemStatus`, **When** a session
   is active, **Then** Naru can show CPU, memory, and storage buckets without
   logging process lists, file paths, usernames, or exact raw values.
2. **Given** a paired helper advertises `messageUser`, **When** the user sends a
   one-way message, **Then** the helper displays the message locally on the Mac
   and the app records only a fixed delivery status.
3. **Given** a user taps restart, log out, sleep, or lock, **When** the action
   is destructive or may interrupt work, **Then** Naru requires explicit
   confirmation and records a redacted action timeline entry.

---

### User Story 3 - Treat High Performance Screen Sharing As A Distinct Research Path (Priority: P3)

A power user asks why Naru cannot simply use Apple Remote Desktop High
Performance screen sharing. Naru should explain support accurately, diagnose
readiness where possible, and avoid promising private Apple protocol behavior
that the app cannot implement safely.

**Why this priority**: Apple's High Performance screen sharing is compelling
for responsiveness, audio, high frame rates, and high-fidelity color, but it is
not a drop-in VNC optimization. It has Apple Silicon, macOS version, UDP port,
bandwidth, and session-count requirements and no public iOS client API for Naru
to call directly.

**Independent Test**: A support catalog test classifies High Performance screen
sharing as `researchOnly`, reports fixed readiness blockers, and routes the
product path to Naru Helper Video unless a future public API or licensed
protocol path exists.

**Acceptance Scenarios**:

1. **Given** a Mac profile is marked Apple Screen Sharing, **When** the user
   opens advanced visual transport options, **Then** High Performance screen
   sharing appears as "not directly supported" with fixed reasons rather than a
   selectable broken mode.
2. **Given** helper video is available, **When** the user wants smoother visual
   transport, **Then** Naru recommends helper video as the product-owned
   high-performance path and keeps VNC for control/fallback.

---

### User Story 4 - Use Mac-Native Session Controls From iPhone (Priority: P2)

An iPhone user connected to their Mac expects the session controls they see in
Apple-oriented remote desktop clients: Mission Control, front-app windows,
app switching, desktop reveal, and Space navigation. Naru should expose these
as compact session buttons without requiring Direct mode or a physical
keyboard.

**Why this priority**: These controls make a small iPhone screen practical for
real Mac use. They do not require private Apple Remote Desktop protocols: they
can ride the existing VNC `KeyEvent` path as documented macOS keyboard
shortcuts.

**Independent Test**: A pure model test maps each Mac session control to a
fixed X11 keysym and modifier set, and an app render-state test shows the strip
only for active sessions.

**Acceptance Scenarios**:

1. **Given** an active Mac VNC session, **When** the user taps Mission Control,
   **Then** Naru emits Control-Up Arrow through the existing key-event queue.
2. **Given** an active Mac VNC session, **When** the user taps App Windows,
   Switch App, Desktop, Space Left, or Space Right, **Then** Naru emits only
   the corresponding fixed keyboard shortcut and does not modify the Compose
   draft or sticky Direct modifiers.
3. **Given** no active session or the VNC wire is not ready, **When** the user
   reaches the input dock, **Then** Mac session controls are hidden or their
   emissions drop without logging unsafe payload data.

### Edge Cases

- Remote Management is enabled but "VNC viewers may control screen" is not
  allowed.
- The Mac supports Apple Remote Desktop administrator privileges, but the saved
  Naru profile only has VNC password access.
- UDP ports required by High Performance screen sharing are blocked, while TCP
  `5900` VNC is reachable.
- A helper action requires macOS permissions that were revoked after pairing.
- The Mac is asleep and cannot be woken across a different subnet without a
  Bonjour sleep proxy or Wake-on-LAN-compatible network path.
- A message, file, command, or status report contains private content; logs must
  remain fixed-label and redacted.
- The remote Mac has customized Mission Control, Desktop, or Spaces keyboard
  shortcuts; Naru's buttons follow Apple's defaults and may need future
  per-profile remapping.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST model Apple Screen Sharing as a VNC-compatible profile
  kind with Apple-aware setup hints, not as full Apple Remote Desktop
  administrator access.
- **FR-002**: System MUST default Apple Screen Sharing profiles to TCP `5900`
  and MAY offer fixed additional-display candidates `5901` and `5902`.
- **FR-003**: System MUST diagnose Apple Remote Desktop support with fixed
  categories: `vncCompatible`, `helperBacked`, `researchOnly`, and
  `unsupported`.
- **FR-004**: System MUST not claim support for private Apple Remote Desktop
  administrator protocols unless a public, documented, review-approved
  integration path is added.
- **FR-005**: System MUST treat High Performance screen sharing as a separate
  research-only candidate until Naru has a public API, licensed protocol, or
  product-owned equivalent that passes benchmarks.
- **FR-006**: System MUST route smooth visual-transport improvements to the
  helper-video path unless direct High Performance screen sharing support
  becomes legitimate and verifiable.
- **FR-007**: System MUST expose helper-backed ARD-class actions only when the
  optional helper advertises the matching fixed capability.
- **FR-008**: User MUST explicitly confirm destructive or privacy-sensitive
  helper-backed actions such as restart, log out, sleep, lock, file transfer,
  shell command execution, or future screen privacy modes.
- **FR-009**: System MUST preserve no-helper VNC connection, viewing, Compose,
  pointer control, diagnostics, and PiP behavior.
- **FR-010**: System MUST record only fixed labels, coarse buckets, and action
  status for ARD-class diagnostics; it must not export hostnames, endpoints,
  credentials, usernames, command text, file paths, message text, screen
  content, or raw timing series.
- **FR-011**: System SHOULD expose Mac session controls for Mission Control,
  front-app windows, app switching, desktop reveal, and Space navigation during
  active sessions.
- **FR-012**: Mac session controls MUST use the existing VNC `KeyEvent`
  emission path with fixed keysym/modifier mappings and MUST NOT require the
  optional helper.
- **FR-013**: Mac session controls MUST NOT mutate Compose text, local
  clipboard state, Direct-mode page, or Direct sticky modifier state.

### Naru Input Requirements *(mandatory if feature handles input)*

- **IN-001**: Local composition path: unchanged. Text and messages are composed
  locally on iPhone/iPad before user confirmation.
- **IN-002**: Remote injection behavior: VNC-compatible profiles use existing
  VNC input; helper-backed messages or actions use the paired helper only after
  capability and approval checks.
- **IN-003**: Fallback behavior: if Apple-specific support is unavailable, Naru
  falls back to the existing VNC path and fixed setup guidance.
- **IN-004**: Clipboard impact: none for P1/P3; helper-backed file/message work
  must not modify clipboard unless a later file/input spec explicitly requires
  it.
- **IN-005**: User confirmation: all helper-backed management actions require
  explicit confirmation; shell command execution is deferred until a separate
  agent/command approval spec exists.
- **IN-006**: Mac session controls are discrete shortcut emissions. They do not
  replace Compose & Send and do not stream multilingual text.

### Tailnet / Connection Requirements

- **TN-001**: Private-network assumption: Apple-aware profiles are private
  host/MagicDNS-first saved profiles.
- **TN-002**: Diagnostics shown to user: DNS, TCP `5900`, optional UDP
  readiness hints for High Performance screen sharing, VNC handshake/auth/first
  frame, helper capability, and fixed permission labels.
- **TN-003**: Public internet posture: public Apple Screen Sharing profiles are
  advanced/manual only and must show security warnings.

### Security & Privacy Requirements *(mandatory)*

- **SP-001**: Data crossing the local/remote boundary: VNC control/display data
  for P1, fixed helper capability/status labels for P2, and user-confirmed
  helper action requests when enabled.
- **SP-002**: Data retained on device: profile kind, port, fixed capability
  labels, fixed last failure code, redacted action status, and user opt-in
  preferences.
- **SP-003**: Data retained on helper/remote host: helper pairing metadata,
  fixed recent action status, and no message text, command text, file paths, or
  screen frames by default.
- **SP-004**: Sensitive actions needing approval: file transfer, shell command,
  restart, shut down, sleep, wake, log out, lock/unlock, message send, helper
  capability escalation, and future privacy/curtain modes.
- **SP-005**: Logging rule: logs and diagnostics MUST NOT include hostnames,
  endpoints, credentials, raw ARD/VNC payloads, message text, shell command
  text, file names, file contents, usernames, screenshots, pixels, coordinates,
  or exact timing series.

### Key Entities

- **AppleRemoteDesktopSupportTier**: A fixed product catalog value describing
  whether a capability is VNC-compatible, helper-backed, research-only, or
  unsupported.
- **AppleScreenSharingProfileHints**: Setup hints for default port, additional
  display ports, VNC viewer allowance, public-internet warning, and helper
  upgrade path.
- **ARDClassHelperCapability**: Optional helper-advertised capability such as
  `systemStatus`, `messageUser`, `fileStage`, `wakeOrKeepAwake`, `lockScreen`,
  or `powerAction`.
- **ARDClassActionRequest**: A user-confirmed helper action request with fixed
  type, fixed approval state, and redacted result.
- **MacSessionControl**: A fixed VNC-compatible shortcut action such as Mission
  Control, App Windows, Switch App, Desktop, Space Left, or Space Right.

## Acceptance Test Matrix *(mandatory)*

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| Apple Screen Sharing profile defaults to TCP `5900` and labels full ARD admin as unavailable | XCTest model test | iPhone | `swift test --filter AppleRemoteDesktopSupportCatalogTests` |
| Extra display suggestions use fixed ports `5901` and `5902` | XCTest model test | iPhone | `swift test --filter AppleRemoteDesktopSupportCatalogTests` |
| Helper capability catalog hides unavailable ARD-class actions | XCTest model test | iPhone | `swift test --filter AppleRemoteDesktopSupportCatalogTests` |
| High Performance screen sharing is classified as research-only | XCTest model test | iPhone | `swift test --filter AppleRemoteDesktopSupportCatalogTests` |
| Mac session controls emit fixed keyboard shortcuts without Compose mutation | XCTest model test | iPhone | `swift test --filter 'MacSessionControlTests|MacSessionControlModelTests|RemoteInputDockRenderStateTests'` |
| iPad profile editor renders the same Apple-aware hints without becoming the primary gate | XCUITest or screenshot review | iPad-graceful | Simulator screenshot artifact after UI implementation |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of Apple-aware profile diagnostics use fixed labels and pass
  report redaction tests.
- **SC-002**: Apple Screen Sharing setup reduces misconfiguration loops by
  distinguishing VNC-compatible access from full ARD administrator privileges.
- **SC-003**: No direct High Performance screen sharing mode ships until a
  public or licensed implementation path has benchmark evidence.
- **SC-004**: Helper-backed ARD-class actions remain disabled unless the helper
  capability, profile policy, and user approval gate all pass.
- **SC-005**: Mac session controls remain available without helper pairing and
  use only fixed shortcut labels in code/tests.

## Assumptions

- Naru does not reverse engineer private Apple Remote Desktop protocols.
- Apple's VNC-compatible Screen Sharing path remains reachable on TCP `5900`
  when Remote Management allows VNC viewers.
- The product-owned path for smoother sustained visual transport remains Naru
  Helper Video unless a future Apple API changes the integration surface.

## Non-Goals

- Shipping an Apple Remote Desktop administrator clone.
- Implementing proprietary High Performance screen sharing in this feature.
- Bypassing macOS Remote Management, Screen Recording, Accessibility, or user
  approval requirements.
- Adding shell command execution before a separate command/agent approval spec.
