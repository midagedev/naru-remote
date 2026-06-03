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

public enum DiagnosticRunTrigger: String, Codable, Equatable, Sendable {
    case manualChecks
    case connect
    case streamDrop
    case reconnect
    case credentialLookup
}

public enum DiagnosticDurationBucket: String, Codable, Equatable, Sendable {
    case notMeasured
    case underOneSecond
    case oneToThreeSeconds
    case threeToTenSeconds
    case overTenSeconds

    public static func bucket(startedAt: Date, finishedAt: Date?) -> DiagnosticDurationBucket {
        guard let finishedAt else {
            return .notMeasured
        }

        return bucket(duration: finishedAt.timeIntervalSince(startedAt))
    }

    public static func bucket(duration seconds: TimeInterval?) -> DiagnosticDurationBucket {
        guard let seconds else {
            return .notMeasured
        }

        let durationSeconds = max(0, seconds)
        switch durationSeconds {
        case ..<1:
            return .underOneSecond
        case ..<3:
            return .oneToThreeSeconds
        case ..<10:
            return .threeToTenSeconds
        default:
            return .overTenSeconds
        }
    }
}

public struct DiagnosticRunContext: Codable, Equatable, Sendable {
    public let targetFingerprint: String?
    public let profileHostKind: String?
    public let configuredPort: Int?
    public let hasCredentialReference: Bool?
    public let trigger: DiagnosticRunTrigger?
    public let probeTimeoutSeconds: Double?

    public init(
        targetFingerprint: String? = nil,
        profileHostKind: String? = nil,
        configuredPort: Int? = nil,
        hasCredentialReference: Bool? = nil,
        trigger: DiagnosticRunTrigger? = nil,
        probeTimeoutSeconds: Double? = nil
    ) {
        self.targetFingerprint = targetFingerprint
        self.profileHostKind = profileHostKind
        self.configuredPort = configuredPort
        self.hasCredentialReference = hasCredentialReference
        self.trigger = trigger
        self.probeTimeoutSeconds = probeTimeoutSeconds
    }
}

public struct DiagnosticStageMetadata: Codable, Equatable, Sendable {
    public let failureCode: String?

    public init(failureCode: String? = nil) {
        self.failureCode = failureCode
    }
}

public struct DiagnosticStageResult: Codable, Equatable, Sendable {
    public let stage: DiagnosticStage
    public let status: DiagnosticStatus
    public let safeTitle: String
    public let safeDetail: String
    public let nextAction: String?
    public let timestamp: Date
    public let metadata: DiagnosticStageMetadata?

