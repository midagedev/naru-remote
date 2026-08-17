import Foundation

/// Clock-injected hold-to-repeat state machine for accessory-strip
/// keys (spec 012 US2-1).
///
/// Cadence matches the orca mobile measurement (`docs/research/orca-mobile-input-reference.md`
/// §1.3): one emission on touch-down, then after 400 ms an emission
/// every 45 ms until `release()` / `stop()`. The type never reads
/// `Date()` or `ContinuousClock.now` itself — callers inject `now`
/// so tests can drive the 400/45 ms boundaries without sleeping.
public struct AccessoryKeyRepeatCadence: Sendable, Equatable {
    /// Delay between the initial touch-down emission and the first repeat.
    public static let initialDelay: Duration = .milliseconds(400)
    /// Interval between subsequent repeat emissions.
    public static let repeatInterval: Duration = .milliseconds(45)

    /// Result of `press` / `tick`: optionally emit a key, optionally
    /// schedule the next injected tick at `nextTickAt`.
    public struct Tick: Sendable, Equatable {
        public var emit: AccessoryKey?
        public var nextTickAt: ContinuousClock.Instant?

        public init(emit: AccessoryKey?, nextTickAt: ContinuousClock.Instant?) {
            self.emit = emit
            self.nextTickAt = nextTickAt
        }

        public static let idle = Tick(emit: nil, nextTickAt: nil)
    }

    /// The key currently held, if a repeatable press is in progress.
    public private(set) var heldKey: AccessoryKey?
    private var nextFireAt: ContinuousClock.Instant?

    public init() {
        heldKey = nil
        nextFireAt = nil
    }

    public var isActive: Bool { heldKey != nil }

    /// Touch-down. Always emits once. Repeatable keys also arm the
    /// 400 ms initial delay; non-repeatable keys stay one-shot.
    public mutating func press(_ key: AccessoryKey, at now: ContinuousClock.Instant) -> Tick {
        stop()
        guard key.repeatable else {
            return Tick(emit: key, nextTickAt: nil)
        }
        heldKey = key
        let next = now.advanced(by: Self.initialDelay)
        nextFireAt = next
        return Tick(emit: key, nextTickAt: next)
    }

    /// Injected timer fire. Emits only when `now` has reached the
    /// scheduled instant; earlier ticks return the remaining deadline
    /// and do not emit (the 400 ms boundary).
    public mutating func tick(at now: ContinuousClock.Instant) -> Tick {
        guard let key = heldKey, let due = nextFireAt else {
            return .idle
        }
        if now < due {
            return Tick(emit: nil, nextTickAt: due)
        }
        let next = now.advanced(by: Self.repeatInterval)
        nextFireAt = next
        return Tick(emit: key, nextTickAt: next)
    }

    /// Finger-up. Further ticks emit nothing.
    public mutating func release() {
        stop()
    }

    /// Strip unmount / session teardown. Same as release.
    public mutating func stop() {
        heldKey = nil
        nextFireAt = nil
    }
}
