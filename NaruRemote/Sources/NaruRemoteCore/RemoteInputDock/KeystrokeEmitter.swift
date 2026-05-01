import Foundation

/// Logical-event-to-wire-events bridge for Direct Keystroke Mode.
///
/// Owns no state of its own; takes an `RFBKeyEventClient` injection
/// (the production `RFBNetworkClient` or a fake) and emits the right
/// *sequence* of `KeyEvent` messages for one logical user-perceived
/// keypress. For now (Phase 3) only the empty-modifier path is
/// implemented — exactly one `KeyEvent` down + one `KeyEvent` up.
/// The modifier-wrapping path (Ctrl-c → 4 events in Control_L /
/// shift / alt / meta-down → key-down → key-up → modifier-up
/// reverse order) lands in Phase 4 alongside `StickyModifierState`.
///
/// Per `contracts/keystroke-emitter.md`:
/// - Total `KeyEvent` count for any `emit(...)` call is
///   `2 * (1 + modifiers.count)`.
/// - Modifier press order (Phase 4): Control → Shift → Alt → Meta.
///   Release is the reverse.
/// - On any `RFBKeyEventClient.sendKeyEvent(...)` throw, the
///   emitter rethrows immediately. The caller (`NaruRemoteAppModel`)
///   MUST clear sticky-armed modifier state on throw.
public final class KeystrokeEmitter: Sendable {
    private let client: any RFBKeyEventClient

    public init(client: any RFBKeyEventClient) {
        self.client = client
    }

    /// Emit a logical key press. Phase 3 supports the empty
    /// modifier set only; passing a non-empty set throws a
    /// typed `unsupportedModifierSet` error so callers cannot
    /// silently use Phase 4 wiring before it lands. Phase 4 will
    /// remove this guard and add the modifier-wrapping emission
    /// per `contracts/keystroke-emitter.md`.
    public func emit(
        keysym: UInt32,
        modifiers: Set<DirectKeystrokeModifier> = []
    ) async throws {
        guard modifiers.isEmpty else {
            throw KeystrokeEmitterError.unsupportedModifierSet
        }

        try await client.sendKeyEvent(keysym: keysym, isDown: true)
        try await client.sendKeyEvent(keysym: keysym, isDown: false)
    }
}

/// Sticky-modifier kinds. The full state machine
/// (`StickyModifierState`) lands in Phase 4; this enum is exposed
/// now so `KeystrokeEmitter`'s public API is shaped for the
/// modifier-wrapping path Phase 4 will implement, and Phase 3
/// callers can reference the type without depending on the
/// state-machine struct.
public enum DirectKeystrokeModifier: String, Sendable, Equatable, CaseIterable, Codable {
    case control
    case shift
    case alt
    case meta
}

public enum KeystrokeEmitterError: Error, Equatable {
    /// Phase 3 emit guard — non-empty modifier sets are accepted
    /// only after Phase 4 lands the modifier-wrapping emission.
    /// Callers in the Phase 3 `tapDirectKey(_:)` path must always
    /// pass `[]` until that work merges.
    case unsupportedModifierSet
}
