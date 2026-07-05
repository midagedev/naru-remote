# Feature Specification: Host Helper Text Bridge

**Feature Branch**: `006-host-helper-text-bridge`  
**Created**: 2026-06-05  
**Status**: Implemented v1 (helper text bridge; nativeInsert live-verified with Korean against a real Mac 2026-07-05). Open: T028 helper-side revoke, physical evidence recording, security-review checklist.  
**Product**: Naru Remote  
**Input**: Founder feedback: Compose & Send must reliably insert Korean/CJK/emoji text into a remote Mac from iPhone; Apple Screen Sharing did not adopt legacy VNC `ClientCutText` in local probes, so a helper-native path is needed for the founder's sustained iPhone workspace.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Send Multilingual Compose Through Helper (Priority: P1)

An iPhone user is connected to their own Mac over VNC and writes a Korean or mixed-language prompt in the local Compose dock. When the VNC server has not confirmed Extended Clipboard UTF-8 support, the user can choose the optional trusted Mac helper path and send the final local text to the focused remote app without pretending that legacy VNC clipboard succeeded.

**Why this priority**: The product promise is IME-first remote work from iPhone. Legacy VNC clipboard is not reliable enough for the founder's Apple Screen Sharing target, and Direct mode explicitly cannot carry Korean/CJK/emoji.

**Independent Test**: A fake helper endpoint receives one redacted text-insert request after the app classifies an unconfirmed UTF-8 Compose payload; no VNC `ClientCutText` or paste key event is emitted for that payload.

**Acceptance Scenarios**:

1. **Given** an active VNC session to a profile with a paired helper marked reachable, **When** the user sends Korean/CJK/emoji Compose text and the VNC clipboard path is unconfirmed, **Then** Naru sends the text through the helper text bridge and reports "sent through helper" without writing VNC clipboard bytes.
2. **Given** the helper is not paired, not reachable, disabled, or revoked, **When** the user sends Korean/CJK/emoji Compose text over an unconfirmed VNC clipboard session, **Then** Naru keeps the draft and shows a safe failure that names the missing helper/confirmed clipboard path.

---

### User Story 2 - Permission And Revocation Are Visible (Priority: P2)

A Mac owner installs or enables the helper only for hosts they trust. The app and helper expose the current permission state, make revocation obvious, and never require the helper for basic VNC viewing.

**Why this priority**: Host helper capabilities cross a stronger trust boundary than VNC viewing. Constitution §IV requires optional, least-privilege, observable, and revocable helper behavior.

**Independent Test**: Helper state transitions are represented as fixed-catalog states in app diagnostics and UI copy; disabling the helper prevents any future helper insert attempt without deleting the saved VNC profile.

**Acceptance Scenarios**:

1. **Given** a saved profile with a helper pairing, **When** the helper reports missing Accessibility/Input permission, **Then** Naru shows the helper as unavailable for native insert and falls back to the same safe Compose failure used when no helper exists.
2. **Given** the user revokes helper pairing from the iPhone app or the Mac helper, **When** the next Compose send occurs, **Then** no helper request is attempted and diagnostics record only a fixed revocation state.

---

### User Story 3 - Keep Basic VNC And Diagnostics Honest (Priority: P3)

A user who does not install the helper can still connect, view, pan, zoom, use Direct mode, and use VNC Compose only when the server confirms a safe clipboard path. Diagnostics explain why helper-native text is unavailable without leaking draft text or host identity.

**Why this priority**: The helper must be optional, but the app must not make false success claims when both VNC UTF-8 and helper-native text insert are unavailable.

**Independent Test**: Diagnostic export includes helper capability catalog fields and omits raw Compose text, helper address, host name, clipboard bytes, raw key events, and timing samples.

**Acceptance Scenarios**:

1. **Given** no helper is paired, **When** diagnostics are exported after a failed UTF-8 Compose send, **Then** the report includes `helperTextBridgeState=notConfigured` and the existing payload encoding/status fields, but not the draft text.
2. **Given** helper insertion fails after the helper accepted a request, **When** diagnostics are exported, **Then** the report includes a fixed failure code such as `helper.permissionMissing` or `helper.focusUnavailable`, not raw OS error text.

### Edge Cases

- The focused remote app is a secure input field or blocks paste/text events.
- The helper is paired with one Mac user session but a different user is logged in or the screen is locked.
- The helper crashes, upgrades, or restarts while a Compose send is in flight.
- iPhone changes networks while connected over VNC; helper reachability may differ from VNC reachability.
- The helper has Accessibility permission but not enough ability to insert into the current app.
- The user has sensitive text in the Compose draft; logs and diagnostics must not capture it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST model helper-native text insert as a distinct Compose injection path from VNC clipboard paste.
- **FR-002**: System MUST prefer a confirmed Extended Clipboard UTF-8 VNC path when available and a paired reachable helper-native path when VNC UTF-8 is unavailable for Korean/CJK/emoji payloads.
- **FR-003**: User MUST be able to see whether helper-native text insert is available, unavailable, disabled, or revoked for the selected profile.
- **FR-004**: System MUST retain the Compose draft and report a safe failure when neither confirmed VNC UTF-8 nor helper-native insert is available for Korean/CJK/emoji payloads.
- **FR-005**: System MUST keep the helper optional; basic VNC connect, screen viewing, pointer control, Direct mode, diagnostics, and PiP Watch MUST work without a helper.
- **FR-006**: System MUST expose helper text bridge state and last safe failure code in diagnostic exports using fixed catalog values only.
- **FR-007**: System MUST provide revocation from both the iPhone app profile state and the Mac helper state.

