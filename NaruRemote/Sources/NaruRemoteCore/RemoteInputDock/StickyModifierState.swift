import Foundation

/// State machine for sticky modifier UX in Direct Keystroke Mode.
///
/// Each modifier (Control, Shift, Alt, Meta) is independently in
/// one of three slot states:
///
/// - `idle`   — not held; not applied to the next non-modifier key.
/// - `armed`  — single-tap-armed; will be applied to the **next**
///              non-modifier key, then released automatically
///              (`consumeAfterNonModifierEmission()`).
/// - `locked` — double-tapped within the 400 ms window; held until
///              the user taps the modifier again.
///
/// State transitions (per `data-model.md`):
///
/// | Current slot | Time since last tap | New slot |
/// | ------------ | ------------------- | -------- |
/// | `idle`       | (any)               | `armed`  |
/// | `armed`      | ≤ 400 ms            | `locked` |
/// | `armed`      | > 400 ms            | `armed`  (fresh single-tap; timestamp updated) |
/// | `locked`     | (any)               | `idle`   |
///
/// `consumeAfterNonModifierEmission()` is invoked by the model
/// after a non-modifier `KeyEvent` pair lands on the wire — it
/// releases armed slots and leaves locked slots alone.
///
/// **API divergence note** vs `data-model.md`: the contract draft
/// kept `lastTapAt` in a separate dictionary owned by the model so
/// the struct stayed `Codable`.  This implementation folds the
/// per-modifier `lastTapAt` map inside the struct because (a) the
/// caller pattern in the model is "tap, then read activeModifiers"
/// — never serialise mid-flight — and (b) the struct is still
/// `Sendable` and `Equatable` and remains cheap to copy.  Sticky
/// modifier state is in-memory only by spec FR-014, so dropping
/// `Codable` does not affect persistence (it has none).
public struct StickyModifierState: Sendable, Equatable {

    /// The four sticky-modifier kinds.  Aliased to the existing
    /// `DirectKeystrokeModifier` so the `KeystrokeEmitter` and the
    /// state machine share a single enum and no translation layer
    /// is needed at the model boundary (the contract surface in
    /// `contracts/keystroke-emitter.md` uses
    /// `StickyModifierState.Modifier`; both names refer to the same
    /// type).
    public typealias Modifier = DirectKeystrokeModifier

    public enum SlotState: String, Sendable, Equatable {
        case idle
        case armed
        case locked
    }

    /// 400 ms double-tap window.  Hard-coded per `data-model.md`:
    /// "tuning belongs to plan / implementation, not a scope
    /// variable" (founder direction 2026-05-02).
    private static let lockWindow: Duration = .milliseconds(400)

    private var slots: [Modifier: SlotState]
    private var lastTapAt: [Modifier: ContinuousClock.Instant]

    public init() {
        self.slots = Dictionary(uniqueKeysWithValues: Modifier.allCases.map { ($0, .idle) })
        self.lastTapAt = [:]
    }

    // MARK: - Queries

    public func slot(for modifier: Modifier) -> SlotState {
        slots[modifier] ?? .idle
    }

    /// The set of modifiers currently held — armed or locked.
    /// This is the snapshot the `KeystrokeEmitter` wraps around a
    /// non-modifier key.
    public var activeModifiers: Set<Modifier> {
        Set(slots.compactMap { (m, s) in s == .idle ? nil : m })
    }

    // MARK: - Transitions

    /// User tapped a modifier key.  See the transition table on the
    /// type doc.  `now` is injected so tests drive the 400 ms
    /// double-tap window without `Task.sleep`.
    public mutating func tap(_ modifier: Modifier, at now: ContinuousClock.Instant) {
        let current = slot(for: modifier)
        switch current {
        case .idle:
            slots[modifier] = .armed
            lastTapAt[modifier] = now
        case .armed:
            if let last = lastTapAt[modifier], now - last <= Self.lockWindow {
                slots[modifier] = .locked
                lastTapAt[modifier] = now
            } else {
                // Outside the window → fresh single-tap.  Stays
                // armed; timestamp updates so a third tap within
                // 400 ms of THIS tap can lock.
                slots[modifier] = .armed
                lastTapAt[modifier] = now
            }
        case .locked:
            slots[modifier] = .idle
            lastTapAt[modifier] = nil
        }
    }

    /// Called by the model after every non-modifier `KeyEvent` pair
    /// lands on the wire.  Armed slots transition to idle (one-shot
    /// consumed); locked slots stay locked.
    public mutating func consumeAfterNonModifierEmission() {
        for m in Modifier.allCases where slots[m] == .armed {
            slots[m] = .idle
            lastTapAt[m] = nil
        }
    }

    /// FR-013 panic clear — all four modifiers → idle.  Wired to
    /// the "Clear modifiers" button on the special-keys page.
    public mutating func clear() {
        for m in Modifier.allCases {
            slots[m] = .idle
        }
        lastTapAt.removeAll()
    }
}
