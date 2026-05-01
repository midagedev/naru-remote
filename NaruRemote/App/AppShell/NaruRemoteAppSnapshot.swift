import Foundation
import NaruRemoteCore

public struct NaruRemoteAppSnapshot: Equatable, Sendable {
    public var profiles: [ConnectionProfile]
    public var selectedProfileID: ConnectionProfile.ID?
    public var session: RemoteSession?
    public var diagnosticRun: ConnectionDiagnosticRun?
    public var composeDraft: ComposeDraft?
    public var latestInjectionAttempt: TextInjectionAttempt?
    public var pipWatchSession: PiPWatchSession?
    public var latestFramebuffer: RFBRawFramebuffer?
    /// Damage rectangles for `latestFramebuffer`, when the most recent
    /// frame came from a damage-tracking source.  `nil` means the
    /// renderer should treat the framebuffer as a full-frame upload —
    /// this is the right default for first frames, the fallback path,
    /// and snapshot-driven previews that have no damage history.
    public var latestFrameDirtyRectangles: [RFBFrameDamageRect]?
    public var directKeystrokeMode: DirectKeystrokeMode

    public init(
        profiles: [ConnectionProfile] = [],
        selectedProfileID: ConnectionProfile.ID? = nil,
        session: RemoteSession? = nil,
        diagnosticRun: ConnectionDiagnosticRun? = nil,
        composeDraft: ComposeDraft? = nil,
        latestInjectionAttempt: TextInjectionAttempt? = nil,
        pipWatchSession: PiPWatchSession? = nil,
        latestFramebuffer: RFBRawFramebuffer? = nil,
        latestFrameDirtyRectangles: [RFBFrameDamageRect]? = nil,
        directKeystrokeMode: DirectKeystrokeMode = DirectKeystrokeMode()
    ) {
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
        self.session = session
        self.diagnosticRun = diagnosticRun
        self.composeDraft = composeDraft
        self.latestInjectionAttempt = latestInjectionAttempt
        self.pipWatchSession = pipWatchSession
        self.latestFramebuffer = latestFramebuffer
        self.latestFrameDirtyRectangles = latestFrameDirtyRectangles
        self.directKeystrokeMode = directKeystrokeMode
    }

    public var selectedProfile: ConnectionProfile? {
        guard let selectedProfileID else {
            return profiles.first
        }
        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    public var title: String {
        selectedProfile?.displayName ?? "Naru Remote"
    }

    public var subtitle: String {
        selectedProfile?.endpoint ?? "Private Network Remote Desktop"
    }

    public var inputStatusText: String {
        guard let latestInjectionAttempt else {
            return "Ready to compose locally"
        }

        switch latestInjectionAttempt.status {
        case .sent:
            return latestInjectionAttempt.safeMessage.isEmpty ? "Text accepted by remote target" : latestInjectionAttempt.safeMessage
        case .failed:
            return latestInjectionAttempt.safeMessage.isEmpty ? "Send failed; draft kept locally" : latestInjectionAttempt.safeMessage
        case .unknown:
            return latestInjectionAttempt.safeMessage.isEmpty ? "Confirmation unavailable; draft kept locally" : latestInjectionAttempt.safeMessage
        }
    }

    public var isPiPWatchAvailable: Bool {
        guard selectedProfile?.allowsPiPWatch ?? true else {
            return false
        }

        return session?.allowsPiPWatch ?? false
    }

    public var pipWatchStatusText: String {
        guard selectedProfile?.allowsPiPWatch ?? true else {
            return "PiP disabled for profile"
        }

        guard let pipWatchSession else {
            return isPiPWatchAvailable ? "PiP Watch ready" : "PiP after first frame"
        }

        switch pipWatchSession.state {
        case .unavailable:
            return "PiP unavailable"
        case .stopped:
            return "PiP Watch ready"
        case .preparing:
            return "Preparing PiP"
        case .watching:
            return "Watching in PiP"
        case .stale:
            return "PiP frame stale"
        case .failed:
            return "PiP failed"
        }
    }

    public var onboardingGuide: OnboardingGuide {
        OnboardingGuide(
            profile: selectedProfile,
            session: session,
            diagnosticRun: diagnosticRun,
            latestInjectionAttempt: latestInjectionAttempt,
            pipWatchSession: pipWatchSession
        )
    }

    public var diagnosticRows: [DiagnosticSummaryRow] {
        diagnosticRun?.stages.enumerated().map { index, stage in
            DiagnosticSummaryRow(
                id: "\(index)-\(stage.stage.rawValue)-\(stage.status.rawValue)",
                stage: stage.stage.rawValue,
                status: stage.status.rawValue,
                title: stage.safeTitle,
                detail: stage.safeDetail
            )
        } ?? []
    }
}

public struct DiagnosticSummaryRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let stage: String
    public let status: String
    public let title: String
    public let detail: String

    public init(
        id: String,
        stage: String,
        status: String,
        title: String,
        detail: String
    ) {
        self.id = id
        self.stage = stage
        self.status = status
        self.title = title
        self.detail = detail
    }
}
