import Foundation

public enum DiagnosticStage: String, Codable, CaseIterable, Equatable, Sendable {
    case dns
    case tcp
    case rfbHandshake
    case authentication
    case firstFrame
    case clipboardText
}

public enum DiagnosticStatus: String, Codable, Equatable, Sendable {
    case notStarted
    case running
    case passed
    case failed
    case skipped
}

public struct DiagnosticStageResult: Codable, Equatable, Sendable {
    public let stage: DiagnosticStage
    public let status: DiagnosticStatus
    public let safeTitle: String
    public let safeDetail: String
    public let nextAction: String?
    public let timestamp: Date

    public init(
        stage: DiagnosticStage,
        status: DiagnosticStatus,
        safeTitle: String,
        safeDetail: String,
        nextAction: String? = nil,
        timestamp: Date = Date()
    ) {
        self.stage = stage
        self.status = status
        self.safeTitle = safeTitle
        self.safeDetail = safeDetail
        self.nextAction = nextAction
        self.timestamp = timestamp
    }
}

public struct ConnectionDiagnosticRun: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let profileID: ConnectionProfile.ID
    public let startedAt: Date
    public var finishedAt: Date?
    public var stages: [DiagnosticStageResult]

    public init(
        id: UUID = UUID(),
        profileID: ConnectionProfile.ID,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        stages: [DiagnosticStageResult] = []
    ) {
        self.id = id
        self.profileID = profileID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.stages = stages
    }

    public var firstFailedStage: DiagnosticStageResult? {
        stages.first { $0.status == .failed }
    }

    public var safeSummary: String {
        let finalStage = firstFailedStage ?? stages.last
        guard let finalStage else {
            return "Diagnostics have not started."
        }

        return "\(finalStage.safeTitle): \(finalStage.safeDetail)"
    }

    /// Reduces a diagnostic run to a single high-level verdict suitable
    /// for at-a-glance UI cues (e.g. the per-profile status dot in the
    /// sidebar).  Constitution §IV: this never returns raw stage detail
    /// strings — only the safe-catalog status enum.  The verdict is
    /// derived as follows:
    ///
    /// - `.failed` if any stage failed.
    /// - `.warning` if no stage failed but a stage was skipped (we
    ///   reached a degraded-but-usable state — e.g. clipboard text
    ///   path skipped on a server that does not advertise it).
    /// - `.passed` if every recorded stage passed and the run has
    ///   finished.
    /// - `.unknown` while the run is still in flight, or for empty
    ///   runs / runs with only `.notStarted` / `.running` stages.
    public var verdict: DiagnosticVerdict {
        if stages.contains(where: { $0.status == .failed }) {
            return .failed
        }
        guard finishedAt != nil else {
            return .unknown
        }
        if stages.isEmpty {
            return .unknown
        }
        if stages.contains(where: { $0.status == .skipped }) {
            return .warning
        }
        if stages.allSatisfy({ $0.status == .passed }) {
            return .passed
        }
        return .unknown
    }
}

/// At-a-glance diagnostic verdict for a profile's most recent
/// `ConnectionDiagnosticRun`.  Values are derived through
/// `ConnectionDiagnosticRun.verdict` only — there is no setter that
/// accepts caller-provided raw strings, which keeps this in line with
/// the constitution §IV "fixed safe-detail catalog" rule.
public enum DiagnosticVerdict: String, Codable, Equatable, Sendable {
    /// No diagnostic has been run yet, or the most recent run is
    /// still in progress.  UI should render this as a neutral cue
    /// (gray dot) and not imply success.
    case unknown
    /// Every recorded stage passed and the run has finished.
    case passed
    /// The run finished without a hard failure but at least one
    /// stage was skipped — the connection is reachable in a
    /// degraded form (e.g. text clipboard unavailable).
    case warning
    /// Some stage failed.  UI should render this as the strongest
    /// "do not tap blindly" cue (red dot).
    case failed
}

public enum DiagnosticMessageCatalog {
    public static func failure(
        for stage: DiagnosticStage,
        timestamp: Date = Date()
    ) -> DiagnosticStageResult {
        switch stage {
        case .dns:
            DiagnosticStageResult(
                stage: .dns,
                status: .failed,
                safeTitle: "MagicDNS did not resolve",
                safeDetail: "Check Tailscale status and the host name.",
                nextAction: "Open Tailscale and confirm this device is connected.",
                timestamp: timestamp
            )
        case .tcp:
            DiagnosticStageResult(
                stage: .tcp,
                status: .failed,
                safeTitle: "Host reached, VNC port closed",
                safeDetail: "The host resolved, but the VNC port is not reachable.",
                nextAction: "Check the VNC server and port.",
                timestamp: timestamp
            )
        case .rfbHandshake:
            DiagnosticStageResult(
                stage: .rfbHandshake,
                status: .failed,
                safeTitle: "VNC handshake failed",
                safeDetail: "The service did not complete a compatible RFB handshake.",
                nextAction: "Check the server type and security settings.",
                timestamp: timestamp
            )
        case .authentication:
            DiagnosticStageResult(
                stage: .authentication,
                status: .failed,
                safeTitle: "Authentication failed",
                safeDetail: "The VNC server rejected the supplied credentials.",
                nextAction: "Check the VNC password.",
                timestamp: timestamp
            )
        case .firstFrame:
            DiagnosticStageResult(
                stage: .firstFrame,
                status: .failed,
                safeTitle: "No frame received",
                safeDetail: "The session connected, but no remote frame arrived yet.",
                nextAction: "Try reconnecting or check the remote display state.",
                timestamp: timestamp
            )
        case .clipboardText:
            DiagnosticStageResult(
                stage: .clipboardText,
                status: .failed,
                safeTitle: "Text clipboard unavailable",
                safeDetail: "This server did not accept the text clipboard path.",
                nextAction: "Try a different server or wait for helper support.",
                timestamp: timestamp
            )
        }
    }
}
