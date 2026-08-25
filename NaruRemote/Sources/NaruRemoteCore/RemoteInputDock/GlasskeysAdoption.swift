import Glasskeys

/// Naru's names for the shared input machines.
///
/// Sticky modifiers, hold-to-repeat and the flush barrier were written here,
/// matured over many rounds against a real VNC session, and then lifted into
/// `glasskeys` so gadak's phone client could run the same decisions instead of
/// a lesser copy of them. This file is the direction reversing: the machines
/// come back as a dependency, and there is one Swift implementation again
/// rather than two that agree only as long as somebody remembers to check.
///
/// What did **not** move is the encoder. `AccessoryKey.keysym`, the RFB
/// `KeyEvent` pairs and the Compose paths stay in this repository, because the
/// far end here is an X11 keysym over RFB and the far end there is a control
/// byte in a PTY — not different constants, a different shape.
///
/// The conformance harness that used to live in `NaruRemoteCoreTests` is gone
/// with the copies it protected: the vectors run in the package's own CI, in
/// both languages, and a vendored snapshot of them here could only go stale.
public typealias StickyModifiers = Glasskeys.StickyModifiers

/// The modifier set naru speaks in. Same four cases as before, now shared —
/// `KeystrokeEmitter` and the strip both keep using this name.
public typealias DirectKeystrokeModifier = Glasskeys.Modifier

/// Hold-to-repeat over naru's own key enum, so the keysym stays on the key.
public typealias AccessoryKeyRepeatCadence = Glasskeys.RepeatCadence<AccessoryKey>

/// Commit what is held, then emit the control — and drop it if the flush
/// failed.
public typealias FlushBarrier = Glasskeys.FlushBarrier

extension AccessoryKey: Glasskeys.RepeatableKey {
    /// The cadence machine reads this; `repeatable` is the property this repo
    /// already used, and it stays the single source for the set.
    public var repeats: Bool { repeatable }
}
