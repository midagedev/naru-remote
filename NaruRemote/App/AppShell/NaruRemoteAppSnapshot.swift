import Foundation
import NaruRemoteCore

public enum SessionStreamThermalState: String, Equatable, Sendable {
    case unknown
    case nominal
    case fair
    case serious
    case critical

    public init(_ thermalState: ProcessInfo.ThermalState) {
        switch thermalState {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .unknown
        }
    }
}

public struct SessionStreamStats: Equatable, Sendable {
    public var deliveredFrameCount: Int
    public var contentFrameCount: Int
    public var emptyUpdateCount: Int
    public var transportIdleTimeoutCount: Int
    public var dirtyRectangleSampleCount: Int
    public var dirtyRectangleCountTotal: Int
    public var dirtyRectangleCountMax: Int
    public var dirtyAreaPermilleTotal: Int
    public var dirtyAreaPermilleMax: Int
    public var changedPixelsPermilleTotal: Int
    public var changedPixelsPermilleMax: Int
    public var rendererUploadSampleCount: Int
    public var rendererPartialUploadCount: Int
    public var rendererFullUploadCount: Int
    public var rendererUploadRegionCountMax: Int
    public var rendererUploadTimingSampleCount: Int
    public var rendererUploadMillisecondsTotal: Int
    public var rendererUploadMillisecondsMax: Int
    public var receiveTimingSampleCount: Int
    public var receiveTotalMillisecondsTotal: Int
    public var receiveTotalMillisecondsMax: Int
    public var networkReadMillisecondsTotal: Int
    public var networkReadMillisecondsMax: Int
    public var clientProcessingMillisecondsTotal: Int
    public var clientProcessingMillisecondsMax: Int
    public var appFrameApplyTimingSampleCount: Int
    public var appFrameApplyMillisecondsTotal: Int
    public var appFrameApplyMillisecondsMax: Int
    public var adaptiveClientPressurePacingSampleCount: Int
    public var actualEncodingMix: RFBFramebufferEncodingMix
    public var thermalState: SessionStreamThermalState
    public var firstFrameCapturedAt: Date?
    public var latestFrameCapturedAt: Date?
    // Internal-only renderer planning cache. It is not exported in
    // diagnostics; only aggregate upload strategy counts leave memory.
    private var lastFramebufferWidth: Int?
    private var lastFramebufferHeight: Int?

