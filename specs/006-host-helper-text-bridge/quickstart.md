# Quickstart: Host Helper Text Bridge

This feature is not implemented yet. These commands define the expected verification flow for implementation PRs.

## Spec Validation

```bash
rg -n "NEEDS CLARIFICATION[:]" specs/006-host-helper-text-bridge
```

Expected: no unresolved clarification markers.

## First Implementation Slice

Run after adding core helper state and fake-helper routing:

```bash
swift test --filter HelperTextBridge
swift test --filter HelperTextBridgeTests/testHelperTextBridgePathUsesStableDiagnosticValue
swift test --filter TextInjectionAdapterTests
swift test --filter NaruRemoteAppModelTests/testModelRoutesUTF8ComposeThroughReachableHelperWhenVNCUTF8IsUnconfirmed
swift test --filter NaruRemoteAppModelTests/testModelRejectsMismatchedHelperInsertResultID
swift test --filter NaruRemoteAppModelTests/testModelRejectsUTF8ComposeWhenClipboardSupportIsUnconfirmed
swift test --filter NaruRemoteAppModelTests
swift test --filter DiagnosticExportTests
```

Expected:
- UTF-8 Compose with unconfirmed VNC clipboard routes to fake helper when reachable.
- The same payload fails safely and retains the draft when helper is unavailable.
- Diagnostics export helper state and fixed failure codes without raw text.

## Future macOS Helper Slice

Run after adding the macOS helper target:

```bash
swift test --filter NaruHelper
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test
```

Manual evidence required before declaring completion:
- Physical iPhone sends Korean/CJK/emoji Compose text to a focused app on the paired Mac.
- Helper disabled/revoked state blocks subsequent inserts.
- Redacted diagnostic export contains helper catalog state only.

## Privacy Checklist

Search generated diagnostics, logs, and fixtures for obvious forbidden sample
data. Normative spec text is excluded because it must name the forbidden
categories.

```bash
rg -n --glob '*HelperTextBridge*' \
  "localhost|5900|password|focusedApp|windowTitle" \
  artifacts/helper-text-bridge NaruRemote/Tests 2>/dev/null || true
```

Expected: no secrets, helper endpoint, host identity, focused app title, or raw
clipboard contents in committed fixtures. Test strings inside source tests are
allowed only when they are local constants and not diagnostic output.
