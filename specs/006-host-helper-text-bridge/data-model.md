# Data Model: Host Helper Text Bridge

## HelperTextBridgeProfileState

Represents helper-native text bridge availability for one saved connection profile.

Fields:
- `profileID`: existing profile identifier.
- `isEnabled`: user-controlled helper use for this profile.
- `pairingFingerprint`: non-secret stable fingerprint for diagnostics and UI matching. Raw endpoint/token is never exported.
- `availability`: `HelperTextBridgeAvailability`.
- `lastFailureCode`: optional `HelperTextBridgeFailureCode`.
- `lastCheckedBucket`: coarse recency bucket such as `never`, `recent`, `stale`.

Lifecycle:
- Created only after the user pairs or enables helper support for a profile.
- Disabled or deleted when the user revokes helper support.
- Updated by reachability/capability checks and helper insert attempts.

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
- `accessibility`: `unknown`, `granted`, `missing`, `revoked`.
- `inputMonitoring`: `unknown`, `granted`, `missing`, `notRequired`.
- `pasteboardFallback`: `available`, `restoreUnsupported`, `disabled`.
- `activeUserSession`: `available`, `locked`, `wrongUser`, `unknown`.

Rules:
- The helper reports only catalog states to the app.
- The app may use these states for UI and diagnostics.
