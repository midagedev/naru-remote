# 2026-06-05 Compose Unconfirmed UTF-8 Guard Summary

## Trigger

Physical-device feedback still reported that Compose input did not work
reliably. A code/spec audit found that the task log said Korean/CJK/emoji
Compose should be rejected on unconfirmed VNC clipboard sessions, but the
runtime still sent those payloads through legacy `ClientCutText` when
`utf8ClipboardSupport == unknown`.

## Research Refresh

- RFC 6143 pseudo-encodings are capability declarations: a server that does not
  support an extension ignores it, and the client must assume the extension is
  unsupported until extension-specific confirmation arrives.
- Therefore a Unicode Compose payload that requires UTF-8 clipboard support
  should not be silently sent through legacy clipboard when no helper bridge is
  available.

## Change

- UTF-8-required Compose payloads now fail locally when server UTF-8 clipboard
  support is `unknown` or `unsupported`, unless a reachable helper text bridge
  can handle the insert.
- ASCII and Latin-1 text still use the legacy clipboard path.
- Failure state keeps the draft text retryable and records only safe capability
  metadata in diagnostics.

## Verification

- `swift test --filter TextInjectionAdapterTests --filter NaruRemoteAppModelTests/testModelRejectsUTF8ComposeWhenClipboardSupportIsUnconfirmed --filter NaruRemoteAppModelTests/testModelRoutesUTF8ComposeThroughReachableHelperWhenVNCUTF8IsUnconfirmed --filter NaruRemoteAppModelTests/testModelRejectsUTF8ComposeWhenClipboardSupportIsUnsupported`
- `swift test`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

## Residual Risk

This prevents false-success legacy sends for Korean/CJK/emoji text. It does not
make unsupported VNC servers accept Unicode by itself; practical Unicode Compose
on those targets still needs confirmed Extended Clipboard support or the helper
text bridge.
