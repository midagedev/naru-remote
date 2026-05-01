# Data Model: Direct Keystroke Streaming Mode

**Feature**: `specs/002-direct-keystroke-mode`
**Date**: 2026-05-02
**Phase**: Phase 1 (informs `tasks.md` and implementation)

This file defines the new Core types for Direct Keystroke mode and how they
relate to existing app-model state. All types live in `NaruRemoteCore` and have
no SwiftUI / UIKit imports unless explicitly noted.

---

## `DirectKeystrokeMode`

```swift
public struct DirectKeystrokeMode: Sendable, Equatable, Codable {
    public var isActive: Bool
    public var page: KeyboardPage
    public var hasShownEntryWarningThisSession: Bool

    public init(
        isActive: Bool = false,
        page: KeyboardPage = .qwerty,
        hasShownEntryWarningThisSession: Bool = false
    )
}

public enum KeyboardPage: String, Sendable, Equatable, Codable {
    case qwerty
    case special
}
```

**Lifecycle**:

- Default-constructed (`isActive = false`, `page = .qwerty`, no warning shown) on every fresh `connectSelectedProfile()` (FR-014). State is in-memory only — never persisted to `settings.json` or `profiles.json` (constitution §I default; the user opts in per session by design).
- `isActive` flips on user toggle from `RemoteInputDockView`'s mode picker. Flipping `isActive: false → true` for the first time in a session sets `hasShownEntryWarningThisSession = true` and triggers the FR-009 confirmation dialog. Flipping again in the same session shows no dialog.
- `page` defaults to `.qwerty` on every Direct mode entry (FR-006-adjacent — fresh entry = familiar layout); the user toggles to `.special` via an in-keyboard button.
- On `disconnect()`, profile change, or session end, the entire struct resets to defaults.

**Invariants**:

- `page` matters only when `isActive == true`. We don't enforce this — it's harmless to track the page across off cycles.
- `hasShownEntryWarningThisSession` is reset to `false` on every disconnect; the warning is once-per-session, not once-per-app-install.

---

## `StickyModifierState`

State machine for sticky modifier UX. Each modifier (Ctrl, Shift, Alt, Cmd) is independently in one of three states. A non-modifier key emission consumes the armed modifiers but not the locked ones.

```swift
public struct StickyModifierState: Sendable, Equatable, Codable {
    public var control: Slot
    public var shift: Slot
    public var alt: Slot
    public var meta: Slot

    public enum Slot: String, Sendable, Equatable, Codable {
        case idle
        case armed
        case locked
    }

    public enum Modifier: String, Sendable, Equatable, CaseIterable {
        case control, shift, alt, meta
    }

    public init(
        control: Slot = .idle,
        shift: Slot = .idle,
        alt: Slot = .idle,
        meta: Slot = .idle
    )
}
```

### State transitions

Each modifier slot transitions independently. The transition is driven by user input on the modifier key (single tap, double tap within 400 ms) and by the emitter consuming an armed state when a non-modifier key is sent.

```text
                user tap
                 ─────►
        idle ──────────────► armed
         ▲                     │
         │                     │ emitter consumes (non-mod key sent)
         │                     ▼
         └──── tap ──────── armed → idle
                              │
                              │ second tap within 400 ms
                              ▼
                            locked
                              │
                              │ tap (any time)
                              ▼
                             idle
```

**Public API**:

```swift
extension StickyModifierState {
    /// User tapped a modifier key.  `now` is injected so tests can drive
    /// the 400 ms double-tap window without sleeping.
    public mutating func tap(
        _ modifier: Modifier,
        at now: ContinuousClock.Instant,
        lastTapAt: inout [Modifier: ContinuousClock.Instant]
    )

    /// Emitter calls this after sending a non-modifier KeyEvent down/up
    /// pair so any armed modifiers transition back to idle.  Locked
    /// modifiers stay locked.  Returns the set of modifiers that were
    /// active during emission so the caller knows which release (`up`)
    /// events to send.
    public mutating func consumeAfterNonModifierEmission() -> Set<Modifier>

    /// FR-013 panic clear.  All four modifiers → idle.
    public mutating func clear()

    /// The modifier set currently in armed-or-locked state — what the
    /// emitter must press-down before emitting the non-modifier key.
    public var activeModifiers: Set<Modifier> { get }
}
```

**Transition table** (driven by `tap(_:at:lastTapAt:)`):