    public init(
        stage: DiagnosticStage,
        status: DiagnosticStatus,
        safeTitle: String,
        safeDetail: String,
        nextAction: String? = nil,
        timestamp: Date = Date(),
        metadata: DiagnosticStageMetadata? = nil
    ) {
        self.stage = stage
        self.status = status
        self.safeTitle = safeTitle
        self.safeDetail = safeDetail
        self.nextAction = nextAction
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public struct ConnectionDiagnosticRun: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let profileID: ConnectionProfile.ID
    public let startedAt: Date
    public var finishedAt: Date?
    public var context: DiagnosticRunContext?
    public var stages: [DiagnosticStageResult]

    public init(
        id: UUID = UUID(),
        profileID: ConnectionProfile.ID,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        context: DiagnosticRunContext? = nil,
        stages: [DiagnosticStageResult] = []
    ) {
        self.id = id
        self.profileID = profileID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.context = context
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
        timestamp: Date = Date(),
        metadata: DiagnosticStageMetadata? = nil
    ) -> DiagnosticStageResult {
        switch stage {
        case .dns:
            DiagnosticStageResult(
                stage: .dns,
                status: .failed,
                safeTitle: "MagicDNS did not resolve",
                safeDetail: "Check Tailscale status and the host name.",
                nextAction: "Open Tailscale and confirm this device is connected.",
                timestamp: timestamp,
                metadata: metadata
            )
        case .tcp:
            DiagnosticStageResult(
                stage: .tcp,
                status: .failed,
                safeTitle: "Host reached, VNC port closed",
                safeDetail: "VNC port did not respond. The host may be off, the port may be closed, or your iPhone's Local Network permission may be denied for Naru Remote.",
                nextAction: "On iOS: Settings → Naru Remote → Local Network. On the host: confirm port 5900 is open.",
                timestamp: timestamp,
                metadata: metadata
            )
        case .rfbHandshake:
            DiagnosticStageResult(
                stage: .rfbHandshake,
                status: .failed,
                safeTitle: "VNC handshake failed",
                safeDetail: "The server did not offer a compatible RFB security type. macOS hosts must enable 'VNC viewers may control screen with password' in System Settings → General → Sharing → Screen Sharing → ⓘ.",
                nextAction: "Enable the VNC viewers checkbox in macOS Sharing settings.",
                timestamp: timestamp,
                metadata: metadata
            )
        case .authentication:
            DiagnosticStageResult(
                stage: .authentication,
                status: .failed,
                safeTitle: "Authentication failed",
                safeDetail: "The VNC password was rejected. macOS uses a separate VNC password from your account password — set it in System Settings → General → Sharing → Screen Sharing → ⓘ. VNC Auth uses only the first 8 characters.",
                nextAction: "Re-check the VNC password (first 8 chars only) under macOS Sharing settings.",
                timestamp: timestamp,
                metadata: metadata
            )
        case .firstFrame:
            DiagnosticStageResult(
                stage: .firstFrame,
                status: .failed,
                safeTitle: "No frame received",
                safeDetail: "The session connected, but no remote frame arrived yet.",
                nextAction: "Try reconnecting or check the remote display state.",
                timestamp: timestamp,
                metadata: metadata
            )
        case .clipboardText:
            DiagnosticStageResult(
                stage: .clipboardText,
                status: .failed,
                safeTitle: "Text clipboard unavailable",
                safeDetail: "This server did not accept the text clipboard path.",
                nextAction: "Try a different server or wait for helper support.",
                timestamp: timestamp,
                metadata: metadata
            )
        }
    }

    /// Safe-catalog success message for the profile-editor "Test"
    /// affordance.  The editor's reachability check runs before the
    /// profile is persisted, so the verdict is informational only —
    /// constitution §IV still requires that the rendered string come
    /// from the catalog and never from a raw network error.
    ///
    /// Two variants are surfaced:
    ///
    /// - `requiresAuthentication: false` — the server accepted the
    ///   no-auth path, suggesting the VNC server is configured for
    ///   anonymous access.
    /// - `requiresAuthentication: true` — the server advertised a
    ///   security type that requires a password.  The Test affordance
    ///   does not actually authenticate (the entered password may not
    ///   be saved yet), so reaching this point still counts as
    ///   "reachable" — the user just needs to provide a credential
    ///   before connect.
    public static func reachabilitySuccess(
        host: String,
        port: Int,
        requiresAuthentication: Bool,
        timestamp: Date = Date()
    ) -> DiagnosticStageResult {
        let endpoint = "\(host):\(port)"
        let detail = requiresAuthentication
            ? "\(endpoint) — reachable, requires VNC password."
            : "\(endpoint) — reachable, no password required."
        return DiagnosticStageResult(
            stage: .rfbHandshake,
            status: .passed,
            safeTitle: "Reachable",
            safeDetail: detail,
            nextAction: nil,
            timestamp: timestamp
        )
    }
}

/// One-shot verdict + safe-catalog message returned by the profile
/// editor's "Test" affordance.  The editor renders `safeMessage`
/// verbatim under the form (constitution §IV — no caller-provided
/// raw strings reach the UI).  `verdict` drives the foreground color
/// (Coral on `.failed`, ink/secondary on `.passed`).
public struct ProfileEditorTestOutcome: Equatable, Sendable {
    public let verdict: DiagnosticVerdict
    public let safeMessage: String

    public init(verdict: DiagnosticVerdict, safeMessage: String) {
        self.verdict = verdict
        self.safeMessage = safeMessage
    }
}