### Naru Input Requirements *(mandatory if feature handles input)*

- **IN-001**: Local composition path: iPhone/iPad Compose text, including Korean/CJK/emoji and dictated text after iOS commits final text.
- **IN-002**: Remote injection behavior: helper receives final text only after the user taps Send and inserts it into the currently focused Mac app using helper-native APIs.
- **IN-003**: Fallback behavior: confirmed Extended Clipboard UTF-8 remains valid; unconfirmed VNC clipboard for Korean/CJK/emoji is rejected; Direct mode remains English/raw-key only.
- **IN-004**: Clipboard impact: helper-native insert SHOULD avoid changing the user's Mac general pasteboard. If a fallback helper implementation temporarily uses the pasteboard, it MUST restore or clearly report restore failure.
- **IN-005**: User confirmation: explicit Compose Send action; no background replay or buffered helper send after disconnect.

### Tailnet / Connection Requirements *(mandatory if feature touches connection)*

- **TN-001**: Private-network assumption: helper pairing and reachability are scoped to saved private profiles and MagicDNS/manual private host entries.
- **TN-002**: Diagnostics shown to user: VNC clipboard support, helper pairing state, helper reachability, helper permission state, and fixed helper insert failure code.
- **TN-003**: Public internet posture: helper control endpoints MUST NOT encourage public exposure; public endpoints are unsupported unless a future security review explicitly adds an advanced manual mode.

### Security & Privacy Requirements *(mandatory)*

- **SP-001**: Data crossing the local/remote boundary: final Compose text, profile helper pairing identifier, fixed request ID, and fixed capability/failure codes.
- **SP-002**: Data retained on device: helper pairing metadata, helper enabled/disabled state, last fixed helper status, and last fixed failure code. Raw Compose text MUST NOT be retained beyond existing draft state.
- **SP-003**: Data retained on helper/remote host: helper pairing metadata and fixed recent status only. Raw inserted text MUST NOT be logged or persisted by default.
- **SP-004**: Sensitive actions needing approval: helper pairing, helper enable/disable, helper revocation, and each Compose Send action.
- **SP-005**: Logging rule: logs and diagnostics MUST NOT include raw Compose text, clipboard contents, host name, helper endpoint, auth token, password, framebuffer pixels, coordinates, raw key events, byte payloads, or exact timing samples.

### Key Entities *(include if feature involves data)*

- **HelperTextBridgeProfileState**: Per-profile helper pairing and availability state. Key attributes: enabled flag, pairing fingerprint, helper state catalog value, last safe failure code, last checked bucket, and fixed capability summary for native insert, Accessibility value insert, Unicode event insert, and pasteboard fallback.
- **HelperTextInsertRequest**: One user-confirmed text insert operation. Key attributes: request ID, session/profile IDs, payload encoding class, approximate payload size bucket, injection strategy, and fixed result code. Raw text is process-local only.
- **HelperPermissionState**: Mac-side permission summary for helper-native insert. Key attributes: accessibility value insert state, Unicode event insert state, input permission state if required, pasteboard fallback permission state, and revocation state.

## Acceptance Test Matrix *(mandatory)*

Per constitution §VI, list at least one iPhone path before any iPad path.

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| iPhone Compose sends Korean text through fake helper when VNC UTF-8 is unconfirmed | XCTest + fake helper | iPhone simulator | `swift test` app-model test showing helper request and no VNC clipboard write |
| iPhone Compose keeps draft and reports safe failure when helper is not configured | XCTest | iPhone simulator | `swift test` app-model/text-injection test |
| Helper state appears in diagnostics without raw text or endpoint | Unit | iPhone simulator / N/A | Diagnostic JSON fixture assertion |
| Mac helper inserts text into focused app with permission present | Helper integration/manual | physical Mac + physical iPhone | Manual device log and redacted screen recording |
| Revoking helper blocks future inserts | Helper integration | physical Mac + iPhone simulator or physical iPhone | Helper test log plus app diagnostic export |
| iPad graceful scaling shows same helper state in the session UI | Screenshot/XCUITest | iPad-graceful | Screenshot artifact after iPhone path is verified |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Korean/CJK/emoji Compose on Apple Screen Sharing no longer depends on legacy `ClientCutText`; it either succeeds through helper-native insert or fails honestly with a retained draft.
- **SC-002**: A helper-native text insert request reaches the helper within 300 ms p95 after the user taps Send on a local private network, excluding user permission prompts.
- **SC-003**: Helper insert diagnostics use only fixed catalog values and pass privacy tests that assert raw text, host identity, endpoints, tokens, and clipboard bytes are absent.
- **SC-004**: Disabling or revoking helper pairing prevents all helper text insert attempts for that profile until the user re-enables or re-pairs it.

## Assumptions

- The first helper target is macOS because the founder's blocking path is Apple Screen Sharing to a Mac.
- The helper runs in the logged-in user's session, not as a root daemon.
- VNC viewing remains the baseline; helper-native insert augments input reliability but does not replace RFB.
- Physical iPhone + Mac evidence is required before declaring the feature complete; simulator/fake-helper tests are necessary but not sufficient.

## Non-Goals

- Building a full remote-control agent or unattended automation framework.
- Image/file paste, voice streaming, shell command execution, or file staging.
- Public-internet helper exposure.
- Requiring helper installation for basic VNC viewing.
- Detecting every remote app secure-input policy with perfect accuracy.