| Current slot | Time since last tap on this modifier | New slot |
| --- | --- | --- |
| `idle` | (any) | `armed` |
| `armed` | ≤ 400 ms | `locked` |
| `armed` | > 400 ms | `armed` (treats as fresh single-tap; the previous `armed` is dropped) |
| `locked` | (any) | `idle` |

**Why a separate `lastTapAt` dict instead of a stored property**: the struct stays `Sendable` and `Codable` and is cheap to copy. The clock state belongs to the *holder* (the model), not the data.

**Invariants** (asserted in tests):

- `consumeAfterNonModifierEmission()` never changes a `locked` slot.
- After `clear()`, every slot is `idle` and `activeModifiers` is empty.
- The 400 ms threshold is not an option — it's a constant that lives in the impl. (Founder direction 2026-05-02: "tuning belongs to plan / implementation, not a scope variable".)

---

## `KeysymMapping`

Pure-logic source-of-truth table. Used by both the on-screen and hardware paths so SC-005 (byte-identical wire output for the same logical key) holds by construction.

```swift
public enum KeysymMapping {
    public enum NamedKey: String, Sendable, Equatable, CaseIterable {
        case backspace, tab, return_, escape
        case left, up, right, down
        case home, end, pageUp, pageDown, insert, delete
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
        case shiftLeft, controlLeft, altLeft, metaLeft
    }

    /// Printable ASCII (0x20..0x7E) maps to the identical X11 keysym.
    /// Non-ASCII characters return nil — Direct mode is English-only by
    /// spec; Korean / CJK / emoji belong to Compose & Send.
    public static func keysym(for character: Character) -> UInt32?

    /// Named keys map to their X11 keysym constants (see `research.md`
    /// R-1 for the locked values).
    public static func keysym(for namedKey: NamedKey) -> UInt32
}
```

**App-side overload** (separate file `KeysymMapping+UIKit.swift`, gated by `#if canImport(UIKit)`):

```swift
#if canImport(UIKit)
import UIKit

extension KeysymMapping {
    /// Map a UIKey.keyCode (`UIKeyboardHIDUsage`) from a hardware
    /// keyboard's `pressesBegan(_:with:)` / `pressesEnded(_:with:)`
    /// stream to an X11 keysym.  Returns nil for any key with no
    /// X11 mapping (Globe, Dictation, etc.) — FR-015 requires we
    /// drop these silently.
    public static func keysym(forUIKeyCode code: UIKeyboardHIDUsage) -> UInt32?
}
#endif
```

**Locked keysym values** (from `research.md` R-1):

| Source | Keysym |
| --- | --- |
| Printable ASCII char (`0x20`–`0x7E`) | `UInt32(char.asciiValue!)` |
| `.backspace` | `0xFF08` |
| `.tab` | `0xFF09` |
| `.return_` | `0xFF0D` |
| `.escape` | `0xFF1B` |
| `.left` | `0xFF51` |
| `.up` | `0xFF52` |
| `.right` | `0xFF53` |
| `.down` | `0xFF54` |
| `.home` | `0xFF50` |
| `.end` | `0xFF57` |
| `.pageUp` | `0xFF55` |
| `.pageDown` | `0xFF56` |
| `.insert` | `0xFF63` |
| `.delete` | `0xFFFF` |
| `.f1` … `.f12` | `0xFFBE` … `0xFFC9` (sequential) |
| `.shiftLeft` | `0xFFE1` |
| `.controlLeft` | `0xFFE3` |
| `.altLeft` | `0xFFE9` |
| `.metaLeft` | `0xFFE7` |

**Invariants**:

- `keysym(for character:)` is byte-identical for printable ASCII regardless of source (on-screen tap on the QWERTY page → `keysym(for: "c")`; hardware press of `c` key → `keysym(forUIKeyCode: .keyboardC)` returns the same `0x63`).
- `NamedKey.allCases` covers everything the special-keys page renders.
- No `nil` from `keysym(for namedKey:)` — all named keys have a keysym by construction.

---

## `KeystrokeEmitter`

Logical-event-to-wire-events bridge. Owns no state of its own; takes a `RFBKeyEventClient` injection (the production `RFBNetworkClient` or a fake) and emits the right *sequence* of `KeyEvent`s for one logical user-perceived keypress, including modifier wrapping.

