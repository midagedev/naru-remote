# Research: Direct Keystroke Streaming Mode

**Feature**: `specs/002-direct-keystroke-mode`
**Date**: 2026-05-02
**Phase**: Phase 0 (informs `plan.md` Architecture Decision)

## R-1 — X11 keysym values for the named-key set

**Decision**: Ship a closed `enum NamedKey` in `KeysymMapping` whose raw values are the X11 keysym integers from `keysymdef.h`. Inline literals, not a runtime table.

**Rationale**:

- The named-key set is small and stable — Backspace, Tab, Return, Escape, the four arrows, F1–F12, Home, End, PgUp, PgDn, Insert, Delete, plus four modifier keysyms (Shift_L, Control_L, Alt_L, Meta_L). 27 total. A runtime table or external generated file would only add code-gen overhead with no benefit.
- Inline `case backspace = 0xFF08` lets the compiler verify exhaustiveness in switch sites and gives the unit tests a literal value to assert against (`KeysymMapping.keysym(for: .backspace) == 0xFF08`).
- For printable ASCII (`0x20`–`0x7E`), the X11 keysym value equals the ASCII code, so `Character` → keysym is a direct cast for those characters with no table needed. Non-ASCII characters return `nil` (Direct mode is English-only by spec; CJK input belongs to Compose & Send).

**Locked values** (excerpt; full list lands in `data-model.md`):

| NamedKey | Keysym | Note |
| --- | --- | --- |
| `.backspace` | `0xFF08` | |
| `.tab` | `0xFF09` | |
| `.return` | `0xFF0D` | LineFeed `0xFF0A` is X11-but-rare; Return is what terminals expect |
| `.escape` | `0xFF1B` | |
| `.left` `.up` `.right` `.down` | `0xFF51` `0xFF52` `0xFF53` `0xFF54` | |
| `.home` `.end` | `0xFF50` `0xFF57` | |
| `.pageUp` `.pageDown` | `0xFF55` `0xFF56` | |
| `.insert` `.delete` | `0xFF63` `0xFFFF` | |
| `.f1` … `.f12` | `0xFFBE` … `0xFFC9` | sequential |
| `.shiftLeft` | `0xFFE1` | left side only — see R-4 |
| `.controlLeft` | `0xFFE3` | |
| `.altLeft` | `0xFFE9` | |
| `.metaLeft` | `0xFFE7` | maps to Cmd on macOS remote, Win on Windows remote |

**Alternatives Considered**:

- *Generate from `keysymdef.h` at build time.* Rejected — the file has 1,000+ entries, we only need 27 + ASCII range, and a generator adds CI complexity with no upside.
- *Look up keysyms in a Dictionary.* Rejected — slower, harder to reason about exhaustiveness, harder to test.

