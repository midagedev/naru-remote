# Contract: MVP Text Injection

## Purpose

Define the MVP behavior for sending locally composed text into a remote VNC
session.

## Input

- Local composed Unicode text
- Active remote session
- User confirmation through Send
- Paste command strategy for the target remote OS or profile setting

## MVP Path

1. User focuses a target field in the remote session.
2. User composes text locally in Remote Input Dock.
3. User taps Send.
4. Naru Remote sends text through Extended Clipboard UTF-8 `provide` when the
   server has confirmed text+provide support through an extended `ServerCutText`
   caps message. If no confirmation has arrived, Naru falls back to legacy RFB
   `ClientCutText` using the local UTF-8 byte payload.
5. Naru Remote sends the remote paste shortcut as RFB key events.
6. Naru Remote displays the actual path and result.

## Status Values

- `ready`: draft can be sent
- `sending`: adapter is active
- `sent`: adapter has a confirmation source that proves the remote target accepted the text
- `failed`: adapter failed and draft is retained
- `unknown`: adapter cannot prove final remote state

The MVP VNC clipboard path should report `unknown` after clipboard set and paste
command success unless a future adapter can confirm that the focused remote app
received the text.

## Helper-Native Compose Path

For Mac profiles with a configured and reachable Naru Helper, automatic Compose
text entry should prefer native text insertion over clipboard mutation. The
default helper request strategy is:

- `nativeInsert`

`pasteboardPasteWithRestore` remains a helper capability, but it must not be the
implicit automatic Compose fallback. A UI or diagnostic path that chooses the
pasteboard fallback must report that fixed strategy value separately from native
insert so field logs can distinguish real text-event insertion from paste
shortcut dispatch.

Current automated coverage verifies outgoing legacy `ClientCutText`, Extended
Clipboard caps/provide negotiation, zlib-wrapped UTF-8 payloads, and paste key
events against the fake RFB server. It does not yet prove that every real VNC
server accepts Unicode clipboard text or inserts it into every focused remote
application.

## Clipboard Restore

MVP may not support reliable remote clipboard restore for every server. The UI
must report one of:

- `notAttempted`
- `attempted`
- `succeeded`
- `failed`
- `unsupported`

## Required Failure Behavior

- Never clear the local draft on failed or unknown send.
- Never silently fall back to key-event typing for multilingual text.
- Never log the text payload in diagnostics.
- Show a retry path or a clear reason when possible.

## MVP Non-Contract

The MVP does not guarantee:

- Native text insertion without clipboard
- Image clipboard support
- Remote app-specific paste confirmation
- Host helper coordination
- Agent action execution
