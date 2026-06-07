# Compose Text Event Strategy Summary — 2026-06-08

## Trigger

Physical-device testing showed that local Compose input can accept text, but the
composed text does not reliably appear in the remote Mac application.

This reclassifies the active issue from "local Compose editor freezes" to
"remote text injection is not confirmed or is using an unreliable fallback."

## Chrome Remote Desktop Reference

Chromium's remoting host has separate input surfaces for clipboard, key, and
text injection:

- `InputInjectorMac::InjectClipboardEvent(...)` routes remote clipboard data.
- `InputInjectorMac::InjectKeyEvent(...)` routes physical-style key events.
- `InputInjectorMac::InjectTextEvent(...)` converts UTF-8 text to UTF-16 and
  posts Unicode keyboard events in bounded character chunks.

Reference source:

- https://chromium.googlesource.com/chromium/src/+/HEAD/remoting/host/input_injector_mac.cc
- https://chromium.googlesource.com/chromium/src/+/HEAD/remoting/host/ipc_desktop_environment_unittest.cc

The important product lesson is not that Chrome Remote Desktop never uses
clipboard. It has clipboard sync. The lesson is that a practical remote desktop
stack should not treat "set clipboard, then send paste shortcut" as the only
text entry primitive.

## Strategy Comparison

### Clipboard + paste

Pros:

- Works with plain VNC/RFB using existing `ClientCutText` plus key events.
- Low implementation complexity.

Cons:

- RFB paste success does not prove the focused remote app inserted text.
- UTF-8 clipboard support is not universal or always confirmed.
- Restoring the remote/local pasteboard after posting Cmd-V can race the target
  app's paste handling.
- It can modify user clipboard state.

Use as fallback only. Status must remain `unknown` unless a separate
confirmation source exists.

### Raw key decomposition

Pros:

- Useful for Direct mode, shortcuts, ASCII, navigation, and known key layouts.
- Avoids clipboard mutation.

Cons:

- Multilingual text depends on remote IME state, language toggle state, keyboard
  layout, dead-key behavior, and app-specific composition handling.
- Korean Hangul can be decomposed into jamo/key positions, but correctness then
  requires the remote machine to be in the expected Korean IME/layout state.

Use for Direct mode and explicitly configured IME-aware typing experiments, not
as the automatic Compose path.

### Native Unicode text event

Pros:

- Sends already-composed text as text, not as a guessed keyboard layout.
- Avoids clipboard mutation.
- Matches the design shape used by Chrome Remote Desktop's macOS text event
  injector.
- Can return a helper-level acknowledgement and fixed failure codes.

Cons:

- Requires a trusted host-side helper and macOS permissions.
- Some target apps may reject AX value insertion or ignore Unicode keyboard
  event payloads.

Use as the primary automatic Compose path for Mac profiles with Naru Helper.

## Applied Decision

Automatic Compose sends through Naru Helper now request native insertion only:

```swift
strategyPreferences: [.nativeInsert]
```

`pasteboardPasteWithRestore` remains implemented by the helper, but it is no
longer the default automatic Compose fallback. This prevents a pasteboard
fallback from reporting `sent` when the actual remote app did not insert the
draft.

Diagnostics now include the fixed catalog value:

```json
"latestInjectionHelperStrategy": "nativeInsert"
```

or another `HelperTextInsertStrategy` value if a future explicit fallback path
uses it. Raw draft text, pairing secrets, host details, and clipboard bytes stay
out of diagnostic exports.

## Verification Target

Focused tests should prove:

- VNC-only paste remains `unknown` after transport success.
- Helper Compose requests default to `[nativeInsert]`.
- Helper insert results record `helperStrategyUsed`.
- Diagnostic JSON schema reports `latestInjectionHelperStrategy` without raw
  text or secrets.
