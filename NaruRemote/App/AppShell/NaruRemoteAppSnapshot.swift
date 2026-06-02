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
    /// Most recent server-provided cursor shape, decoded from the RFB
    /// Cursor pseudo-encoding. This is additive to the synthetic
    /// trackpad cursor and is memory-only.
    public var latestServerCursor: RFBServerCursor?
    /// Local-only, downsampled preview thumbnails keyed by profile id.
    /// These are recognition aids for the connection grid. They are
    /// never exported in diagnostics or sent to a remote host.
    public var profilePreviews: [ConnectionProfile.ID: ProfilePreviewThumbnail]
    /// Memory-only launch probe state keyed by profile id. These are
    /// refreshed on app entry and profile edits; stale states are not
    /// persisted as truth.
    public var profileReachability: [ConnectionProfile.ID: ProfileReachabilityState]
    public var directKeystrokeMode: DirectKeystrokeMode
    /// Sticky modifier slot state for the Direct-mode special-keys
    /// page (Phase 4 / US-2).  Mirrors the `directKeystrokeMode`
    /// pattern — pure value type carried on the snapshot so views
    /// render off the snapshot, not by reaching back into the
    /// `@MainActor` model directly.
    public var stickyModifierState: StickyModifierState
    /// Per-profile diagnostic verdict cache (UX punch-list #109).
    /// Memory-only — never persisted.  Populated whenever a
    /// `ConnectionDiagnosticRun` finishes for a profile so the
    /// sidebar can render a colored status dot at a glance without
    /// re-running diagnostics on every render.  Profiles missing
    /// from this map are rendered as `.unknown` (gray).  Constitution
    /// §IV: the verdict is derived through `ConnectionDiagnosticRun
    /// .verdict` — never from caller-provided strings.
    public var lastDiagnosticVerdict: [ConnectionProfile.ID: DiagnosticVerdict]

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
        latestServerCursor: RFBServerCursor? = nil,
        profilePreviews: [ConnectionProfile.ID: ProfilePreviewThumbnail] = [:],
        profileReachability: [ConnectionProfile.ID: ProfileReachabilityState] = [:],
        directKeystrokeMode: DirectKeystrokeMode = DirectKeystrokeMode(),
        stickyModifierState: StickyModifierState = StickyModifierState(),
        lastDiagnosticVerdict: [ConnectionProfile.ID: DiagnosticVerdict] = [:]
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
        self.latestServerCursor = latestServerCursor
        self.profilePreviews = profilePreviews
        self.profileReachability = profileReachability
        self.directKeystrokeMode = directKeystrokeMode
        self.stickyModifierState = stickyModifierState
        self.lastDiagnosticVerdict = lastDiagnosticVerdict
    }

    public var selectedProfile: ConnectionProfile? {
        guard let selectedProfileID else {
            return profiles.first
        }
        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    public var title: String {
        // Empty-state hero copy is intentionally actionable rather than
        // marketing — see UX punch-list #201 / `BRANDING.md` §9.1.
        // The product name lives on the sidebar nav bar and Settings
        // → About; the home detail column should tell the user what
        // to do next, not what they bought.
        selectedProfile?.displayName ?? "Pick a computer"
    }

    public var subtitle: String {
        selectedProfile?.endpoint ?? "Choose a profile from the sidebar to begin."
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

    public var connectionGridCards: [ConnectionGridCard] {
        profiles.map { profile in
            ConnectionGridCard(
                id: profile.id,
                displayName: profile.displayName,
                endpoint: profile.endpoint,
                hostKind: profile.hostKind,
                preview: profilePreviews[profile.id],
                reachability: profileReachability[profile.id] ?? .unknown,
                verdict: lastDiagnosticVerdict[profile.id] ?? .unknown,
                isSelected: selectedProfile?.id == profile.id
            )
        }
    }
}

public struct ConnectionGridCard: Equatable, Sendable, Identifiable {
    public let id: ConnectionProfile.ID
    public let displayName: String
    public let endpoint: String
    public let hostKind: ConnectionProfile.HostKind
    public let preview: ProfilePreviewThumbnail?
    public let reachability: ProfileReachabilityState
    public let verdict: DiagnosticVerdict
    public let isSelected: Bool

    public init(
        id: ConnectionProfile.ID,
        displayName: String,
        endpoint: String,
        hostKind: ConnectionProfile.HostKind,
        preview: ProfilePreviewThumbnail? = nil,
        reachability: ProfileReachabilityState = .unknown,
        verdict: DiagnosticVerdict,
        isSelected: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.endpoint = endpoint
        self.hostKind = hostKind
        self.preview = preview
        self.reachability = reachability
        self.verdict = verdict
        self.isSelected = isSelected
    }
}

public enum ProfileReachabilityState: Equatable, Sendable {
    case unknown
    case checking
    case reachable
    case needsPassword
    case unreachable(failedStage: DiagnosticStage)
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
