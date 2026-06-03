# Feature Specification: Connection Grid, Reachability, Previews, And Collectable Diagnostics

**Feature Branch**: `005-connection-grid-diagnostics`
**Created**: 2026-06-02
**Status**: Draft
**Product**: Naru Remote
**Input**: Goal - fix light/dark theme visibility issues, make the app open by default to a grid of saved connections, show each connection's most recent screen capture on the grid, show online/reachable status when the app opens, and make problem diagnostics easy for the Naru team to collect without leaking sensitive content.

## Why This Feature

Naru currently opens into a split-view profile list plus a selected session detail. That is serviceable for development, but it does not match how a remote desktop viewer should feel once a user has multiple computers:

1. The first useful choice is "which computer do I want?", not "which row in a sidebar is selected?" A phone-first app should start with a dense, glanceable connection grid.
2. A saved computer is easiest to recognize by the last visible screen, especially when names are similar. The preview must be local-only and privacy-scoped.
3. Reachability must be visible before the user taps Connect. A stale green dot from yesterday is not enough; launch should start bounded, non-blocking probes and show checking/reachable/unreachable states.
4. Support diagnostics are currently human-readable text only. They are safe, but harder to aggregate. We need a structured, schema-versioned report that preserves the existing redaction guarantees.
5. Some surfaces still use fixed light colors or weak status tint choices. The connection grid must pass visual inspection in both light and dark appearance.

## User Scenarios & Testing

### User Story 1 - Start In A Connection Grid (Priority: P1)

A returning user opens Naru and sees saved computers as cards in a responsive grid. Tapping a card opens that profile's connection detail/session view. The old list can remain as secondary navigation on wide layouts, but the default entry point is the grid.

**Independent Test**: Launch with multiple saved profiles in the UX-audit fixture on iPhone and iPad simulators. Assert the first detail surface exposes `naru.connection.grid`, cards expose stable accessibility identifiers, and no session viewport is shown until a card is selected or connected.

**Acceptance Scenarios**:

1. Given one or more saved profiles, when the app launches, then the primary first screen is a profile grid rather than a pre-selected session viewport.
2. Given no saved profiles, when the app launches, then the existing empty-home add-profile CTA remains the first screen.
3. Given a card is selected, when the user taps it, then the session detail for that profile opens and all existing connect/input behavior remains available.

### User Story 2 - Last Screen Preview On Each Card (Priority: P1)

A user can recognize a computer from its latest remote screen preview in the grid. The preview is a downsampled local thumbnail captured from the latest received framebuffer for that profile.

**Independent Test**: Unit-test preview store save/load/delete by profile id. UI fixture seeds synthetic previews for multiple profiles and screenshots the grid in light and dark themes.

**Acceptance Scenarios**:

1. Given a profile has a stored preview thumbnail, when the grid renders, then its card shows that image at a stable aspect ratio.
2. Given a profile has no preview, when the grid renders, then its card shows a themed placeholder with host-kind icon and no layout shift.
3. Given a profile is deleted, when deletion completes, then its stored preview is deleted best-effort and never appears on another profile.

### User Story 3 - Reachability At Launch (Priority: P1)

The user can tell whether each saved profile is currently reachable before tapping it. Launch starts bounded background probes for saved profiles, without blocking the UI or auto-connecting a full session.

**Independent Test**: App-model tests inject fake reachability connectors and assert profile states transition from unknown/checking to reachable/unreachable/authenticationRequired. UI fixture screenshots all states.

**Acceptance Scenarios**:

1. Given saved profiles, when the grid appears, then each card initially shows unknown or checking without implying success.
2. Given a probe succeeds to first-frame or handshake/auth-required, when it completes, then the card shows reachable or needs-password using a distinct visual state.
3. Given a probe fails, when it completes, then the card shows unreachable and exposes the safe diagnostic catalog stage that failed.
4. Given the user opens a real session while probes are running, then probes do not steal the active connector or clear the session.

### User Story 4 - Theme-Safe, Readable Cards And Diagnostics (Priority: P1)

The grid, status badges, diagnostics panel, placeholders, and buttons remain readable in light and dark appearance.

**Independent Test**: UX-audit screenshots in light and dark appearance for the grid, diagnostics, empty state, and active-session detail. Static review removes hardcoded light-only backgrounds from these surfaces.

**Acceptance Scenarios**:

1. Given light appearance, when the grid and diagnostics render, then text, badges, separators, and placeholders meet readable contrast and do not disappear into the canvas.
2. Given dark appearance, when the same surfaces render, then fixed white/cream backgrounds are not used unless paired with dark text by design.
3. Given long profile names or endpoints, when cards resize across phone and tablet widths, then text truncates or wraps without overlapping status badges or previews.

### User Story 5 - Collectable Structured Diagnostics (Priority: P1)

When a connection fails, the user can share a structured diagnostic report that the team can aggregate by schema version, stage id, status id, build version, and coarse environment fields. It must be detailed enough for support to distinguish "wrong profile target", "VNC port unreachable", "handshake/authentication reached", and "stream dropped" without asking for a second log. It must keep the current safe-catalog rules: no password, host, endpoint, clipboard text, composed text, pixels, coordinates, raw latency, or raw error strings.

