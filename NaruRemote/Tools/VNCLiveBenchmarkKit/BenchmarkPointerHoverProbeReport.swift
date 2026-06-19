import Foundation

public enum BenchmarkPointerHoverProbeStatus: String, Codable, Equatable, Sendable {
    case observedHover = "observed-hover"
    case failed
}

public enum BenchmarkPointerHoverProbeStageStatus: String, Codable, Equatable, Sendable {
    case notRun = "not-run"
    case passed
    case failed
}

public enum BenchmarkPointerHoverObservationStatus: String, Codable, Equatable, Sendable {
    case notRun = "not-run"
    case observed
    case timedOut = "timed-out"
    case targetUnavailable = "target-unavailable"
    case failed
}

public struct BenchmarkPointerHoverProbeReport: Codable, Equatable, Sendable {
    public static let schemaVersion = 2

    public let schemaVersion: Int
    public let mode: String
    public let status: BenchmarkPointerHoverProbeStatus
    public let networkConditionProfile: BenchmarkNetworkConditionProfile
    public let connectStatus: BenchmarkPointerHoverProbeStageStatus
    public let firstFrameStatus: BenchmarkPointerHoverProbeStageStatus
    public let targetVisibilityStatus: BenchmarkPointerHoverProbeStageStatus
    public let sendStatus: BenchmarkPointerHoverProbeStageStatus
    public let observationStatus: BenchmarkPointerHoverObservationStatus
    public let timestampLatency: BenchmarkLatencySummary?
    public let timestampLatencySampleCount: Int
    public let failureLabel: String?
    public let recommendedNextActionLabel: String
    public let safety: [String]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        mode: String = "pointer-hover-observed-probe",
        status: BenchmarkPointerHoverProbeStatus,
        networkConditionProfile: BenchmarkNetworkConditionProfile = .none,
        connectStatus: BenchmarkPointerHoverProbeStageStatus,
        firstFrameStatus: BenchmarkPointerHoverProbeStageStatus,
        targetVisibilityStatus: BenchmarkPointerHoverProbeStageStatus = .notRun,
        sendStatus: BenchmarkPointerHoverProbeStageStatus,
        observationStatus: BenchmarkPointerHoverObservationStatus = .notRun,
        timestampLatency: BenchmarkLatencySummary? = nil,
        timestampLatencySampleCount: Int? = nil,
        failureLabel: String?,
        recommendedNextActionLabel: String = "none",
        safety: [String] = Self.defaultSafety
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.status = status
        self.networkConditionProfile = networkConditionProfile
        self.connectStatus = connectStatus
        self.firstFrameStatus = firstFrameStatus
        self.targetVisibilityStatus = targetVisibilityStatus
        self.sendStatus = sendStatus
        self.observationStatus = observationStatus
        self.timestampLatency = timestampLatency
        self.timestampLatencySampleCount = max(
            timestampLatencySampleCount ?? timestampLatency?.sampleCount ?? 0,
            0
        )
        self.failureLabel = failureLabel
        self.recommendedNextActionLabel = recommendedNextActionLabel
        self.safety = safety
    }

    public static let defaultSafety = [
        "pointer-hover probe reports omit pointer coordinates, target identity, credentials, framebuffer dimensions, pixels, byte counts, sidecar timestamps, raw OS errors, and exact event payloads",
        "pointer-hover probe reports emit fixed stage labels, target-visibility labels, network-condition labels, observation labels, safe failure labels, fixed next-action labels, and aggregate timestamp-latency millisecond summaries only",
        "observed-hover means a controlled local hover target changed a timestamp marker after a buttonless RFB pointer move and that marker was later observed through the VNC framebuffer"
    ]
}