    public init(
        deliveredFrameCount: Int = 0,
        contentFrameCount: Int = 0,
        emptyUpdateCount: Int = 0,
        transportIdleTimeoutCount: Int = 0,
        dirtyRectangleSampleCount: Int = 0,
        dirtyRectangleCountTotal: Int = 0,
        dirtyRectangleCountMax: Int = 0,
        dirtyAreaPermilleTotal: Int = 0,
        dirtyAreaPermilleMax: Int = 0,
        changedPixelsPermilleTotal: Int = 0,
        changedPixelsPermilleMax: Int = 0,
        rendererUploadSampleCount: Int = 0,
        rendererPartialUploadCount: Int = 0,
        rendererFullUploadCount: Int = 0,
        rendererUploadRegionCountMax: Int = 0,
        rendererUploadTimingSampleCount: Int = 0,
        rendererUploadMillisecondsTotal: Int = 0,
        rendererUploadMillisecondsMax: Int = 0,
        receiveTimingSampleCount: Int = 0,
        receiveTotalMillisecondsTotal: Int = 0,
        receiveTotalMillisecondsMax: Int = 0,
        networkReadMillisecondsTotal: Int = 0,
        networkReadMillisecondsMax: Int = 0,
        clientProcessingMillisecondsTotal: Int = 0,
        clientProcessingMillisecondsMax: Int = 0,
        appFrameApplyTimingSampleCount: Int = 0,
        appFrameApplyMillisecondsTotal: Int = 0,
        appFrameApplyMillisecondsMax: Int = 0,
        adaptiveClientPressurePacingSampleCount: Int = 0,
        actualEncodingMix: RFBFramebufferEncodingMix = RFBFramebufferEncodingMix(),
        thermalState: SessionStreamThermalState = .unknown,
        firstFrameCapturedAt: Date? = nil,
        latestFrameCapturedAt: Date? = nil
    ) {
        self.deliveredFrameCount = max(deliveredFrameCount, 0)
        self.contentFrameCount = max(contentFrameCount, 0)
        self.emptyUpdateCount = max(emptyUpdateCount, 0)
        self.transportIdleTimeoutCount = max(transportIdleTimeoutCount, 0)
        self.dirtyRectangleSampleCount = max(dirtyRectangleSampleCount, 0)
        self.dirtyRectangleCountTotal = max(dirtyRectangleCountTotal, 0)
        self.dirtyRectangleCountMax = max(dirtyRectangleCountMax, 0)
        self.dirtyAreaPermilleTotal = max(dirtyAreaPermilleTotal, 0)
        self.dirtyAreaPermilleMax = max(dirtyAreaPermilleMax, 0)
        self.changedPixelsPermilleTotal = max(changedPixelsPermilleTotal, 0)
        self.changedPixelsPermilleMax = max(changedPixelsPermilleMax, 0)
        self.rendererUploadSampleCount = max(rendererUploadSampleCount, 0)
        self.rendererPartialUploadCount = max(rendererPartialUploadCount, 0)
        self.rendererFullUploadCount = max(rendererFullUploadCount, 0)
        self.rendererUploadRegionCountMax = max(rendererUploadRegionCountMax, 0)
        self.rendererUploadTimingSampleCount = max(rendererUploadTimingSampleCount, 0)
        self.rendererUploadMillisecondsTotal = max(rendererUploadMillisecondsTotal, 0)
        self.rendererUploadMillisecondsMax = max(rendererUploadMillisecondsMax, 0)
        self.receiveTimingSampleCount = max(receiveTimingSampleCount, 0)
        self.receiveTotalMillisecondsTotal = max(receiveTotalMillisecondsTotal, 0)
        self.receiveTotalMillisecondsMax = max(receiveTotalMillisecondsMax, 0)
        self.networkReadMillisecondsTotal = max(networkReadMillisecondsTotal, 0)
        self.networkReadMillisecondsMax = max(networkReadMillisecondsMax, 0)
        self.clientProcessingMillisecondsTotal = max(clientProcessingMillisecondsTotal, 0)
        self.clientProcessingMillisecondsMax = max(clientProcessingMillisecondsMax, 0)
        self.appFrameApplyTimingSampleCount = max(appFrameApplyTimingSampleCount, 0)
        self.appFrameApplyMillisecondsTotal = max(appFrameApplyMillisecondsTotal, 0)
        self.appFrameApplyMillisecondsMax = max(appFrameApplyMillisecondsMax, 0)
        self.adaptiveClientPressurePacingSampleCount = min(
            max(adaptiveClientPressurePacingSampleCount, 0),
            self.deliveredFrameCount
        )
        self.actualEncodingMix = actualEncodingMix
        self.thermalState = thermalState
        self.firstFrameCapturedAt = firstFrameCapturedAt
        self.latestFrameCapturedAt = latestFrameCapturedAt
    }

    public var averageDirtyRectangleCount: Int? {
        average(dirtyRectangleCountTotal)
    }

    public var averageDirtyAreaPermille: Int? {
        average(dirtyAreaPermilleTotal)
    }

    public var averageChangedPixelsPermille: Int? {
        average(changedPixelsPermilleTotal)
    }

    public var observedDuration: TimeInterval? {
        guard deliveredFrameCount > 1,
              let firstFrameCapturedAt,
              let latestFrameCapturedAt
        else {
            return nil
        }
        return max(0, latestFrameCapturedAt.timeIntervalSince(firstFrameCapturedAt))
    }

    public var observedDurationBucket: DiagnosticDurationBucket {
        DiagnosticDurationBucket.bucket(duration: observedDuration)
    }

    public var deliveredFramesPerSecondBucket: DiagnosticFrameRateBucket {
        DiagnosticFrameRateBucket.bucket(
            deliveredFrameCount: deliveredFrameCount,
            observedDurationSeconds: observedDuration
        )
    }

    public var contentFramePermille: Int? {
        permille(contentFrameCount, of: deliveredFrameCount)
    }

    public var emptyUpdatePermille: Int? {
        permille(emptyUpdateCount, of: deliveredFrameCount)
    }

