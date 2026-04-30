import Foundation

public enum OnboardingStepID: String, Codable, CaseIterable, Equatable, Sendable {
    case privateTarget
    case diagnostics
    case compose
    case pipWatch
}

public enum OnboardingStepState: String, Codable, Equatable, Sendable {
    case complete
    case next
    case waiting
    case blocked
}

public struct OnboardingStep: Codable, Equatable, Identifiable, Sendable {
    public let id: OnboardingStepID
    public let state: OnboardingStepState
    public let title: String
    public let detail: String
    public let actionTitle: String?

    public init(
        id: OnboardingStepID,
        state: OnboardingStepState,
        title: String,
        detail: String,
        actionTitle: String? = nil
    ) {
        self.id = id
        self.state = state
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
    }
}

public struct OnboardingGuide: Codable, Equatable, Sendable {
    public let steps: [OnboardingStep]

    public init(
        profile: ConnectionProfile?,
        session: RemoteSession? = nil,
        diagnosticRun: ConnectionDiagnosticRun? = nil,
        latestInjectionAttempt: TextInjectionAttempt? = nil,
        pipWatchSession: PiPWatchSession? = nil
    ) {
        self.steps = [
            Self.privateTargetStep(profile: profile),
            Self.diagnosticsStep(profile: profile, diagnosticRun: diagnosticRun),
            Self.composeStep(session: session, latestInjectionAttempt: latestInjectionAttempt),
            Self.pipWatchStep(profile: profile, session: session, pipWatchSession: pipWatchSession)
        ]
    }

    public var firstActionableStep: OnboardingStep? {
        steps.first { $0.state == .next || $0.state == .blocked }
    }

    public var isComplete: Bool {
        steps.allSatisfy { $0.state == .complete }
    }

    private static func privateTargetStep(profile: ConnectionProfile?) -> OnboardingStep {
        guard let profile else {
            return OnboardingStep(
                id: .privateTarget,
                state: .next,
                title: "Private target",
                detail: "Add a MagicDNS name or private host.",
                actionTitle: "Add Profile"
            )
        }

        switch profile.hostKind {
        case .magicDNS, .privateAddress:
            return OnboardingStep(
                id: .privateTarget,
                state: .complete,
                title: "Private target",
                detail: "Private profile selected."
            )
        case .advancedManualPublicEndpoint:
            return OnboardingStep(
                id: .privateTarget,
                state: .blocked,
                title: "Private target",
                detail: "Public endpoint is advanced.",
                actionTitle: "Review"
            )
        }
    }

    private static func diagnosticsStep(
        profile: ConnectionProfile?,
        diagnosticRun: ConnectionDiagnosticRun?
    ) -> OnboardingStep {
        guard profile != nil else {
            return OnboardingStep(
                id: .diagnostics,
                state: .waiting,
                title: "Connection checks",
                detail: "Create a profile first."
            )
        }

        guard let diagnosticRun else {
            return OnboardingStep(
                id: .diagnostics,
                state: .next,
                title: "Connection checks",
                detail: "Run DNS, TCP, and VNC checks.",
                actionTitle: "Run Checks"
            )
        }

        if let failedStage = diagnosticRun.firstFailedStage {
            return OnboardingStep(
                id: .diagnostics,
                state: .blocked,
                title: "Connection checks",
                detail: failedStage.safeTitle,
                actionTitle: "Fix"
            )
        }

        if diagnosticRun.stages.contains(where: { $0.status == .running }) {
            return OnboardingStep(
                id: .diagnostics,
                state: .waiting,
                title: "Connection checks",
                detail: "Checks are running."
            )
        }

        return OnboardingStep(
            id: .diagnostics,
            state: .complete,
            title: "Connection checks",
            detail: "No blocking failure."
        )
    }

    private static func composeStep(
        session: RemoteSession?,
        latestInjectionAttempt: TextInjectionAttempt?
    ) -> OnboardingStep {
        if latestInjectionAttempt?.status == .unknown {
            return OnboardingStep(
                id: .compose,
                state: .complete,
                title: "Compose locally",
                detail: "Last send kept local text until confirmation."
            )
        }

        guard let session, session.state.allowsRemoteCompose else {
            return OnboardingStep(
                id: .compose,
                state: .waiting,
                title: "Compose locally",
                detail: "Open a remote session first."
            )
        }

        return OnboardingStep(
            id: .compose,
            state: .complete,
            title: "Compose locally",
            detail: "Local text entry is ready."
        )
    }

    private static func pipWatchStep(
        profile: ConnectionProfile?,
        session: RemoteSession?,
        pipWatchSession: PiPWatchSession?
    ) -> OnboardingStep {
        if profile?.allowsPiPWatch == false {
            return OnboardingStep(
                id: .pipWatch,
                state: .blocked,
                title: "PiP Watch",
                detail: "Disabled for this profile."
            )
        }

        if pipWatchSession?.state == .watching {
            return OnboardingStep(
                id: .pipWatch,
                state: .complete,
                title: "PiP Watch",
                detail: "Watch-only monitor is active."
            )
        }

        guard session?.allowsPiPWatch == true else {
            return OnboardingStep(
                id: .pipWatch,
                state: .waiting,
                title: "PiP Watch",
                detail: "Available after first frame."
            )
        }

        return OnboardingStep(
            id: .pipWatch,
            state: .waiting,
            title: "PiP Watch",
            detail: "Renderer validation is pending."
        )
    }
}

public extension RemoteSessionState {
    var allowsRemoteCompose: Bool {
        switch self {
        case .active, .degraded, .reconnecting:
            return true
        case .connecting, .authenticating, .failed, .closed:
            return false
        }
    }
}
