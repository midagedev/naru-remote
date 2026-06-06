import Foundation

public enum HelperVideoAvailability: String, Codable, Equatable, CaseIterable, Sendable {
    case notConfigured
    case disabled
    case checking
    case available
    case permissionMissing
    case codecUnsupported
    case revoked
    case unreachable
    case failed
}

public enum HelperVideoFailureCode: String, Codable, Equatable, CaseIterable, Sendable {
    case authFailed = "helperVideo.authFailed"
    case permissionMissing = "helperVideo.permissionMissing"
    case codecUnsupported = "helperVideo.codecUnsupported"
    case streamStalled = "helperVideo.streamStalled"
    case decoderRejected = "helperVideo.decoderRejected"
    case revoked = "helperVideo.revoked"
    case transportFailed = "helperVideo.transportFailed"
    case fallbackToVNC = "helperVideo.fallbackToVNC"
}

public enum HelperVideoLastCheckedBucket: String, Codable, Equatable, CaseIterable, Sendable {
    case never
    case recent
    case stale
}

public enum HelperVideoCodec: String, Codable, Equatable, CaseIterable, Sendable {
    case h264
    case unknown
}

public enum HelperVideoCodecProfile: String, Codable, Equatable, CaseIterable, Sendable {
    case baseline
    case main
    case high
    case unknown
}

public enum HelperVideoLatencyMode: String, Codable, Equatable, CaseIterable, Sendable {
    case lowLatency
    case balanced
}

public enum HelperVideoQualityBucket: String, Codable, Equatable, CaseIterable, Sendable {
    case readability
    case balanced
    case fidelity
}

public enum HelperVideoFrameRateBucket: String, Codable, Equatable, CaseIterable, Sendable {
    case upTo15
    case upTo30
    case unknown
}

public enum HelperVideoColorMode: String, Codable, Equatable, CaseIterable, Sendable {
    case standardDynamicRange
    case unknown
}

public enum HelperVideoStreamState: String, Codable, Equatable, CaseIterable, Sendable {
    case idle
    case starting
    case healthy
    case stalled
    case fallbackToVNC
    case ended
    case failed
}

public enum HelperVideoStartupBand: String, Codable, Equatable, CaseIterable, Sendable {
    case notMeasured
    case fast
    case usable
    case slow
    case failed
}

public enum HelperVideoSustainedUpdateBand: String, Codable, Equatable, CaseIterable, Sendable {
    case notMeasured
    case smooth
    case usable
    case choppy
    case stalled
}

public enum HelperVideoDecodePressure: String, Codable, Equatable, CaseIterable, Sendable {
    case notMeasured
    case low
    case medium
    case high
}

public enum HelperVideoFallbackCountBucket: String, Codable, Equatable, CaseIterable, Sendable {
    case none
    case one
    case few
    case many
}

public struct HelperVideoProfileState: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var pairingFingerprint: String?
    public var availability: HelperVideoAvailability
    public var lastFailureCode: HelperVideoFailureCode?
    public var lastCheckedBucket: HelperVideoLastCheckedBucket

    public init(
        isEnabled: Bool = false,
        pairingFingerprint: String? = nil,
        availability: HelperVideoAvailability = .notConfigured,
        lastFailureCode: HelperVideoFailureCode? = nil,
        lastCheckedBucket: HelperVideoLastCheckedBucket = .never
    ) {
        self.isEnabled = isEnabled
        self.pairingFingerprint = pairingFingerprint
        self.availability = availability
        self.lastFailureCode = lastFailureCode
        self.lastCheckedBucket = lastCheckedBucket
    }

    public var canAttemptHelperVideoStream: Bool {
        isEnabled && availability == .available
    }

    public var shouldUseVNCVisualFallback: Bool {
        !canAttemptHelperVideoStream
    }
}

public struct HelperVideoStreamDescriptor: Codable, Equatable, Sendable {
    public static let minimumSupportedProtocolVersion = 1

    public var protocolVersion: Int
    public var codec: HelperVideoCodec
    public var codecProfile: HelperVideoCodecProfile
    public var latencyMode: HelperVideoLatencyMode
    public var qualityBucket: HelperVideoQualityBucket
    public var frameRateBucket: HelperVideoFrameRateBucket
    public var colorMode: HelperVideoColorMode
    public var supportsKeyframeRequest: Bool
    public var supportsFallbackSignal: Bool

    public init(
        protocolVersion: Int = 1,
        codec: HelperVideoCodec = .h264,
        codecProfile: HelperVideoCodecProfile = .unknown,
        latencyMode: HelperVideoLatencyMode = .lowLatency,
        qualityBucket: HelperVideoQualityBucket = .readability,
        frameRateBucket: HelperVideoFrameRateBucket = .upTo30,
        colorMode: HelperVideoColorMode = .standardDynamicRange,
        supportsKeyframeRequest: Bool = true,
        supportsFallbackSignal: Bool = true
    ) {
        self.protocolVersion = max(protocolVersion, Self.minimumSupportedProtocolVersion)
        self.codec = codec
        self.codecProfile = codecProfile
        self.latencyMode = latencyMode
        self.qualityBucket = qualityBucket
        self.frameRateBucket = frameRateBucket
        self.colorMode = colorMode
        self.supportsKeyframeRequest = supportsKeyframeRequest
        self.supportsFallbackSignal = supportsFallbackSignal
    }
}

public struct HelperVideoStreamHealth: Codable, Equatable, Sendable {
    public var state: HelperVideoStreamState
    public var startupBand: HelperVideoStartupBand
    public var sustainedUpdateBand: HelperVideoSustainedUpdateBand
    public var decodePressure: HelperVideoDecodePressure
    public var fallbackCountBucket: HelperVideoFallbackCountBucket

    public init(
        state: HelperVideoStreamState = .idle,
        startupBand: HelperVideoStartupBand = .notMeasured,
        sustainedUpdateBand: HelperVideoSustainedUpdateBand = .notMeasured,
        decodePressure: HelperVideoDecodePressure = .notMeasured,
        fallbackCountBucket: HelperVideoFallbackCountBucket = .none
    ) {
        self.state = state
        self.startupBand = startupBand
        self.sustainedUpdateBand = sustainedUpdateBand
        self.decodePressure = decodePressure
        self.fallbackCountBucket = fallbackCountBucket
    }

    public var shouldUseVNCVisualFallback: Bool {
        switch state {
        case .stalled, .fallbackToVNC, .failed:
            return true
        case .idle, .starting, .healthy, .ended:
            return false
        }
    }
}