**Independent Test**: Unit-test JSON rendering with sentinel secrets in every caller-provided field. Assert the JSON contains only schema keys, safe stage/status ids, safe catalog detail, build version, timestamps, and coarse app/session state.

**Acceptance Scenarios**:

1. Given a diagnostic run, when the user shares diagnostics, then the share payload includes both human-readable text and a JSON block or file with `schemaVersion`.
2. Given caller-provided safeDetail/nextAction strings contain secrets, when JSON renders, then those strings are omitted in favor of the fixed safe catalog.
3. Given a card has a preview thumbnail, when diagnostics are exported, then no image, pixel-derived bytes, frame dimensions beyond safe catalog text, or thumbnail metadata are included.
4. Given a TCP or RFB failure, when JSON renders, then it includes debug-safe failure context: target fingerprint, host kind, configured port, credential-reference presence, diagnostic trigger, timeout bucket/value, run duration bucket, stage timestamp, and typed failure code.

## Requirements

### Functional Requirements

- **FR-001**: Naru MUST default to a connection grid when at least one profile exists. Empty-profile launch MUST keep the add-profile home CTA.
- **FR-002**: The grid MUST render one card per saved profile with display name, endpoint or host-kind label, last preview/placeholder, and current reachability state.
- **FR-003**: Card tap MUST select the profile and navigate to the existing session detail without changing existing connect/disconnect/input semantics.
- **FR-004**: Naru MUST persist a downsampled last-frame preview per profile after a successful framebuffer receive, keyed by profile id.
- **FR-005**: Stored previews MUST be local-only app data, deleted best-effort on profile deletion, and excluded from diagnostics, logs, telemetry, and share exports.
- **FR-006**: The app MUST start bounded, non-blocking reachability probes for saved profiles when profiles first load, with cancellation on model teardown or profile deletion.
- **FR-007**: Reachability states MUST distinguish at least `unknown`, `checking`, `reachable`, `needsPassword`, and `unreachable`.
- **FR-008**: Reachability probes MUST reuse the fixed diagnostic message catalog for user-visible failure reasons and MUST NOT show raw network errors.
- **FR-009**: Grid and diagnostics surfaces MUST use adaptive color tokens for canvas, card/surface, hairline, status fills, and text in light and dark appearance.
- **FR-010**: Diagnostics export MUST provide a structured JSON representation with schema version, build version, generated timestamp, run id, profile fingerprint, run timestamps, run duration bucket, stage rows, and verdict.
- **FR-011**: Diagnostics JSON MUST use safe catalog stage/status/detail values only; caller-provided stage titles/details/next actions, host, endpoint, credential references, clipboard text, composed text, pointer coordinates, raw latency, raw errors, and pixel data MUST NOT be emitted.
- **FR-012**: The existing plain-text share summary MUST remain available for humans, but the structured report is the canonical collection format.
- **FR-013**: Diagnostics JSON MUST include debug-safe connection context when a profile is selected: target fingerprint derived from host+port, host kind, configured port, credential-reference presence, diagnostic trigger, and probe timeout seconds. The raw host, endpoint, username, credential reference, password, and raw network error MUST remain absent.
- **FR-014**: Failed diagnostic stages MUST include a typed failure code such as `network.connectionFailed`, `network.connectTimedOut`, `network.readTimedOut`, `rfb.authenticationRequired`, or `rfb.securityFailed` when the app can derive one. Failure codes MUST be fixed enums/strings owned by the app, not raw platform error descriptions.
- **FR-015**: Diagnostics JSON MAY include active-session stream-performance aggregates for support triage: frame counts, content/empty/timeout ratios, dirty-rectangle/change-area aggregates, coarse duration/FPS buckets, coarse receive-timing buckets, coarse thermal state, and the viewer-selected stream power mode. It MUST NOT include pixels, frame dimensions, coordinates, raw latency/timing samples, raw target identity, preview data, device power state, or user content.

### Naru Input Requirements

- **IN-001 Local composition path**: unchanged. The grid is a launcher and does not modify Compose & Send, Direct Keystroke, or clipboard behavior.
- **IN-002 Remote injection behavior**: unchanged. Reachability probes may perform network handshake/first-frame checks but must not send user text, key events, pointer events, or clipboard payloads.
- **IN-003 Fallback behavior**: if preview storage or reachability probes fail, cards remain usable and show placeholder/unknown or unreachable states.
- **IN-004 Clipboard impact**: none. Clipboard content is never previewed or exported.
- **IN-005 User confirmation**: previews are automatic local UI state; diagnostics still require user share action before leaving the device.

### Tailnet / Connection Requirements

- **TN-001 Private-network assumption**: unchanged; the grid should favor MagicDNS/private endpoints and keep advanced-public endpoint warnings visible.
- **TN-002 Diagnostics shown to user**: grid status and diagnostics use fixed safe catalog labels. No host, endpoint, password, or raw error leaves the model via export.
- **TN-003 Startup probes**: reachability probes must be bounded in count and timeout so launch remains responsive on cellular.

