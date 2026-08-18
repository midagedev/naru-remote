import Foundation

/// Single owner of "which of the two primary screens is on".
///
/// The app has exactly two primary surfaces — the host list and remote
/// control — and this decides between them from session facts alone. It is a
/// derivation, not a command: nothing sets a "which screen" flag on tap and
/// then corrects it afterwards. That correction dance is what produced a
/// visible third screen twice: first the failure overlay (spec 013), then the
/// pre-first-frame connecting state, reported from a device on 2026-08-19.
///
/// The rule the founder chose: **connecting belongs to the host list.** The
/// card that was tapped shows the progress and offers cancel, and remote
/// control opens only when there is a remote screen to control. So the remote
/// control surface has one invariant worth keeping — it is never empty.
public enum RemoteControlSurfacePolicy: Sendable {
    public enum Phase: Equatable, Sendable {
        /// Host list: no session, or one that has ended.
        case hostList
        /// Host list, with the tapped card reporting progress.
        case connecting
        /// Remote control: a remote screen exists (or existed, mid-reconnect).
        case remoteControl
    }

    public static func phase(
        sessionState: RemoteSessionState?,
        hasFramebuffer: Bool
    ) -> Phase {
        guard let sessionState else {
            return .hostList
        }
        switch sessionState {
        case .failed, .closed:
            // Terminal even with a stale framebuffer: a dropped session must
            // not leave the user holding a frozen screen. The card carries the
            // reason (`ConnectionGridCardFailure`).
            return .hostList
        case .connecting, .authenticating:
            // A retained framebuffer means this is a mid-session blip, not an
            // entry, so it stays on remote control.
            return hasFramebuffer ? .remoteControl : .connecting
        case .active, .degraded, .reconnecting:
            // `.active` is set by `RemoteSession.markFirstFrameReceived`, so
            // reaching it means a frame has arrived; the other two imply one
            // arrived earlier.
            return .remoteControl
        }
    }

    /// Two screenshot/UI-test hooks, deliberately not one:
    ///
    /// - `isPinnedForTesting` mounts the surface with no session at all, for
    ///   captures of the dock itself.
    /// - `retainsEndedSessionForTesting` keeps the surface after a session
    ///   reaches a state that would otherwise return to the list. Audit
    ///   captures reach the dock by tapping a card whose connect fails
    ///   immediately (no credential), and they still need the host list to be
    ///   there to tap — so this one must not preempt the grid before a session
    ///   exists. Collapsing the two hooks into one made every card-tap capture
    ///   fail to find a card.
    public static func showsRemoteControl(
        sessionState: RemoteSessionState?,
        hasFramebuffer: Bool,
        isPinnedForTesting: Bool = false,
        retainsEndedSessionForTesting: Bool = false
    ) -> Bool {
        if isPinnedForTesting {
            return true
        }
        if retainsEndedSessionForTesting, sessionState != nil {
            return true
        }
        return phase(sessionState: sessionState, hasFramebuffer: hasFramebuffer) == .remoteControl
    }
}
