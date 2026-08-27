import Foundation

/// Should the device's auto-lock be held off right now?
public enum ScreenWakeDecision: String, Equatable, Sendable {
    case allowSleep
    case holdAwake
}

/// The decision plus the one fact that produced it.
///
/// The reason exists so the hold is debuggable without instrumenting the
/// caller: "why is my phone still awake" and "why did it sleep during a
/// build" are the same question asked from two directions, and both are
/// answered by a single enum case. Constitution §IV — every case is a fixed
/// catalog label, never a coordinate, a byte count, or user text.
public struct ScreenWakeResolution: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        /// Nothing is connected, so nothing is worth watching.
        case noSession
        /// The app is not frontmost. iOS ignores the flag while backgrounded
        /// anyway; releasing it explicitly means the flag never outlives the
        /// screen it was raised for.
        case appNotForeground
        /// The user switched the hold off.
        case userDeclined
        /// A connection is open and on screen.
        case sessionLive
    }

    public let decision: ScreenWakeDecision
    public let reason: Reason

    public init(decision: ScreenWakeDecision, reason: Reason) {
        self.decision = decision
        self.reason = reason
    }

    public var holdsAwake: Bool {
        decision == .holdAwake
    }
}

/// Who decides whether the screen stays on.
///
/// The reason this is a type and not an `if` at the call site: the hold has
/// to be released on every path out of a session — ending it, backgrounding
/// the app, the session failing, the user switching the preference off — and
/// a raised idle-timer flag that no path lowers is a phone that never sleeps
/// again until it is force-quit. One function that maps the whole state to
/// one answer cannot have a path that forgets.
public enum ScreenWakePolicy {

    /// The states in which the user is waiting on this connection.
    ///
    /// `connecting` counts: a phone that dims while it is still reaching a
    /// Mac over a tunnel is dimming at the exact moment the user is watching
    /// hardest. It is bounded — the connect path always resolves to active or
    /// to a failure, and both are handled here.
    public static func isSessionLive(
        sessionState: RemoteSessionState?,
        hasFramebuffer: Bool
    ) -> Bool {
        switch sessionState {
        case .connecting, .authenticating, .active, .degraded, .reconnecting:
            return true
        case .failed, .closed:
            // A terminal session wins over a lingering framebuffer. The last
            // frame stays on screen after a drop so the user can read what was
            // there, and treating that still image as "live" is how a hold
            // outlives the connection that justified it.
            return false
        case .none:
            return hasFramebuffer
        }
    }

    public static func resolve(
        sessionState: RemoteSessionState?,
        hasFramebuffer: Bool,
        isAppForeground: Bool,
        userKeepsScreenAwake: Bool
    ) -> ScreenWakeResolution {
        guard isSessionLive(sessionState: sessionState, hasFramebuffer: hasFramebuffer) else {
            return ScreenWakeResolution(decision: .allowSleep, reason: .noSession)
        }
        guard userKeepsScreenAwake else {
            return ScreenWakeResolution(decision: .allowSleep, reason: .userDeclined)
        }
        guard isAppForeground else {
            return ScreenWakeResolution(decision: .allowSleep, reason: .appNotForeground)
        }
        return ScreenWakeResolution(decision: .holdAwake, reason: .sessionLive)
    }
}
