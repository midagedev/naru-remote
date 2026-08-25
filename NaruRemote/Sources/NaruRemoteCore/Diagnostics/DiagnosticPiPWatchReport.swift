import Foundation

/// PiP Watch lifecycle, as it appears in a diagnostic export.
///
/// Spec 032 FR-006. The founder's "PiP 두 번 켜면 앱이 꺼진다" could not be
/// answered from an export at all: nothing about PiP reached one, so
/// establishing what the app had even asked the system to do required reading
/// code. These are counts and one fixed label — no window geometry, no system
/// error strings (constitution §IV).
public struct DiagnosticPiPWatchReport: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case pipEntryRequestCount
        case pipControllerCreationCount
        case pipStartRefusalCount
        case pipStartFailureCount
        case pipSystemDismissalCount
        case pipLastStopReason
        case pipPhase
    }

    /// Entries the app asked for, refused or not.
    public let pipEntryRequestCount: Int
    /// System controllers constructed. More than one per session means the
    /// invariant spec 032 FR-001 establishes has broken.
    public let pipControllerCreationCount: Int
    public let pipStartRefusalCount: Int
    public let pipStartFailureCount: Int
    /// Times the system took the window away without the app asking.
    public let pipSystemDismissalCount: Int
    public let pipLastStopReason: String
    public let pipPhase: String

    public init(
        pipEntryRequestCount: Int,
        pipControllerCreationCount: Int,
        pipStartRefusalCount: Int,
        pipStartFailureCount: Int,
        pipSystemDismissalCount: Int,
        pipLastStopReason: String,
        pipPhase: String
    ) {
        self.pipEntryRequestCount = max(0, pipEntryRequestCount)
        self.pipControllerCreationCount = max(0, pipControllerCreationCount)
        self.pipStartRefusalCount = max(0, pipStartRefusalCount)
        self.pipStartFailureCount = max(0, pipStartFailureCount)
        self.pipSystemDismissalCount = max(0, pipSystemDismissalCount)
        self.pipLastStopReason = PiPWatchDiagnosticCatalog.stopReason(pipLastStopReason)
        self.pipPhase = PiPWatchDiagnosticCatalog.phase(pipPhase)
    }

    public init(lifecycle: PiPWatchControllerLifecycle) {
        self.init(
            pipEntryRequestCount: lifecycle.entryRequestCount,
            pipControllerCreationCount: lifecycle.controllerCreationCount,
            pipStartRefusalCount: lifecycle.startRefusalCount,
            pipStartFailureCount: lifecycle.startFailureCount,
            pipSystemDismissalCount: lifecycle.systemDismissalCount,
            pipLastStopReason: lifecycle.lastStopReason.rawValue,
            pipPhase: lifecycle.phase.rawValue
        )
    }
}

/// Closed vocabularies for the two label fields, re-checked on the way in and
/// on the way out of JSON — the pattern spec 031's rung catalog established.
public enum PiPWatchDiagnosticCatalog {
    public static let unknown = "unknown"

    public static func stopReason(_ value: String) -> String {
        PiPWatchStopReason(rawValue: value)?.rawValue ?? unknown
    }

    public static func phase(_ value: String) -> String {
        PiPWatchControllerLifecycle.Phase(rawValue: value)?.rawValue ?? unknown
    }
}