**Source**: X.Org `keysymdef.h` ([reference snapshot](https://gitlab.freedesktop.org/xorg/proto/xorgproto/-/blob/master/include/X11/keysymdef.h)) — values for Backspace, Tab, Return, etc. are part of the X11 1989-era public API and have not changed.

---

## R-2 — `UIKeyCommand` vs `pressesBegan` / `pressesEnded` for hardware keyboard capture

**Decision**: Use `pressesBegan(_:with:)` and `pressesEnded(_:with:)` on a `UIView` subclass that owns `var canBecomeFirstResponder: Bool { true }` while Direct mode is active. Do **not** rely on `UIKeyCommand` for the general path.

**Rationale**:

- `UIKeyCommand` is a registration-based API — each chord must be declared up-front (`UIKeyCommand(input: "c", modifierFlags: .control, action: #selector(...))`). It's intended for app-level shortcuts (Cmd-N, Cmd-S), not arbitrary keystroke streaming. Registering 100+ chords to cover the keyboard would be brittle and miss Unicode characters.
- `pressesBegan(_:with:)` receives `Set<UIPress>`. Each `UIPress` carries a `key: UIKey?` with `keyCode: UIKeyboardHIDUsage`, `characters: String`, `charactersIgnoringModifiers: String`, `modifierFlags: UIKeyModifierFlags`. This is the raw stream we need.
- `keyCode` (a `UIKeyboardHIDUsage` int) is what we map to X11 keysyms via `KeysymMapping.keysym(forUIKeyCode:)`. Modifier flags come from the same `UIKey` instance, so we don't need the local `StickyModifierState` for hardware paths — the OS already tells us "Ctrl was held when this key was pressed."
- Hardware-keyboard auto-repeat: per Apple docs, holding a hardware key produces *one* `pressesBegan` and *one* `pressesEnded`; the press's `phase` is `.began` then `.ended`, with no per-repeat synthesis from UIKit. This matches FR-006 ("no auto-repeat synthesis from Naru") and FR-016 ("one-shot only on the soft keyboard too") — both paths emit exactly one `KeyEvent` down + one up per logical key.

**Where `UIKeyCommand` still helps**: a small set of system-level chords iOS would otherwise consume — `Esc` on iPhone is allowed via `UIKeyCommand(input: UIKeyCommand.inputEscape, ...)`. We register a handful of these as a safety net, but the primary path is `pressesBegan`/`pressesEnded`.

**Alternatives Considered**:

- *Wrap a hidden `UITextField` and read text via `UITextFieldDelegate`.* Rejected — same iOS-keyboard / IME problems as the rejected on-screen alternative; doesn't capture Tab, Esc, arrows.
- *Use `GCKeyboard` from GameController.* Considered — provides a similar raw stream but is gaming-oriented and adds a dependency without solving anything `pressesBegan` doesn't.

**Source**: [UIResponder.pressesBegan](https://developer.apple.com/documentation/uikit/uiresponder/1621114-pressesbegan), [UIPress.key](https://developer.apple.com/documentation/uikit/uipress/3526314-key), [UIKey](https://developer.apple.com/documentation/uikit/uikey).

---

## R-3 — `firstResponder` chain when the custom keyboard appears

**Decision**: When Direct mode is entered, the existing Compose `UITextField` (or its SwiftUI equivalent) MUST `resignFirstResponder()`, and the hardware-key-handling view (a `UIViewRepresentable` over a custom `UIView` we'll call `DirectKeystrokeResponderView`) MUST `becomeFirstResponder()`. When Direct mode is exited, the reverse: responder view resigns, Compose field becomes first responder again only if the user explicitly taps it.

**Rationale**:

- iOS keyboard appears whenever a `UITextInput`-conforming view is first responder. To reliably *not* show the iOS keyboard in Direct mode (FR-001), we need the responder chain to point at our own non-text-input view.
- A view that returns `canBecomeFirstResponder = true` and overrides `pressesBegan`/`pressesEnded` will receive hardware keystrokes when it is first responder, *without* iOS showing a keyboard for it (because it does not conform to `UITextInput`).
- Naru's existing dock has a Compose surface that is iOS-keyboard-driven; entering Direct mode must hide that keyboard. This is an explicit FR-001 requirement.

**Edge case handled**: if the user is mid-Compose with the iOS keyboard visible and toggles Direct mode, the responder change tears down the iOS keyboard immediately and animates the custom keyboard in. The Compose draft is preserved per FR-011 because the state lives in the model, not the iOS keyboard.

**Source**: [UIResponder.becomeFirstResponder](https://developer.apple.com/documentation/uikit/uiresponder/1621113-becomefirstresponder), [Managing the responder chain](https://developer.apple.com/documentation/uikit/event_handling_for_uikit_apps).

---

## R-4 — `Cmd` key on iPhone vs iPad

**Decision**: The on-screen "Cmd" key on the special-keys page emits keysym `Meta_L` (`0xFFE7`) on every device class. It is identical to a hardware keyboard's left-Cmd (Magic Keyboard on iPad / iPhone) and the Windows key on a Windows VNC-host hardware keyboard. The remote VNC server is responsible for translating `Meta_L` to whatever its OS calls "the Cmd / Win / Super key" — that's the existing X11 contract.

**Rationale**:

- Naru does not, and should not, change the keysym based on local device. The X11 keysym is the wire contract; remote-side meaning is the remote OS's job (macOS interprets `Meta_L` as Cmd, Linux as Super, Windows as Win).
- iPhone does not have a hardware Cmd key without an attached keyboard. The on-screen Cmd button gives a way to send `Meta_L` from on-screen alone — important for triggering `Cmd-Tab`-style window switching on a remote macOS, even from a touchscreen-only iPhone.

**Caveat**: macOS *local* "Secure Keyboard Entry" or system shortcuts that the local iOS device intercepts (Cmd-Space for Spotlight, Cmd-H for hide, etc.) cannot be intercepted by Naru when those come from a hardware keyboard — iOS handles them before `pressesBegan` runs. This is a known limitation, not a Naru bug. The on-screen Cmd is unaffected because it does not flow through iOS's hardware-keyboard pipeline.

**Source**: X11 keysymdef + Apple's documented reserved system shortcuts.

---

## Implementation order implied by this research

1. Extend RFB layer first — `RFBClientMessageEncoder.keyEvent(keysym:isDown:)` is already in the codebase from the Compose & Send `pasteCommand` work, so this step adds the new `RFBKeyEventClient` capability protocol, `RFBNetworkClient` adoption (3-line method routing through the existing encoder), and `FakeRFBClientMessageRecorder.keyEvents`. Fully Core, fully unit-testable, no UI yet.
2. `KeysymMapping` + `StickyModifierState` + `KeystrokeEmitter` — Core logic, tests against the fake recorder.
3. `DirectKeystrokeMode` boolean + mode-toggle wiring on `NaruRemoteAppModel` — model-only, model tests.
4. `DirectKeystrokeKeyboardView` + bottom-dock layout + page toggle + modifier visual states — App-side; first simulator screenshot iteration here.
5. `HardwareKeyboardHandler` + `KeysymMapping+UIKit` overload — App-side; XCTest can mock `UIKey`.
6. Mode badge + one-time warning — App-side polish.
7. XCUITest on iPhone simulator covering FR-001, FR-009, FR-010.
8. Manual physical-iPhone verification (vim navigation + Bluetooth Magic Keyboard) — gates ship.

Tasks file (`tasks.md`, separate PR) will encode this order with explicit FR-### / US-# citations and write-set declarations.