```swift
public final class KeystrokeEmitter: Sendable {
    public init(client: any RFBKeyEventClient)

    /// Emit a logical key press with the active modifier set.  The
    /// caller is responsible for deciding the modifier set (typically
    /// by snapshotting `StickyModifierState.activeModifiers` before
    /// the call).  After the call, the caller invokes
    /// `StickyModifierState.consumeAfterNonModifierEmission()` on its
    /// own copy so armed slots release while locked slots persist.
    ///
    /// For a tap on `c` with `[.control]` active, this emits in
    /// order:
    ///     1. KeyEvent(keysym: Control_L, isDown: true)
    ///     2. KeyEvent(keysym: 'c',       isDown: true)
    ///     3. KeyEvent(keysym: 'c',       isDown: false)
    ///     4. KeyEvent(keysym: Control_L, isDown: false)
    /// Modifiers are pressed in a deterministic order
    /// (Control, Shift, Alt, Meta) and released in the reverse order.
    public func emit(
        keysym: UInt32,
        modifiers: Set<StickyModifierState.Modifier>
    ) async throws

    /// Emit a hardware keyboard press where the modifier set is
    /// already known from `UIKey.modifierFlags` and is NOT sticky-
    /// derived.  Same emission contract as `emit(keysym:modifiers:)`
    /// but the caller does not consume sticky state.
    public func emitHardware(
        keysym: UInt32,
        modifiers: Set<StickyModifierState.Modifier>
    ) async throws
}
```

**Invariants** (asserted in `KeystrokeEmitterTests`):

- For every successful `emit(...)` call there are exactly `2 * (1 + modifiers.count)` `KeyEvent`s on the wire — `n` modifier-down events, 1 character-down, 1 character-up, `n` modifier-up events in reverse.
- The down-events come in a stable order (Control → Shift → Alt → Meta) so the wire bytes are deterministic and unit tests can assert byte-for-byte equality.
- `emit(...)` and `emitHardware(...)` produce byte-identical wire output for the same `(keysym, modifiers)` pair (SC-005).
- An empty `modifiers` set produces exactly 2 `KeyEvent`s: down then up of the keysym.

---

## App-model integration (where these types live in `NaruRemoteAppModel`)

```swift
@MainActor
public final class NaruRemoteAppModel: ObservableObject {
    // ... existing state ...
    @Published public private(set) var directKeystrokeMode: DirectKeystrokeMode = .init()
    @Published public private(set) var stickyModifierState: StickyModifierState = .init()
    private var lastModifierTapAt: [StickyModifierState.Modifier: ContinuousClock.Instant] = [:]
    private var keystrokeEmitter: KeystrokeEmitter?    // built when session has an RFBKeyEventClient

    // New public methods (signatures only — bodies in tasks.md):
    public func toggleDirectKeystrokeMode()
    public func setDirectKeystrokePage(_ page: KeyboardPage)
    public func tapDirectKey(_ key: DirectKey) async  // DirectKey is a small enum: .character(Character) | .named(KeysymMapping.NamedKey) | .modifier(Modifier) | .clearModifiers | .pageToggle
    public func handleHardwareKey(_ key: UIKey, isDown: Bool) async   // App-side; gated by #if canImport(UIKit)
    public func dismissDirectModeEntryWarning()
}
```

**State reset triggers** (model is responsible for these):

- `disconnect()` → `directKeystrokeMode = .init()`, `stickyModifierState = .init()`, `lastModifierTapAt = [:]`, `keystrokeEmitter = nil`.
- New `connectSelectedProfile()` — same reset, fires before stream attaches.
- Profile change — same reset.
- App going to background — *no* reset; sticky state survives PiP / multitasking. This is intentional so a user who locks the phone with Direct mode active returns to the same state.

---

## Test fakes

The fake-RFB-server side gains one new entity for byte-level wire assertions:

```swift
// In TestFixtures/FakeRFBServer/ServerKit/FakeRFBClientMessageRecorder.swift:
public struct FakeRFBKeyEvent: Sendable, Equatable {
    public let keysym: UInt32
    public let isDown: Bool
    public let receivedAt: ContinuousClock.Instant
}

extension FakeRFBClientMessageRecorder {
    public var keyEvents: [FakeRFBKeyEvent] { get }
}
```

This is the same shape the existing `pointerEvents` accessor uses (`FakeRFBPointerEvent`); the recorder demultiplexes incoming client messages by RFB type and stores them in per-type arrays. Tests assert against `recorder.keyEvents` directly.