### Security & Privacy Requirements

- **SP-001 Data crossing local->remote**: reachability probes use only transport/session setup messages required to determine reachability. No composed user content crosses.
- **SP-002 Data retained on device**: profile metadata remains as today. New retained data is only a downsampled last-frame preview per profile and transient reachability state.
- **SP-003 Data retained on remote host**: unchanged; the remote VNC server may observe connection probes the same way it observes connection attempts.
- **SP-004 Sensitive actions needing approval**: sharing diagnostics still uses the system share sheet.
- **SP-005 Preview privacy**: previews must never be logged, copied into diagnostics, or sent to support automatically. They are local recognition aids only.
- **SP-006 Diagnostic redaction**: structured diagnostics must be generated from typed, safe-catalog fields, not from raw `Error.localizedDescription` or caller-provided strings.

### Key Entities

- **ConnectionGridCard** - view model for a saved profile card: profile id, display name, endpoint label, host-kind warning, preview availability, reachability state, and selected state.
- **ProfilePreviewThumbnail** - local, downsampled preview image metadata and bytes for a profile; never exported.
- **ProfilePreviewStore** - async store keyed by `ConnectionProfile.ID` with load/save/delete operations.
- **ProfileReachabilityState** - enum for unknown/checking/reachable/needsPassword/unreachable plus safe failed stage id when available.
- **ReachabilityProbeCoordinator** - app-model owned task coordinator that runs bounded probes and publishes per-profile states without mutating active sessions.
- **DiagnosticCollectionReport** - structured, schema-versioned safe diagnostic payload generated from `ConnectionDiagnosticRun` and build/app context.
- **DiagnosticRunContext** - debug-safe metadata for a diagnostic run: fingerprinted target, host kind, configured port, credential-reference presence, trigger, and probe timeout.
- **DiagnosticStageMetadata** - debug-safe stage metadata such as typed failure code and stage timestamp. It never contains raw platform error text.

## Acceptance Test Matrix

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| Launch with profiles starts on grid | XCUITest screenshot | iPhone simulator | Grid visible first, session viewport absent until card tap |
| Grid adapts to tablet width | XCUITest screenshot | iPad simulator | Multi-column card layout with no text overlap |
| Light and dark cards/diagnostics readable | Screenshot + static review | iPhone simulator | Light/dark captures and removal of fixed light-only fills |
| Preview save/load/delete | Unit | iPhone simulator | Store round-trip by profile id and delete on profile delete |
| Preview shown, placeholder shown | XCUITest screenshot | iPhone simulator | Fixture with mixed preview/no-preview cards |
| Launch reachability probes publish states | App-model unit | iPhone simulator | Fake connector transitions checking to final states |
| Reachability does not disturb active session | App-model unit | iPhone simulator | Active session remains selected and streaming state is unchanged |
| Structured diagnostic JSON redacts sentinels | Unit | iPhone simulator | Secret host/password/clipboard/pixel sentinels absent |
| Structured diagnostic JSON includes debug-safe failure and stream context | Unit | iPhone simulator | TCP failure report includes schema v6 context and typed failure code; active-session report includes safe stream-performance, renderer upload aggregates, viewer stream power mode, and receive-timing buckets; raw host/endpoint/credential/pixels/timing samples remain absent |
| Share diagnostics includes human text + JSON | Unit/UI smoke | iPhone simulator | Share provider payload contains both formats |
| Real Mac VNC launch grid shows reachable and captures preview | Manual device | iPhone physical | Residual-risk manual pass over local/private VNC |

## Success Criteria

- **SC-001**: A saved-profile launch first paints the grid on iPhone and iPad, with profile selection leading to the existing session flow.
- **SC-002**: Cards show a stable preview or themed placeholder and remain readable in light and dark screenshots.
- **SC-003**: At launch, every profile reaches a visible reachability state within the bounded probe timeout or remains honestly checking/unknown if cancelled.
- **SC-004**: Deleting a profile removes its status and preview cache entry.
- **SC-005**: Structured diagnostics can be parsed by schema version and contain no host, endpoint, credential, clipboard, composed text, pixel, coordinate, raw latency/timing sample, or raw error strings.

## Assumptions

- The first implementation may keep the split-view sidebar on iPad/mac-size layouts as secondary navigation, but the detail column's default content is the grid.
- Preview storage can use platform image encoding behind an app-layer protocol while tests use an in-memory implementation.
- Reachability probes can reuse the existing first-frame connector and diagnostic catalog; a lightweight TCP-only optimization is allowed later but is not required for v1.
- The app has no backend telemetry; "collectable" means user-shared support payloads are structured and safe.

## Non-Goals

- Multi-session live tiles or background VNC streaming for every grid card.
- Cloud sync of previews or diagnostics.
- Public-internet discovery or any official Tailscale affiliation.
- New remote input modes, keyboard behavior, or clipboard semantics.
