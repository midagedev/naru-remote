import Foundation

/// System-reported login-item registration state (spec 041 FR-006).
public enum NaruHelperLoginItemState: Equatable, Sendable {
    /// Not registered — the helper does not start at login.
    case off
    /// Registered and enabled.
    case on
    /// Registered but the system is holding it for user approval
    /// (macOS 13+ `SMAppService.requiresApproval`) — surfaced to the
    /// user with a route to Login Items settings, never retried in a
    /// loop: approval is a user decision, not a race to win.
    case requiresApproval
    /// The service API is unavailable or the request failed — retrying
    /// with the same input is the app's call, the toggle just reports.
    case unavailable
}

/// The seam over the system login-item service. The Kit deliberately has
/// no `ServiceManagement` import (spec 041 plan: the `SMAppService`
/// conformance lives in the app target, which is what macOS notarization
/// and the bundle identity belong to); tests conform a fake.
public protocol NaruHelperLoginItemControlling: Sendable {
    func register() throws
    func unregister() throws
    func status() -> NaruHelperLoginItemState
}

/// Pure transition (spec 041 T-A7): applies the desired on/off to a
/// controller and returns the **system-reported** result — the toggle
/// never asserts success from its own request having been sent. A
/// throwing register/unregister maps to `.unavailable`; a controller
/// reporting `.requiresApproval` is surfaced as-is, not retried.
public struct NaruHelperLoginItemToggle: Sendable {
    public let desiredEnabled: Bool

    public init(desiredEnabled: Bool) {
        self.desiredEnabled = desiredEnabled
    }

    public func apply(
        controller: any NaruHelperLoginItemControlling
    ) -> NaruHelperLoginItemState {
        do {
            if desiredEnabled {
                try controller.register()
            } else {
                try controller.unregister()
            }
        } catch {
            return .unavailable
        }
        return controller.status()
    }
}
