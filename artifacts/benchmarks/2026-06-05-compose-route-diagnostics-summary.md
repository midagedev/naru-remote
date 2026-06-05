# 2026-06-05 Compose Route Diagnostics Summary

## Trigger

Physical iPhone feedback still reported Compose input as not working. The
existing send/failure state was honest after a failed send, but exported logs
did not yet show the pre-send route decision that explains why Korean/CJK/emoji
text could or could not be inserted.

## Change

- Bump diagnostic collection schema to v23.
- Add safe pre-send input fields:
  - `composeDraftPayloadEncoding`
  - `composePlannedPath`
  - `composeUTF8ClipboardSupport`
  - `composeRouteBlocker`
- Keep route blocker values fixed-catalog only, such as `none`,
  `helperNotConfigured`, `helperDisabled`, `helperUnreachable`,
  `helperPermissionMissing`, `helperRevoked`, `helperVersionUnsupported`,
  `noActiveTextClient`, `directModeActive`, and `emptyDraft`.

## Verification

- `swift test --filter DiagnosticExportTests`
  - Result: passed, 23 tests, 0 failures.
- `swift test --filter NaruRemoteAppModelTests/testDiagnosticExportIncludesComposeRouteBlockerBeforeUTF8SendWithoutHelper`
  - Result: passed.
- `swift test --filter NaruRemoteAppModelTests/testModelRoutesUTF8ComposeThroughReachableHelperWhenVNCUTF8IsUnconfirmed`
  - Result: passed.

## Expected Diagnostic Read

- Korean/CJK/emoji draft + unconfirmed UTF-8 VNC + no helper:
  - `composeDraftPayloadEncoding=utf8ExtensionRequired`
  - `composeUTF8ClipboardSupport=unknown`
  - `composePlannedPath=null`
  - `composeRouteBlocker=helperNotConfigured`
- Korean/CJK/emoji draft + unconfirmed UTF-8 VNC + reachable helper:
  - `composeDraftPayloadEncoding=utf8ExtensionRequired`
  - `composeUTF8ClipboardSupport=unknown`
  - `composePlannedPath=helperTextBridge`
  - `composeRouteBlocker=none`
- Korean/CJK/emoji draft + confirmed UTF-8 clipboard:
  - `composePlannedPath=vncClipboardPaste`
  - `composeRouteBlocker=none`

## Privacy Notes

The new diagnostics export only fixed enum labels and booleans. It must not
include raw Compose text, helper endpoints, pairing fingerprints, host identity,
clipboard bytes, key events, coordinates, pixels, raw timing samples, or byte
counts.

## Remaining Risk

This improves remote debugging of Compose failures but does not itself make a
Mac accept text. Physical iPhone plus Mac helper verification is still required
to prove end-to-end Korean/CJK/emoji insertion.