    public var transportIdleTimeoutPermille: Int? {
        permille(transportIdleTimeoutCount, of: deliveredFrameCount)
    }

    public var adaptiveClientPressurePacingPermille: Int? {
        permille(adaptiveClientPressurePacingSampleCount, of: deliveredFrameCount)
    }

    public var rendererPartialUploadPermille: Int? {
        permille(rendererPartialUploadCount, of: rendererUploadSampleCount)
    }

    public var rendererFullUploadPermille: Int? {
        permille(rendererFullUploadCount, of: rendererUploadSampleCount)
    }

    public var averageRendererUploadMilliseconds: Int? {
        averageRendererUploadTiming(rendererUploadMillisecondsTotal)
    }

    public var maxRendererUploadMilliseconds: Int? {
        rendererUploadTimingMax(rendererUploadMillisecondsMax)
    }

    public var averageReceiveTotalMilliseconds: Int? {
        averageTiming(receiveTotalMillisecondsTotal)
    }

    public var averageNetworkReadMilliseconds: Int? {
        averageTiming(networkReadMillisecondsTotal)
    }

    public var averageClientProcessingMilliseconds: Int? {
        averageTiming(clientProcessingMillisecondsTotal)
    }

    public var maxReceiveTotalMilliseconds: Int? {
        timingMax(receiveTotalMillisecondsMax)
    }

    public var maxNetworkReadMilliseconds: Int? {
        timingMax(networkReadMillisecondsMax)
    }

    public var maxClientProcessingMilliseconds: Int? {
        timingMax(clientProcessingMillisecondsMax)
    }

    public var averageAppFrameApplyMilliseconds: Int? {
        averageAppFrameApplyTiming(appFrameApplyMillisecondsTotal)
    }

    public var maxAppFrameApplyMilliseconds: Int? {
        appFrameApplyTimingMax(appFrameApplyMillisecondsMax)
    }

    public var diagnosticStreamPerformanceReport: DiagnosticStreamPerformanceReport? {
        guard deliveredFrameCount > 0 else {
            return nil
        }

        return DiagnosticStreamPerformanceReport(
            observedDurationBucket: observedDurationBucket.rawValue,
            deliveredFramesPerSecondBucket: deliveredFramesPerSecondBucket.rawValue,
            deliveredFrameCount: deliveredFrameCount,
            contentFrameCount: contentFrameCount,
            emptyUpdateCount: emptyUpdateCount,
            transportIdleTimeoutCount: transportIdleTimeoutCount,
            contentFramePermille: contentFramePermille,
            emptyUpdatePermille: emptyUpdatePermille,
            transportIdleTimeoutPermille: transportIdleTimeoutPermille,
            adaptiveClientPressurePacingSampleCount: adaptiveClientPressurePacingSampleCount,
            adaptiveClientPressurePacingPermille: adaptiveClientPressurePacingPermille,
            dirtyRectangleSampleCount: dirtyRectangleSampleCount,
            averageDirtyRectangleCount: averageDirtyRectangleCount,
            dirtyRectangleCountMax: dirtyRectangleCountMax,
            averageDirtyAreaPermille: averageDirtyAreaPermille,
            dirtyAreaPermilleMax: dirtyAreaPermilleMax,
            averageChangedPixelsPermille: averageChangedPixelsPermille,
            changedPixelsPermilleMax: changedPixelsPermilleMax,
            rendererUploadSampleCount: rendererUploadSampleCount,
            rendererPartialUploadCount: rendererPartialUploadCount,
            rendererFullUploadCount: rendererFullUploadCount,
            rendererPartialUploadPermille: rendererPartialUploadPermille,
            rendererFullUploadPermille: rendererFullUploadPermille,
            rendererUploadRegionCountMax: rendererUploadRegionCountMax,
            rendererUploadTimingSampleCount: rendererUploadTimingSampleCount,
            averageRendererUploadTimingBucket: DiagnosticTimingBucket
                .bucket(milliseconds: averageRendererUploadMilliseconds).rawValue,
            maxRendererUploadTimingBucket: DiagnosticTimingBucket
                .bucket(milliseconds: maxRendererUploadMilliseconds).rawValue,
            receiveTimingSampleCount: receiveTimingSampleCount,
            averageReceiveTotalTimingBucket: DiagnosticTimingBucket
                .bucket(milliseconds: averageReceiveTotalMilliseconds).rawValue,
            maxReceiveTotalTimingBucket: DiagnosticTimingBucket
                .bucket(milliseconds: maxReceiveTotalMilliseconds).rawValue,
            averageNetworkReadTimingBucket: DiagnosticTimingBucket
                .bucket(milliseconds: averageNetworkReadMilliseconds).rawValue,
            maxNetworkReadTimingBucket: DiagnosticTimingBucket
                .bucket(milliseconds: maxNetworkReadMilliseconds).rawValue,
            averageClientProcessingTimingBucket: DiagnosticTimingBucket
                .bucket(milliseconds: averageClientProcessingMilliseconds).rawValue,
            maxClientProcessingTimingBucket: DiagnosticTimingBucket
                .bucket(milliseconds: maxClientProcessingMilliseconds).rawValue,
            appFrameApplyTimingSampleCount: appFrameApplyTimingSampleCount,
            averageAppFrameApplyTimingBucket: DiagnosticTimingBucket
                .bucket(milliseconds: averageAppFrameApplyMilliseconds).rawValue,
            maxAppFrameApplyTimingBucket: DiagnosticTimingBucket
                .bucket(milliseconds: maxAppFrameApplyMilliseconds).rawValue,
            actualEncodingMix: actualEncodingMix,
            thermalState: thermalState.rawValue
        )
    }

