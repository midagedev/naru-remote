# Data Model: Host Helper Text Bridge

## HelperTextBridgeProfileState

Represents helper-native text bridge availability for one saved connection profile.

Fields:
- `profileID`: existing profile identifier.
- `isEnabled`: user-controlled helper use for this profile.
- `pairingFingerprint`: non-secret stable fingerprint for diagnostics and UI matching. Raw endpoint/token is never exported.
- `helperEndpoint`: private-network host/port for the paired helper. This is
  required for transport but must not appear in diagnostic export.
- `pairingSecretRef`: secure-storage reference for the raw pairing secret. The
  raw secret must not be stored in profile JSON.
- `availability`: `HelperTextBridgeAvailability`.
- `lastFailureCode`: optional `HelperTextBridgeFailureCode`.
- `lastCheckedBucket`: coarse recency bucket such as `never`, `recent`, `stale`.

Lifecycle:
- Created only after the user pairs or enables helper support for a profile.
- Disabled or deleted when the user revokes helper support.
- Updated by reachability/capability checks and helper insert attempts.

## HelperTextBridgeConnectionConfiguration

Represents non-secret helper transport metadata stored with a
`ConnectionProfile`.

Fields:
- `isEnabled`: whether this profile may use helper-native text insertion.
- `host`: optional private helper host. Blank means use the VNC profile host.
- `port`: TCP helper port, constrained to `1...65535`.
- `pairingSecretRef`: secure-storage reference for the raw pairing secret.
- `pairingFingerprint`: non-secret fingerprint shown in diagnostics/UI matching.

Rules:
- The raw pairing secret is written only to the credential store and never to
  profile JSON, diagnostics, logs, or screenshots.
- Removing helper configuration from a profile deletes the existing helper
  secret reference on a best-effort basis.
- Stored configurations are sufficient for the app to construct the
  authenticated helper network client when VNC UTF-8 is unconfirmed.

## HelperTextBridgeAvailability

Fixed catalog:
- `notConfigured`
- `disabled`
- `checking`
- `reachable`
- `unreachable`
- `permissionMissing`
- `revoked`
- `versionUnsupported`

Rules:
- UI and diagnostics may expose the catalog value.
- Raw helper errors, host names, endpoints, and tokens must not be stored in this enum.

## HelperTextBridgeFailureCode

Fixed catalog:
- `none`
- `helper.notConfigured`
- `helper.disabled`
- `helper.unreachable`
- `helper.revoked`
- `helper.permissionMissing`
- `helper.focusUnavailable`
- `helper.insertRejected`
- `helper.insertTimedOut`
- `helper.restoreFailed`
- `helper.versionUnsupported`

Rules:
- Codes are safe for diagnostic export.
- Codes must be stable across app versions once exported.

## HelperTextInsertRequest

Represents one user-confirmed Compose send routed to helper-native insert.

Fields:
- `requestID`: UUID.
- `profileID`: existing profile identifier.
- `sessionID`: current remote session identifier.
- `payloadEncoding`: existing `TextInjectionPayloadEncoding`.
- `payloadSizeBucket`: coarse fixed bucket, not exact byte count.
- `strategy`: `nativeInsert`, `pasteboardPasteWithRestore`, or `unsupported`.
- `startedAtBucket` / `finishedAtBucket`: optional coarse timing bucket only if exported.
- `result`: `HelperTextBridgeFailureCode` or success status.

Raw final text:
- Lives only in process memory long enough to send the request.
- Must not be encoded into diagnostics, logs, persisted state, or PR artifacts.

## HelperPermissionState

Mac-side helper capability summary.

Fields:
- `accessibility`: legacy AX value-insert state, `unknown`, `granted`,
  `missing`, `revoked`, or `unsupported`.
- `accessibilityValueInsert`: optional granular AX focused-value insert state,
  `unknown`, `granted`, `missing`, `revoked`, or `unsupported`.
- `unicodeKeyboardEvent`: optional granular bounded Unicode keyboard-event
  insert state, `unknown`, `granted`, `missing`, `revoked`, or `unsupported`.
- `inputMonitoring`: `unknown`, `granted`, `missing`, `notRequired`.
- `pasteboardFallback`: `available`, `missing`, `restoreUnsupported`,
  `disabled`, or `unsupported`.
- `activeUserSession`: `available`, `locked`, `wrongUser`, `unknown`.

Rules:
- The helper reports only catalog states to the app.
- The app stores a fixed `HelperTextBridgeCapabilitySummary` on the per-profile
  helper state after capability probes and may use these states for UI and
  diagnostics.
- Clients that understand the granular fields should explain
  `accessibilityValueInsert`, `unicodeKeyboardEvent`, and `pasteboardFallback`
  separately so a fallback-only helper is not mistaken for a direct native
  insertion endpoint.
