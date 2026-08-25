import Foundation

/// What the caller must do with its platform PiP controller when it asks to
/// prepare. `reuseController` is the answer that makes a second entry safe:
/// the system controller and the sample-buffer layer it is bound to are
/// created once and live as long as the layer does.
public enum PiPWatchControllerPreparation: String, Codable, Equatable, Sendable, CaseIterable {
    case createController
    case reuseController
}

/// Why a PiP entry request was not delivered to the system. Every case is a
/// refusal the app should survive — before spec 032 all four were delivered
/// to `startPictureInPicture()` regardless, and a second entry terminated the
/// app on device.
public enum PiPWatchStartRefusal: String, Error, Codable, Equatable, Sendable, CaseIterable {
    /// No controller has been prepared, so there is nothing to start.
    case notPrepared
    /// The system reports Picture in Picture is not currently possible.
    case notPossible
    /// A window is already up; entering again is the reported crash.
    case alreadyActive
    /// A start is in flight and the system has not confirmed it yet.
    case startInFlight
    /// A stop transition is in flight; starting into a teardown is the
    /// second of the three hazards spec 032 closes.
    case stopInFlight
}

/// Whether an entry request may be delivered to the system. A two-case enum
/// rather than `Result<Void, _>` so a test can compare decisions directly.
public enum PiPWatchEntryDecision: Equatable, Sendable {
    case start
    case refused(PiPWatchStartRefusal)
}

/// Why PiP stopped. A closed vocabulary because it reaches the diagnostic
/// export (constitution §IV).
public enum PiPWatchStopReason: String, Codable, Equatable, Sendable, CaseIterable {
    /// PiP has not stopped in this session.
    case notStopped
    /// The user asked for it, from the app.
    case userRequested
    /// The session it was watching ended.
    case sessionEnded
    /// The system took it down — the user closed the floating window, or iOS
    /// dismissed it. Before spec 032 nothing in the app learned about this,
    /// so app state and system state diverged silently.
    case systemDismissed
    /// The system refused to start, via the delegate's failure callback.
    case startFailed
}

/// The lifecycle of a system Picture-in-Picture controller, as a value.
///
/// It lives in Core, with no AVKit, for a measured reason: on the iPhone 17
/// Pro simulator (iOS 26.2) `AVPictureInPictureController.isPictureInPicture
/// Supported()` is false, so the crash this type exists to prevent cannot be
/// reproduced or gated on any runner this repository can run. Keeping the
/// *decisions* — create or reuse, start or refuse, who stopped it — in a pure
/// value means they are covered by `swift test` even though AVKit is not.
///
/// The platform adapter (`PiPWatchPictureInPictureController`) owns one of
/// these and does exactly what it says.
public struct PiPWatchControllerLifecycle: Equatable, Sendable {
    public enum Phase: String, Codable, Equatable, Sendable, CaseIterable {
        /// No system controller exists.
        case unprepared
        /// A controller exists and is idle.
        case prepared
        /// A start has been delivered; the system has not confirmed it.
        case starting
        /// A PiP window is up.
        case active
        /// A stop has been delivered; the system has not confirmed it.
        case stopping
    }

    public private(set) var phase: Phase
    /// Every entry the app asked for, refused or not.
    public private(set) var entryRequestCount: Int
    /// How many system controllers were constructed. One per layer is the
    /// invariant this count exists to make visible.
    public private(set) var controllerCreationCount: Int
    public private(set) var startRefusalCount: Int
    public private(set) var startFailureCount: Int
    public private(set) var systemDismissalCount: Int
    public private(set) var lastStopReason: PiPWatchStopReason
    /// Set when the app itself asked to stop, so a confirmed stop can tell an
    /// app-initiated teardown from the system taking the window away.
    private var pendingStopReason: PiPWatchStopReason?

    public init() {
        phase = .unprepared
        entryRequestCount = 0
        controllerCreationCount = 0
        startRefusalCount = 0
        startFailureCount = 0
        systemDismissalCount = 0
        lastStopReason = .notStopped
        pendingStopReason = nil
    }

    /// True while the app should consider a PiP window up or coming up.
    public var isEngaged: Bool {
        phase == .starting || phase == .active
    }

    public var hasController: Bool {
        phase != .unprepared
    }

    /// Idempotent: the second and every later call reuses the controller.
    public mutating func prepare() -> PiPWatchControllerPreparation {
        guard phase == .unprepared else {
            return .reuseController
        }
        phase = .prepared
        controllerCreationCount += 1
        return .createController
    }

    /// The hosted layer or the whole session went away, so the controller
    /// goes with it and the next `prepare()` must build a new one.
    public mutating func invalidate(reason: PiPWatchStopReason = .sessionEnded) {
        if phase != .unprepared {
            lastStopReason = reason
        }
        pendingStopReason = nil
        phase = .unprepared
    }

    /// The single gate in front of `startPictureInPicture()`.
    @discardableResult
    public mutating func requestEntry(
        isPictureInPicturePossible: Bool
    ) -> PiPWatchEntryDecision {
        entryRequestCount += 1

        switch phase {
        case .unprepared:
            return refuse(.notPrepared)
        case .starting:
            return refuse(.startInFlight)
        case .active:
            return refuse(.alreadyActive)
        case .stopping:
            return refuse(.stopInFlight)
        case .prepared:
            guard isPictureInPicturePossible else {
                return refuse(.notPossible)
            }
            phase = .starting
            return .start
        }
    }

    /// The app asked to leave PiP. Returns false when there is nothing to
    /// stop, so a redundant stop is not delivered to the system either.
    @discardableResult
    public mutating func requestStop(reason: PiPWatchStopReason = .userRequested) -> Bool {
        guard isEngaged else {
            return false
        }
        pendingStopReason = reason
        phase = .stopping
        return true
    }

    public mutating func noteStarted() {
        phase = .active
    }

    public mutating func noteStartFailed() {
        startFailureCount += 1
        lastStopReason = .startFailed
        pendingStopReason = nil
        phase = hasController ? .prepared : .unprepared
    }

    /// The system confirmed the window is gone. With no pending app-initiated
    /// reason this is the user closing the floating window, which is the state
    /// divergence spec 032 closes.
    public mutating func noteStopped() {
        let reason = pendingStopReason ?? .systemDismissed
        if reason == .systemDismissed {
            systemDismissalCount += 1
        }
        lastStopReason = reason
        pendingStopReason = nil
        if phase != .unprepared {
            phase = .prepared
        }
    }

    private mutating func refuse(
        _ refusal: PiPWatchStartRefusal
    ) -> PiPWatchEntryDecision {
        startRefusalCount += 1
        return .refused(refusal)
    }
}
