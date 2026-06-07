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

## D5 - Use authenticated length-prefixed JSON for the first helper transport

**Decision**: The first app-to-helper network slice uses one TCP request per helper command, framed as a 4-byte big-endian payload length plus JSON. Each request carries a pairing secret; diagnostics and UI may expose only a non-secret pairing fingerprint.

**Rationale**:
- The helper is private-network/tailnet scoped and optional, but it still accepts user text, so unauthenticated local-network commands are not acceptable.
- Length-prefix framing handles multiline Compose payloads without relying on newline-delimited JSON.
- One request per connection is simple to test and avoids a long-lived unaudited control channel before pairing, persistence, and revocation UI are complete.

**Alternatives considered**:
- Newline-delimited JSON: rejected because Compose text can contain newlines and framing mistakes would be costly.
- Expose helper without a pairing secret on a private network: rejected because private network reachability is not the same as user approval.
- Full persistent bidirectional helper protocol now: deferred because the next practical need is Compose insert reliability, and the security review should stay small.

## D6 - Reject unconfirmed UTF-8 VNC clipboard and make native insert primary

**Decision**: For Korean/CJK/emoji Compose payloads, reject the legacy VNC
clipboard path unless the server has explicitly confirmed Extended Clipboard
UTF-8 support. The primary no-false-success path is the Mac helper
`nativeInsert` strategy. Its implementation should prefer focused-element
Accessibility insertion, then bounded Unicode keyboard events where the target
app honors them, and only then helper-local pasteboard paste with restore.

**Rationale**:
- The founder's Apple Screen Sharing path showed the worst UX failure mode:
  Naru reported a dispatched paste while the remote app received no text.
- Base VNC `ClientCutText` cannot confirm remote app insertion, and an
  unconfirmed UTF-8 payload can fail silently or corrupt multilingual text.
- Apple documents `AXUIElementSetAttributeValue` for setting supported
  accessibility attributes such as editable values, while
  `CGEventKeyboardSetUnicodeString` can attach Unicode text to key events but
  may be ignored by application frameworks. `NSPasteboard` is shared system
  state, so it remains a helper fallback that must restore or report restore
  failure rather than the primary path.

**Sources**:
- Apple AXUIElementSetAttributeValue: https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue
- Apple kAXValueAttribute: https://developer.apple.com/documentation/applicationservices/kaxvalueattribute
- Apple CGEventKeyboardSetUnicodeString: https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring%28stringlength%3Aunicodestring%3A%29
- Apple NSPasteboard: https://developer.apple.com/documentation/AppKit/NSPasteboard
- RealVNC copy/paste guidance: https://help.realvnc.com/hc/en-us/articles/360002253738-Copying-and-Pasting-Text

**Verification**:
- `TextInjectionAdapterTests/testAdapterRejectsUTF8ComposeWhenServerSupportIsUnknown`
  proves unconfirmed UTF-8 no longer writes VNC clipboard or paste events.
- `NaruRemoteAppModelTests/testModelRejectsUTF8ComposeWhenClipboardSupportIsUnconfirmedWithoutHelper`
  proves the app keeps the draft and reports the helper/confirmed clipboard
  requirement.
- `NaruRemoteAppModelTests/testModelRoutesUTF8ComposeThroughReachableHelperWhenVNCUTF8IsUnconfirmed`
  continues to prove reachable helper routing avoids VNC clipboard writes.

**Alternatives considered**:
- Keep best-effort legacy VNC clipboard for Korean/CJK/emoji: rejected because
  it creates false success and loses the user's trust when no text appears.
- Increase paste settle delay: rejected because silent remote pasteboard
  adoption failure is not just a timing issue.
- Use raw VNC key events for every character: rejected because Direct mode is
  not a multilingual composition path and remote IME state is not reliably
  controlled by the iPhone app.

## D7 - Native helper insertion should be capability-gated and fallback-aware

