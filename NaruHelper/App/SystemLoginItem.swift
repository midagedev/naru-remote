import ServiceManagement
import NaruHelperKit

/// The app-target side of the login-item seam (spec 041 T-A7): the Kit
/// owns the protocol and the pure transition; this type owns the
/// `ServiceManagement` import, because registration is bound to this
/// bundle's identity — exactly where notarization and the bundle id live.
@MainActor
enum SystemLoginItem {
    static let shared: any NaruHelperLoginItemControlling = LiveSystemLoginItem()

    /// Deep-link to Login Items settings (spec 041 FR-006), offered when
    /// the system reports `.requiresApproval`.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Wraps `SMAppService.mainApp`. `status` maps one-to-one onto
/// `NaruHelperLoginItemState`; `.requiresApproval` surfaces as-is —
/// approval is a user decision, never retried in a loop. `SMAppService`
/// is queried per call rather than stored: it is not `Sendable`, and the
/// conformance must be. The wrapper itself is stateless (the Kit
/// protocol is nonisolated, so an actor-isolated conformance would be
/// rejected); every call site lives on the main actor.
private struct LiveSystemLoginItem: NaruHelperLoginItemControlling {
    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func status() -> NaruHelperLoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .requiresApproval
        case .notRegistered: .off
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
}
