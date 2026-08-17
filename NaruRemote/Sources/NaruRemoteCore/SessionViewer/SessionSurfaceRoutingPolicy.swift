import Foundation

/// Pure routing predicate for the two primary surfaces: host list and
/// remote control. Failed or closed sessions with no framebuffer belong
/// on the host list; connecting and live sessions stay on remote control.
///
/// The screenshot / UI-test pin keeps a deliberately failed fixture on
/// the remote-control surface so dock captures can still mount.
public enum SessionSurfaceRoutingPolicy: Sendable {
    public static func shouldLeaveOperationSurface(
        sessionState: RemoteSessionState?,
        hasFramebuffer: Bool,
        isOperationSurfaceVisible: Bool,
        isPinnedForTesting: Bool
    ) -> Bool {
        guard isOperationSurfaceVisible, !isPinnedForTesting else {
            return false
        }
        guard !hasFramebuffer, let sessionState else {
            return false
        }
        switch sessionState {
        case .failed, .closed:
            return true
        case .connecting, .authenticating, .active, .degraded, .reconnecting:
            return false
        }
    }
}
