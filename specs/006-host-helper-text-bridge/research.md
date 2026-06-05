# Research: Host Helper Text Bridge

## D1 - Use a logged-in-user macOS helper, not a root daemon

**Decision**: The first Mac helper text bridge should run in the logged-in user's session via a user-level helper model, not as a root LaunchDaemon.

**Rationale**:
- Text insertion targets the user's active GUI session and focused app.
- Root is unnecessary for Compose text insertion and would enlarge the trust boundary.
- Apple Service Management documents helper executables including LoginItems and LaunchAgents, where LaunchAgents run on behalf of the currently logged-in user and can communicate with same-session processes.

**Sources**:
- Apple Service Management: https://developer.apple.com/documentation/servicemanagement/
- Apple Service Management package installer update guide: https://developer.apple.com/documentation/servicemanagement/updating-your-app-package-installer-to-use-the-new-service-management-api

**Alternatives considered**:
- Root LaunchDaemon: rejected because it is over-privileged and poorly matched to focused GUI insertion.
- No helper: rejected because local Apple Screen Sharing probes showed legacy VNC clipboard is not reliable for the founder path.

## D2 - Treat helper-native insert as separate from VNC clipboard

**Decision**: Add a distinct helper-native injection path instead of making legacy VNC clipboard look more reliable.

**Rationale**:
- RFC 6143 base `ClientCutText` is Latin-1 oriented and does not prove remote app insertion.
- Extended Clipboard UTF-8 remains the best no-helper VNC path when a server confirms support.
- Apple Screen Sharing did not adopt local redacted `ClientCutText` probes, so helper insertion must be separately observable and diagnosable.

**Sources**:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- RealVNC copy/paste: https://help.realvnc.com/hc/en-us/articles/360002253738-Copying-and-Pasting-Text

**Alternatives considered**:
- Retry `ClientCutText` with longer settle delays: rejected because the probe result indicates adoption failure, not only timing.
- Send Unicode as raw key events: rejected because IME composition is local and Direct mode is not a multilingual text path.

## D3 - Prefer direct text insertion; pasteboard fallback must restore

**Decision**: The helper should prefer a direct text insertion mechanism suitable for the focused app. If it temporarily uses the Mac general pasteboard as a fallback, it must restore prior contents or return a fixed restore-failure code.

**Rationale**:
- The product principle says clipboard should not be collateral damage.
- Apple documents `NSPasteboard` as the shared pasteboard server interface; the general pasteboard participates in broader system behavior, so helper use of it is user-visible and must be minimized.
- `CGEvent` can represent low-level keyboard events, but key events alone do not solve multilingual text unless used only for paste/confirmation gestures around a reliable text staging path.

**Sources**:
- Apple NSPasteboard: https://developer.apple.com/documentation/AppKit/NSPasteboard
- Apple CGEvent: https://developer.apple.com/documentation/coregraphics/cgevent
- Apple CGEvent keyboard initializer: https://developer.apple.com/documentation/coregraphics/cgevent/init%28keyboardeventsource%3Avirtualkey%3Akeydown%3A%29

**Alternatives considered**:
- Always use general pasteboard + Command-V: acceptable only as fallback with restore evidence.
- Key-event streaming for characters: rejected for multilingual Compose.

## D4 - Permission states must be fixed-catalog and visible

**Decision**: Helper availability and failure reporting must use fixed catalog states such as `notConfigured`, `reachable`, `permissionMissing`, `revoked`, `focusUnavailable`, and `insertFailed`.

**Rationale**:
- Accessibility/Input permissions can change outside the iPhone app.
- Diagnostics need enough information for debugging without exporting raw OS error strings, host identity, helper endpoint, tokens, or user text.
- The helper is optional and revocable, so state must be understandable without requiring the user to inspect logs.

**Sources**:
- Apple Accessibility API: https://developer.apple.com/documentation/accessibility/accessibility-api
- Apple CGEvent: https://developer.apple.com/documentation/coregraphics/cgevent

**Alternatives considered**:
- Export raw helper errors: rejected by constitution privacy rules.
- Hide helper state until send time: rejected because permission failures should be understandable before the user loses a Compose draft send attempt.