    public mutating func record(
        frame: RFBFramePumpFrame,
        thermalState: SessionStreamThermalState,
        usesAdaptiveClientPressurePacing: Bool = false,
        appFrameApplyMilliseconds: Int? = nil
    ) {
        deliveredFrameCount += 1
        if usesAdaptiveClientPressurePacing {
            adaptiveClientPressurePacingSampleCount += 1
        }
        self.thermalState = thermalState
        if firstFrameCapturedAt == nil {
            firstFrameCapturedAt = frame.capturedAt
        }
        latestFrameCapturedAt = frame.capturedAt
        recordReceiveTiming(frame.timing)
        recordAppFrameApplyTiming(appFrameApplyMilliseconds)
        actualEncodingMix = actualEncodingMix.adding(frame.encodingMix)

        if frame.transportIdleTimedOut {
            transportIdleTimeoutCount += 1
            return
        } else if frame.isIncremental, frame.changedPixelCount == 0 {
            emptyUpdateCount += 1
        } else {
            contentFrameCount += 1
        }

        let framebufferArea = max(frame.framebuffer.width * frame.framebuffer.height, 1)
        let dirtyArea = frame.dirtyRectangles.reduce(0) { total, rect in
            total + max(rect.width, 0) * max(rect.height, 0)
        }
        let dirtyAreaPermille = Self.permille(dirtyArea, of: framebufferArea)
        let changedPixelsPermille = Self.permille(frame.changedPixelCount, of: framebufferArea)

        dirtyRectangleSampleCount += 1
        dirtyRectangleCountTotal += frame.dirtyRectangles.count
        dirtyRectangleCountMax = max(dirtyRectangleCountMax, frame.dirtyRectangles.count)
        dirtyAreaPermilleTotal += dirtyAreaPermille
        dirtyAreaPermilleMax = max(dirtyAreaPermilleMax, dirtyAreaPermille)
        changedPixelsPermilleTotal += changedPixelsPermille
        changedPixelsPermilleMax = max(changedPixelsPermilleMax, changedPixelsPermille)

        recordRendererUploadPlan(for: frame)
        lastFramebufferWidth = frame.framebuffer.width
        lastFramebufferHeight = frame.framebuffer.height
    }

    public mutating func recordRendererUploadTiming(milliseconds: Int) {
        let clampedMilliseconds = max(milliseconds, 0)
        rendererUploadTimingSampleCount += 1
        rendererUploadMillisecondsTotal += clampedMilliseconds
        rendererUploadMillisecondsMax = max(
            rendererUploadMillisecondsMax,
            clampedMilliseconds
        )
    }

