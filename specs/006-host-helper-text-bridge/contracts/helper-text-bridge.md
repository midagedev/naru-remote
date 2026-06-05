# Contract: Helper Text Bridge

This contract describes the app-to-helper behavior before the transport is chosen. The first implementation may use an in-process fake helper for tests; the real macOS helper must preserve this semantic contract.

## Trust Boundary

- Caller: Naru Remote iPhone/iPad app, after the user taps Compose Send.
- Callee: Optional Naru Helper running in the logged-in macOS user session.
- Secret material: pairing secret or token, never diagnostic-exported.
- User content: final Compose text, process-local only unless the helper is explicitly asked to insert it.

## Capability Request

Input:

```json
{
  "schemaVersion": 1,
  "profilePairingFingerprint": "sha256:<redacted>",
  "requestedCapability": "text.nativeInsert"
}
```

Output:

```json
{
  "schemaVersion": 1,
  "availability": "reachable",
  "permissionState": {
    "accessibility": "granted",
    "inputMonitoring": "notRequired",
    "pasteboardFallback": "available",
    "activeUserSession": "available"
  },
  "supportedStrategies": ["nativeInsert", "pasteboardPasteWithRestore"]
}
```

Privacy:
- Capability responses must not include host name, username, focused app title, window title, endpoint, token, or raw OS errors.

## Insert Text Request

Input:

```json
{
  "schemaVersion": 1,
  "requestID": "uuid",
  "payloadEncoding": "utf8ExtensionRequired",
  "payloadSizeBucket": "small",
  "strategyPreference": ["nativeInsert", "pasteboardPasteWithRestore"],
  "text": "<process-local final Compose text>"
}
```

Output:

```json
{
  "schemaVersion": 1,
  "requestID": "uuid",
  "status": "succeeded",
  "strategyUsed": "nativeInsert",
  "safeFailureCode": "none"
}
```

Failure output:

```json
{
  "schemaVersion": 1,
  "requestID": "uuid",
  "status": "failed",
  "strategyUsed": "nativeInsert",
  "safeFailureCode": "helper.permissionMissing"
}
```

## Required Behaviors

- The helper must perform insertion only for a user-confirmed request.
- The helper must reject requests when pairing is revoked, permission is missing, the user session is not insertable, or the helper version is unsupported.
- The helper must not persist raw text.
- The helper must not log raw text, endpoint, token, focused app/window title, pasteboard bytes, or raw OS errors.
- If pasteboard fallback is used, the helper must attempt to restore previous pasteboard contents and return `helper.restoreFailed` if restore fails.
- The app must retain the Compose draft on helper failure.
