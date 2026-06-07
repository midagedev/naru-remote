import Foundation
import NaruRemoteCore

public enum BenchmarkHelperVideoVisualTransport: String, Codable, Equatable, CaseIterable, Sendable {
    case helperVideo = "helper-video"
}

public enum BenchmarkHelperVideoIssueCode: String, Codable, Equatable, CaseIterable, Sendable {
    case streamDisabled = "helper-video-stream-disabled"
    case permissionMissing = "helper-video-permission-missing"
    case streamUnhealthy = "helper-video-stream-unhealthy"
    case startupSlow = "helper-video-startup-slow"
    case startupFailed = "helper-video-startup-failed"
    case sustainedChoppy = "helper-video-sustained-choppy"
    case sustainedStalled = "helper-video-sustained-stalled"
    case decodePressureHigh = "helper-video-decode-pressure-high"
    case fallbackObserved = "helper-video-fallback-observed"
    case externalHelperUnavailable = "helper-video-external-helper-unavailable"
    case externalHelperTimedOut = "helper-video-external-helper-timed-out"
    case transportFailed = "helper-video-transport-failed"
}

public enum BenchmarkHelperVideoReadinessState: String, Codable, Equatable, CaseIterable, Sendable {
    case disabled
    case permissionBlocked
    case transportBlocked
    case startupBlocked
    case sustainedDegraded
    case decodeBlocked
    case readyForTrueCaptureGate
    case readyForPhysicalGate
}

public enum BenchmarkHelperVideoRecommendedAction: String, Codable, Equatable, CaseIterable, Sendable {
    case enableHelperVideo = "enable-helper-video"
    case grantScreenRecordingPermission = "grant-helper-video-app-screen-recording-permission"
    case inspectHelperVideoTransport = "inspect-helper-video-transport"
    case inspectHelperVideoStartup = "inspect-helper-video-startup"
    case inspectHelperVideoSustainedCadence = "inspect-helper-video-sustained-cadence"
    case inspectHelperVideoDecodePressure = "inspect-helper-video-decode-pressure"
    case runTrueHelperVideoLiveCaptureBenchmark = "run-true-helper-video-live-capture-benchmark"
    case runPhysicalIPhoneHelperVideoGate = "run-physical-iphone-helper-video-gate"
}

public struct BenchmarkHelperVideoReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case visualTransport
        case streamProtocolVersion
        case codec
        case codecProfile
        case latencyMode
        case qualityBucket
        case frameRateBucket
        case colorMode
        case supportsKeyframeRequest
        case supportsFallbackSignal
        case streamState
        case startupBand
        case sustainedUpdateBand
        case decodePressure
        case fallbackCountBucket
        case verdict
        case issueCodes
        case readinessState
        case recommendedAction
    }

    public let schemaVersion: Int
    public let visualTransport: BenchmarkHelperVideoVisualTransport
    public let streamProtocolVersion: Int
    public let codec: HelperVideoCodec
    public let codecProfile: HelperVideoCodecProfile
    public let latencyMode: HelperVideoLatencyMode
    public let qualityBucket: HelperVideoQualityBucket
    public let frameRateBucket: HelperVideoFrameRateBucket
    public let colorMode: HelperVideoColorMode
    public let supportsKeyframeRequest: Bool
    public let supportsFallbackSignal: Bool
    public let streamState: HelperVideoStreamState
    public let startupBand: HelperVideoStartupBand
    public let sustainedUpdateBand: HelperVideoSustainedUpdateBand
    public let decodePressure: HelperVideoDecodePressure
    public let fallbackCountBucket: HelperVideoFallbackCountBucket
    public let verdict: BenchmarkStreamShapePracticalVerdict
    public let issueCodes: [BenchmarkHelperVideoIssueCode]
    public let readinessState: BenchmarkHelperVideoReadinessState
    public let recommendedAction: BenchmarkHelperVideoRecommendedAction

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        visualTransport: BenchmarkHelperVideoVisualTransport = .helperVideo,
        streamProtocolVersion: Int = HelperVideoStreamDescriptor.minimumSupportedProtocolVersion,
        codec: HelperVideoCodec = .h264,
        codecProfile: HelperVideoCodecProfile = .unknown,
        latencyMode: HelperVideoLatencyMode = .lowLatency,
        qualityBucket: HelperVideoQualityBucket = .readability,
        frameRateBucket: HelperVideoFrameRateBucket = .upTo30,
        colorMode: HelperVideoColorMode = .standardDynamicRange,
        supportsKeyframeRequest: Bool = true,
        supportsFallbackSignal: Bool = true,
        streamState: HelperVideoStreamState = .idle,
        startupBand: HelperVideoStartupBand = .notMeasured,
        sustainedUpdateBand: HelperVideoSustainedUpdateBand = .notMeasured,
        decodePressure: HelperVideoDecodePressure = .notMeasured,
        fallbackCountBucket: HelperVideoFallbackCountBucket = .none,
        issueCodes: [BenchmarkHelperVideoIssueCode] = [],
        readinessState: BenchmarkHelperVideoReadinessState? = nil,
        recommendedAction: BenchmarkHelperVideoRecommendedAction? = nil
    ) {
        self.schemaVersion = max(schemaVersion, Self.currentSchemaVersion)
        self.visualTransport = visualTransport
        self.streamProtocolVersion = max(
            streamProtocolVersion,
            HelperVideoStreamDescriptor.minimumSupportedProtocolVersion
        )
        self.codec = codec
        self.codecProfile = codecProfile
        self.latencyMode = latencyMode
        self.qualityBucket = qualityBucket
        self.frameRateBucket = frameRateBucket
        self.colorMode = colorMode
        self.supportsKeyframeRequest = supportsKeyframeRequest
        self.supportsFallbackSignal = supportsFallbackSignal
        self.streamState = streamState
        self.startupBand = startupBand
        self.sustainedUpdateBand = sustainedUpdateBand
        self.decodePressure = decodePressure
        self.fallbackCountBucket = fallbackCountBucket
        self.issueCodes = Self.safeIssueCodes(
            issueCodes + Self.derivedIssueCodes(
                explicitIssueCodes: issueCodes,
                streamState: streamState,
                startupBand: startupBand,
                sustainedUpdateBand: sustainedUpdateBand,
                decodePressure: decodePressure,
                fallbackCountBucket: fallbackCountBucket
            )
        )
        self.verdict = Self.verdict(
            streamState: streamState,
            issueCodes: self.issueCodes
        )
        let derivedReadiness = Self.readinessState(
            streamState: streamState,
            startupBand: startupBand,
            sustainedUpdateBand: sustainedUpdateBand,
            decodePressure: decodePressure,
            issueCodes: self.issueCodes
        )
        self.readinessState = readinessState ?? derivedReadiness
        self.recommendedAction = recommendedAction
            ?? Self.recommendedAction(for: self.readinessState)
    }

    public init(
        descriptor: HelperVideoStreamDescriptor,
        health: HelperVideoStreamHealth,
        issueCodes: [BenchmarkHelperVideoIssueCode] = []
    ) {
        self.init(
            streamProtocolVersion: descriptor.protocolVersion,
            codec: descriptor.codec,
            codecProfile: descriptor.codecProfile,
            latencyMode: descriptor.latencyMode,
            qualityBucket: descriptor.qualityBucket,
            frameRateBucket: descriptor.frameRateBucket,
            colorMode: descriptor.colorMode,
            supportsKeyframeRequest: descriptor.supportsKeyframeRequest,
            supportsFallbackSignal: descriptor.supportsFallbackSignal,
            streamState: health.state,
            startupBand: health.startupBand,
            sustainedUpdateBand: health.sustainedUpdateBand,
            decodePressure: health.decodePressure,
            fallbackCountBucket: health.fallbackCountBucket,
            issueCodes: issueCodes
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? Self.currentSchemaVersion,
            visualTransport: try container.decodeIfPresent(
                BenchmarkHelperVideoVisualTransport.self,
                forKey: .visualTransport
            ) ?? .helperVideo,
            streamProtocolVersion: try container.decodeIfPresent(Int.self, forKey: .streamProtocolVersion)
                ?? HelperVideoStreamDescriptor.minimumSupportedProtocolVersion,
            codec: try container.decodeIfPresent(HelperVideoCodec.self, forKey: .codec) ?? .unknown,
            codecProfile: try container.decodeIfPresent(HelperVideoCodecProfile.self, forKey: .codecProfile)
                ?? .unknown,
            latencyMode: try container.decodeIfPresent(HelperVideoLatencyMode.self, forKey: .latencyMode)
                ?? .balanced,
            qualityBucket: try container.decodeIfPresent(HelperVideoQualityBucket.self, forKey: .qualityBucket)
                ?? .balanced,
            frameRateBucket: try container.decodeIfPresent(HelperVideoFrameRateBucket.self, forKey: .frameRateBucket)
                ?? .unknown,
            colorMode: try container.decodeIfPresent(HelperVideoColorMode.self, forKey: .colorMode)
                ?? .unknown,
            supportsKeyframeRequest: try container.decodeIfPresent(Bool.self, forKey: .supportsKeyframeRequest)
                ?? false,
            supportsFallbackSignal: try container.decodeIfPresent(Bool.self, forKey: .supportsFallbackSignal)
                ?? false,
            streamState: try container.decodeIfPresent(HelperVideoStreamState.self, forKey: .streamState)
                ?? .idle,
            startupBand: try container.decodeIfPresent(HelperVideoStartupBand.self, forKey: .startupBand)
                ?? .notMeasured,
            sustainedUpdateBand: try container.decodeIfPresent(
                HelperVideoSustainedUpdateBand.self,
                forKey: .sustainedUpdateBand
            ) ?? .notMeasured,
            decodePressure: try container.decodeIfPresent(HelperVideoDecodePressure.self, forKey: .decodePressure)
                ?? .notMeasured,
            fallbackCountBucket: try container.decodeIfPresent(
                HelperVideoFallbackCountBucket.self,
                forKey: .fallbackCountBucket
            ) ?? .none,
            issueCodes: try container.decodeIfPresent([BenchmarkHelperVideoIssueCode].self, forKey: .issueCodes)
                ?? [],
            readinessState: try container.decodeIfPresent(
                BenchmarkHelperVideoReadinessState.self,
                forKey: .readinessState
            ),
            recommendedAction: try container.decodeIfPresent(
                BenchmarkHelperVideoRecommendedAction.self,
                forKey: .recommendedAction
            )
        )
    }

    private static func safeIssueCodes(
        _ values: [BenchmarkHelperVideoIssueCode]
    ) -> [BenchmarkHelperVideoIssueCode] {
        var seen = Set<String>()
        return values.filter { issue in
            guard seen.insert(issue.rawValue).inserted else {
                return false
            }
            return true
        }
    }

    private static func derivedIssueCodes(
        explicitIssueCodes: [BenchmarkHelperVideoIssueCode],
        streamState: HelperVideoStreamState,
        startupBand: HelperVideoStartupBand,
        sustainedUpdateBand: HelperVideoSustainedUpdateBand,
        decodePressure: HelperVideoDecodePressure,
        fallbackCountBucket: HelperVideoFallbackCountBucket
    ) -> [BenchmarkHelperVideoIssueCode] {
        if explicitIssueCodes.contains(.permissionMissing) {
            return []
        }

        var issues: [BenchmarkHelperVideoIssueCode] = []

        switch streamState {
        case .idle, .ended:
            issues.append(.streamDisabled)
        case .stalled, .fallbackToVNC, .failed:
            issues.append(.streamUnhealthy)
        case .starting, .healthy:
            break
        }

        switch startupBand {
        case .slow:
            issues.append(.startupSlow)
        case .failed:
            issues.append(.startupFailed)
        case .notMeasured, .fast, .usable:
            break
        }

        switch sustainedUpdateBand {
        case .choppy:
            issues.append(.sustainedChoppy)
        case .stalled:
            issues.append(.sustainedStalled)
        case .notMeasured, .smooth, .usable:
            break
        }

        if decodePressure == .high {
            issues.append(.decodePressureHigh)
        }

        if fallbackCountBucket != .none {
            issues.append(.fallbackObserved)
        }

        return issues
    }

    private static func verdict(
        streamState: HelperVideoStreamState,
        issueCodes: [BenchmarkHelperVideoIssueCode]
    ) -> BenchmarkStreamShapePracticalVerdict {
        let hardFailures: Set<BenchmarkHelperVideoIssueCode> = [
            .permissionMissing,
            .streamUnhealthy,
            .startupFailed,
            .sustainedStalled,
            .decodePressureHigh,
            .externalHelperUnavailable,
            .externalHelperTimedOut,
            .transportFailed
        ]
        if issueCodes.contains(where: hardFailures.contains) {
            return .fail
        }

        switch streamState {
        case .idle, .ended:
            return .disabled
        case .starting, .healthy, .stalled, .fallbackToVNC, .failed:
            break
        }

        if issueCodes.isEmpty {
            return .pass
        }
        return .warning
    }

    private static func readinessState(
        streamState: HelperVideoStreamState,
        startupBand: HelperVideoStartupBand,
        sustainedUpdateBand: HelperVideoSustainedUpdateBand,
        decodePressure: HelperVideoDecodePressure,
        issueCodes: [BenchmarkHelperVideoIssueCode]
    ) -> BenchmarkHelperVideoReadinessState {
        if issueCodes.contains(.permissionMissing) {
            return .permissionBlocked
        }
        if issueCodes.contains(.externalHelperUnavailable)
            || issueCodes.contains(.externalHelperTimedOut)
            || issueCodes.contains(.transportFailed)
        {
            return .transportBlocked
        }
        if streamState == .idle || streamState == .ended || issueCodes.contains(.streamDisabled) {
            return .disabled
        }
        if startupBand == .failed || issueCodes.contains(.startupFailed) {
            return .startupBlocked
        }
        if decodePressure == .high || issueCodes.contains(.decodePressureHigh) {
            return .decodeBlocked
        }
        if sustainedUpdateBand == .stalled
            || sustainedUpdateBand == .choppy
            || issueCodes.contains(.sustainedStalled)
            || issueCodes.contains(.sustainedChoppy)
        {
            return .sustainedDegraded
        }
        if streamState == .healthy && issueCodes.isEmpty {
            return .readyForPhysicalGate
        }
        return .readyForTrueCaptureGate
    }

    private static func recommendedAction(
        for readinessState: BenchmarkHelperVideoReadinessState
    ) -> BenchmarkHelperVideoRecommendedAction {
        switch readinessState {
        case .disabled:
            return .enableHelperVideo
        case .permissionBlocked:
            return .grantScreenRecordingPermission
        case .transportBlocked:
            return .inspectHelperVideoTransport
        case .startupBlocked:
            return .inspectHelperVideoStartup
        case .sustainedDegraded:
            return .inspectHelperVideoSustainedCadence
        case .decodeBlocked:
            return .inspectHelperVideoDecodePressure
        case .readyForTrueCaptureGate:
            return .runTrueHelperVideoLiveCaptureBenchmark
        case .readyForPhysicalGate:
            return .runPhysicalIPhoneHelperVideoGate
        }
    }
}