**Decision**: The first helper-native implementation should attempt
Accessibility direct value insertion, then a bounded Unicode `CGEvent` insert,
before changing the Mac general pasteboard. The helper advertises
`nativeInsert` only when at least one non-pasteboard native strategy has the
required permission/capability, and it advertises `pasteboardPasteWithRestore`
separately when event posting for Command-V is available.

**Rationale**:
- The iPhone app already sends final Compose text to the helper only after an
  explicit Send action, so the Mac-side helper can safely try a focused-element
  insertion without logging or persisting raw text.
- `AXUIElementSetAttributeValue` with `kAXValueAttribute` can update supported
  editable accessibility elements. The implementation bounds the replacement
  to the current `kAXSelectedTextRangeAttribute` so it does not replace an
  entire document unless the focused app explicitly reports that selection.
- Many target apps, especially terminal emulators and web views, may reject
  direct Accessibility value mutation. In that case, the helper tries bounded
  Unicode event insertion before using the existing pasteboard-restore strategy.
- Unicode event insertion is capped per event and per request, so a very large
  Compose payload cannot become an unbounded event-posting loop.
- Capability reporting must not overclaim: a helper with paste-event
  permission but no Accessibility trust is still reachable for fallback, but it
  is not a true `nativeInsert` endpoint.
- Capability reporting also distinguishes `accessibilityValueInsert` from
  `unicodeKeyboardEvent`. A helper that can post bounded Unicode events but
  cannot mutate the focused Accessibility value may still advertise
  `nativeInsert`, while the legacy `accessibility` field remains `"missing"` so
  diagnostics do not overclaim AX value insertion.

**Sources**:
- Apple AXUIElementSetAttributeValue: https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue
- Apple kAXValueAttribute: https://developer.apple.com/documentation/applicationservices/kaxvalueattribute
- Apple CGEventKeyboardSetUnicodeString: https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring%28stringlength%3Aunicodestring%3A%29
- Apple NSPasteboard: https://developer.apple.com/documentation/AppKit/NSPasteboard

**Verification**:
- `NaruHelperPasteboardTextInserterTests/testNativeInsertRunsBeforePasteboardFallbackAndDoesNotTouchPasteboard`
  proves native success leaves the general pasteboard untouched.
- `NaruHelperPasteboardTextInserterTests/testNativeInsertFailureFallsBackToPasteboardWhenRequested`
  proves direct-insert rejection can still use the restore fallback.
- `NaruHelperPasteboardTextInserterTests/testNativeInserterChainUsesSecondNativeStrategyBeforePasteboardFallback`
  proves a second native strategy can succeed before pasteboard fallback.
- `NaruHelperTextBridgeCapabilityProbeTests/testNativeAndPasteboardCapabilityAdvertisesNativeFirst`
  and `testPasteboardOnlyCapabilityDoesNotOverclaimNativeInsert` prove the
  fixed capability catalog stays honest.
- `NaruHelperTextBridgeCapabilityProbeTests/testUnicodeEventOnlyCapabilityAdvertisesNativeWithoutOverclaimingAX`
  proves the helper can advertise native Unicode event insertion without
  falsely reporting Accessibility value insertion as granted.
- `NaruHelperTextBridgeProtocolTests/testCapabilityResponseDecodesLegacyPermissionStateWithoutGranularFields`
  proves older capability responses remain decodable after adding the granular
  fields.
- `HelperTextBridgeTests/testCapabilitySummarySeparatesUnicodeNativeFromAXPermission`,
  `NaruRemoteAppSnapshotTests/testInputHelperStatusUsesGranularHelperCapabilitySummary`,
  and `NaruRemoteAppModelTests/testStoredHelperCapabilityProbeMarksReachableWithoutSendingText`
  prove the app preserves granular capability detail for user-visible status
  and diagnostic export without leaking helper fingerprints.

**Residual risk**:
- Physical iPhone + Mac verification is still required. Accessibility direct
  value insertion is app-dependent, and terminal/AI CLI targets may require the
  pasteboard-restore fallback or a future bounded Unicode event strategy.
