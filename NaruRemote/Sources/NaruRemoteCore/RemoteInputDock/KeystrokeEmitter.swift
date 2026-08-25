import Foundation

/// Logical-event-to-wire-events bridge for Direct Keystroke Mode.
///
/// Owns no state of its own; takes an `RFBKeyEventClient` injection
/// (the production `RFBNetworkClient` or a fake) and emits the right
/// *sequence* of `KeyEvent` messages for one logical user-perceived
/// keypress.
///
/// Per `contracts/keystroke-emitter.md`:
/// - Total `KeyEvent` count for any `emit(...)` call is
///   `2 * (1 + modifiers.count)`.
/// - Modifier press order: Control → Shift → Alt → Meta.
///   Release is the reverse.
/// - On any `RFBKeyEventClient.sendKeyEvent(...)` throw, the
///   emitter rethrows immediately.  The caller (`NaruRemoteAppModel`)
///   is responsible for clearing sticky-armed modifier state on
///   throw.
public final class KeystrokeEmitter: Sendable {
    private let client: any RFBKeyEventClient

    public init(client: any RFBKeyEventClient) {
        self.client = client
    }

    /// Emit a logical key press with the active modifier set.
    ///
    /// For a tap on `c` with `[.control]` active, the wire shows
    /// (in order):
    ///
    ///   1. KeyEvent(keysym: Control_L (0xFFE3), isDown: true)
    ///   2. KeyEvent(keysym: 'c'        (0x0063), isDown: true)
    ///   3. KeyEvent(keysym: 'c'        (0x0063), isDown: false)
    ///   4. KeyEvent(keysym: Control_L (0xFFE3), isDown: false)
    ///
    /// Modifiers are pressed in canonical order
    /// `[.control, .shift, .alt, .meta]` and released in the
    /// reverse order, regardless of `Set` iteration ordering.
    /// Empty modifier set produces exactly 2 events (key down +
    /// key up).
    public func emit(
        keysym: UInt32,
        modifiers: Set<DirectKeystrokeModifier> = []
    ) async throws {
        try await emitOrdered(keysym: keysym, modifiers: modifiers)
    }

    /// Hardware-keyboard variant of the on-screen emit envelope —
    /// same emission contract as `emit(keysym:modifiers:)`.  Wire
    /// output for the same `(keysym, modifiers)` pair is byte-
    /// identical between the two paths (SC-005), proven by
    /// `HardwareOnScreenIdentityTests`.
    ///
    /// The separate name exists only to make the call site explicit
    /// about the modifier-set source:
    ///
    /// - `emit(keysym:modifiers:)` is called from on-screen taps.
    ///   The caller (model) consumes `StickyModifiers.armed`
    ///   slots after the call returns.
    /// - `emitHardware(keysym:modifiers:)` is the wrapping variant
    ///   for callers that synthesize a logical "press + release"
    ///   pair from a single UIPress (e.g. `UIKeyCommand` paths or
    ///   tests).  The OS owns hardware modifier-key release events,
    ///   so the caller does NOT consume sticky state (per
    ///   `contracts/keystroke-emitter.md`).
    public func emitHardware(
        keysym: UInt32,
        modifiers: Set<DirectKeystrokeModifier> = []
    ) async throws {
        try await emitOrdered(keysym: keysym, modifiers: modifiers)
    }

    /// Single-event hardware variant — sends exactly ONE
    /// `KeyEvent` (down OR up) on the wire with no modifier
    /// wrapping.  Used by the `pressesBegan` / `pressesEnded`
    /// path where the OS already reports each modifier key as its
    /// own UIPress, so wrapping would double-press the modifier.
    ///
    /// For example, a hardware Ctrl-c sequence reaches the wire as
    /// four discrete `emitHardware(keysym:isDown:)` calls — one per
    /// UIPress event (Ctrl down → c down → c up → Ctrl up) — which
    /// is byte-identical to the on-screen Ctrl-c envelope.
    public func emitHardware(
        keysym: UInt32,
        isDown: Bool
    ) async throws {
        try await client.sendKeyEvent(keysym: keysym, isDown: isDown)
    }

    // MARK: - Internal emission core

    /// Canonical press order.  Release order is the reverse of
    /// this list — see `contracts/keystroke-emitter.md`.
    private static let pressOrder: [DirectKeystrokeModifier] = [
        .control, .shift, .alt, .meta,
    ]

    private func emitOrdered(
        keysym: UInt32,
        modifiers: Set<DirectKeystrokeModifier>
    ) async throws {
        // 1. Modifier downs in canonical order.
        for modifier in Self.pressOrder where modifiers.contains(modifier) {
            try await client.sendKeyEvent(
                keysym: KeysymMapping.keysym(for: namedKey(for: modifier)),
                isDown: true
            )
        }

        // 2. Key down + key up.
        try await client.sendKeyEvent(keysym: keysym, isDown: true)
        try await client.sendKeyEvent(keysym: keysym, isDown: false)

        // 3. Modifier ups in reverse canonical order.
        for modifier in Self.pressOrder.reversed() where modifiers.contains(modifier) {
            try await client.sendKeyEvent(
                keysym: KeysymMapping.keysym(for: namedKey(for: modifier)),
                isDown: false
            )
        }
    }

    /// Map a sticky-modifier kind to the `_Left` named key the
    /// emitter sends on the wire (per `research.md` R-1 / R-4 —
    /// always the left-side modifier keysym to keep the on-screen
    /// and hardware paths byte-identical).
    private func namedKey(for modifier: DirectKeystrokeModifier) -> KeysymMapping.NamedKey {
        switch modifier {
        case .control: return .controlLeft
        case .shift:   return .shiftLeft
        case .alt:     return .altLeft
        case .meta:    return .metaLeft
        }
    }
}

// `DirectKeystrokeModifier` used to be declared here. It is now an alias for
// `Glasskeys.Modifier` (see `GlasskeysAdoption.swift`) — the same four cases,
// shared with the phone client that runs the same sticky-modifier machine.
// Both paths still feed it: the on-screen strip through
// `StickyModifiers.activeModifiers`, the hardware keyboard through
// `UIKey.modifierFlags`.