    private mutating func recordReceiveTiming(_ timing: RFBFramebufferUpdateTiming?) {
        guard let timing else {
            return
        }

        receiveTimingSampleCount += 1
        receiveTotalMillisecondsTotal += timing.totalMilliseconds
        receiveTotalMillisecondsMax = max(receiveTotalMillisecondsMax, timing.totalMilliseconds)
        networkReadMillisecondsTotal += timing.networkReadMilliseconds
        networkReadMillisecondsMax = max(networkReadMillisecondsMax, timing.networkReadMilliseconds)
        clientProcessingMillisecondsTotal += timing.clientProcessingMilliseconds
        clientProcessingMillisecondsMax = max(
            clientProcessingMillisecondsMax,
            timing.clientProcessingMilliseconds
        )
    }

    private mutating func recordAppFrameApplyTiming(_ milliseconds: Int?) {
        guard let milliseconds else {
            return
        }

        let clampedMilliseconds = max(milliseconds, 0)
        appFrameApplyTimingSampleCount += 1
        appFrameApplyMillisecondsTotal += clampedMilliseconds
        appFrameApplyMillisecondsMax = max(appFrameApplyMillisecondsMax, clampedMilliseconds)
    }

    private mutating func recordRendererUploadPlan(for frame: RFBFramePumpFrame) {
        guard !(frame.isIncremental && frame.changedPixelCount == 0) else {
            return
        }

        let requiresTextureRecreation = lastFramebufferWidth != frame.framebuffer.width
            || lastFramebufferHeight != frame.framebuffer.height
        let dirtyRectangles = frame.isIncremental ? frame.dirtyRectangles : nil
        let uploadPlan = FramebufferUploadPlan.plan(
            framebufferWidth: frame.framebuffer.width,
            framebufferHeight: frame.framebuffer.height,
            dirtyRectangles: dirtyRectangles,
            requiresTextureRecreation: requiresTextureRecreation
        )

        guard uploadPlan.strategy != .none else {
            return
        }
        rendererUploadSampleCount += 1
        rendererUploadRegionCountMax = max(
            rendererUploadRegionCountMax,
            uploadPlan.uploadRegionCount
        )
        switch uploadPlan.strategy {
        case .partial:
            rendererPartialUploadCount += 1
        case .full:
            rendererFullUploadCount += 1
        case .none:
            break
        }
    }

    private func average(_ total: Int) -> Int? {
        guard dirtyRectangleSampleCount > 0 else {
            return nil
        }
        return total / dirtyRectangleSampleCount
    }

    private func averageTiming(_ total: Int) -> Int? {
        guard receiveTimingSampleCount > 0 else {
            return nil
        }
        return total / receiveTimingSampleCount
    }

    private func averageAppFrameApplyTiming(_ total: Int) -> Int? {
        guard appFrameApplyTimingSampleCount > 0 else {
            return nil
        }
        return total / appFrameApplyTimingSampleCount
    }

    private func averageRendererUploadTiming(_ total: Int) -> Int? {
        guard rendererUploadTimingSampleCount > 0 else {
            return nil
        }
        return total / rendererUploadTimingSampleCount
    }

    private func timingMax(_ value: Int) -> Int? {
        guard receiveTimingSampleCount > 0 else {
            return nil
        }
        return value
    }

    private func appFrameApplyTimingMax(_ value: Int) -> Int? {
        guard appFrameApplyTimingSampleCount > 0 else {
            return nil
        }
        return value
    }

    private func rendererUploadTimingMax(_ value: Int) -> Int? {
        guard rendererUploadTimingSampleCount > 0 else {
            return nil
        }
        return value
    }

    private func permille(_ value: Int, of total: Int) -> Int? {
        guard total > 0 else {
            return nil
        }
        return Self.permille(value, of: total)
    }

    private static func permille(_ value: Int, of total: Int) -> Int {
        guard total > 0 else {
            return 0
        }
        let rounded = Int((Double(max(value, 0)) / Double(total) * 1_000).rounded())
        return value > 0 ? max(rounded, 1) : 0
    }
}

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
    /// Safe aggregate stream counters for the active session. These
    /// counters never include target identity, coordinates, dimensions,
    /// pixels, byte counts, raw latency/timing samples, or raw errors.
    public var sessionStreamStats: SessionStreamStats
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
        sessionStreamStats: SessionStreamStats = SessionStreamStats(),
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
        self.sessionStreamStats = sessionStreamStats
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
