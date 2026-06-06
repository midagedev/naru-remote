import Foundation
import NaruRemoteCore

#if os(macOS) && canImport(CoreMedia) && canImport(CoreVideo) && canImport(VideoToolbox)
import CoreMedia
import CoreVideo
import VideoToolbox
#endif

public let naruHelperVideoEncoderPrototypeSchemaVersion = 1

public enum NaruHelperVideoEncoderFeatureFlagState: String, Codable, Equatable, CaseIterable, Sendable {
    case enabled
    case disabled
}

public enum NaruHelperVideoEncoderAPI: String, Codable, Equatable, CaseIterable, Sendable {
    case videoToolbox
}

public enum NaruHelperVideoEncoderSessionState: String, Codable, Equatable, CaseIterable, Sendable {
    case notStarted
    case prepared
    case unavailable
    case unsupported
}

public struct NaruHelperVideoEncoderPrototypeResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var availability: HelperVideoAvailability
    public var featureFlagState: NaruHelperVideoEncoderFeatureFlagState
    public var encoderAPI: NaruHelperVideoEncoderAPI?
    public var codec: HelperVideoCodec
    public var codecProfile: HelperVideoCodecProfile
    public var latencyMode: HelperVideoLatencyMode
    public var qualityBucket: HelperVideoQualityBucket
    public var sessionState: NaruHelperVideoEncoderSessionState
    public var safeFailureCode: HelperVideoFailureCode?

    public init(
        schemaVersion: Int = naruHelperVideoEncoderPrototypeSchemaVersion,
        availability: HelperVideoAvailability,
        featureFlagState: NaruHelperVideoEncoderFeatureFlagState,
        encoderAPI: NaruHelperVideoEncoderAPI? = .videoToolbox,
        codec: HelperVideoCodec = .h264,
        codecProfile: HelperVideoCodecProfile = .high,
        latencyMode: HelperVideoLatencyMode = .lowLatency,
        qualityBucket: HelperVideoQualityBucket = .readability,
        sessionState: NaruHelperVideoEncoderSessionState,
        safeFailureCode: HelperVideoFailureCode? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.availability = availability
        self.featureFlagState = featureFlagState
        self.encoderAPI = encoderAPI
        self.codec = codec
        self.codecProfile = codecProfile
        self.latencyMode = latencyMode
        self.qualityBucket = qualityBucket
        self.sessionState = sessionState
        self.safeFailureCode = safeFailureCode
    }
}

public struct NaruHelperVideoEncoderFeatureFlag: Sendable {
    public static let environmentKey = "NARU_HELPER_VIDEO_ENCODER_PROTOTYPE"

    public var isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NaruHelperVideoEncoderFeatureFlag {
        let value = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return NaruHelperVideoEncoderFeatureFlag(
            isEnabled: ["1", "true", "yes", "enabled", "videotoolbox"].contains(value)
        )
    }
}

public struct NaruHelperVideoEncoderPrototypeProbe: Sendable {
    public typealias FeatureFlagProvider = @Sendable () -> NaruHelperVideoEncoderFeatureFlag
    public typealias SessionProvider = @Sendable () -> NaruHelperVideoEncoderSessionState

    private let encoderAPI: NaruHelperVideoEncoderAPI?
    private let featureFlagProvider: FeatureFlagProvider
    private let sessionProvider: SessionProvider

    public init(
        encoderAPI: NaruHelperVideoEncoderAPI? = .videoToolbox,
        featureFlagProvider: @escaping FeatureFlagProvider,
        sessionProvider: @escaping SessionProvider
    ) {
        self.encoderAPI = encoderAPI
        self.featureFlagProvider = featureFlagProvider
        self.sessionProvider = sessionProvider
    }

    public func capability() -> NaruHelperVideoEncoderPrototypeResponse {
        let featureFlag = featureFlagProvider()
        guard featureFlag.isEnabled else {
            return NaruHelperVideoEncoderPrototypeResponse(
                availability: .disabled,
                featureFlagState: .disabled,
                encoderAPI: encoderAPI,
                sessionState: .notStarted,
                safeFailureCode: .disabled
            )
        }

        let sessionState = sessionProvider()
        guard sessionState == .prepared else {
            return NaruHelperVideoEncoderPrototypeResponse(
                availability: .codecUnsupported,
                featureFlagState: .enabled,
                encoderAPI: sessionState == .unsupported ? nil : encoderAPI,
                sessionState: sessionState,
                safeFailureCode: .codecUnsupported
            )
        }

        return NaruHelperVideoEncoderPrototypeResponse(
            availability: .available,
            featureFlagState: .enabled,
            encoderAPI: encoderAPI,
            sessionState: .prepared
        )
    }

    public static func live() -> NaruHelperVideoEncoderPrototypeProbe {
        #if os(macOS) && canImport(VideoToolbox)
        return NaruHelperVideoEncoderPrototypeProbe(
            featureFlagProvider: {
                NaruHelperVideoEncoderFeatureFlag.fromEnvironment()
            },
            sessionProvider: {
                LiveNaruHelperVideoToolboxH264EncoderPrototype.prepareSession()
            }
        )
        #else
        return NaruHelperVideoEncoderPrototypeProbe(
            encoderAPI: nil,
            featureFlagProvider: {
                NaruHelperVideoEncoderFeatureFlag.fromEnvironment()
            },
            sessionProvider: {
                .unsupported
            }
        )
        #endif
    }
}

#if os(macOS) && canImport(CoreMedia) && canImport(CoreVideo) && canImport(VideoToolbox)
private enum LiveNaruHelperVideoToolboxH264EncoderPrototype {
    private static let syntheticWidth: Int32 = 64
    private static let syntheticHeight: Int32 = 64

    static func prepareSession() -> NaruHelperVideoEncoderSessionState {
        var session: VTCompressionSession?
        let encoderSpecification: CFDictionary = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any,
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: kCFBooleanTrue as Any
        ] as CFDictionary
        let imageBufferAttributes: CFDictionary = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)
        ] as CFDictionary

        let createStatus = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: syntheticWidth,
            height: syntheticHeight,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpecification,
            imageBufferAttributes: imageBufferAttributes,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard createStatus == noErr, let session else {
            return .unavailable
        }
        defer {
            VTCompressionSessionInvalidate(session)
        }

        guard configure(session: session) else {
            return .unavailable
        }

        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        return prepareStatus == noErr ? .prepared : .unavailable
    }

    private static func configure(session: VTCompressionSession) -> Bool {
        let properties: [(CFString, CFTypeRef)] = [
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),
            (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        ]

        for property in properties {
            let status = VTSessionSetProperty(session, key: property.0, value: property.1)
            guard status == noErr else {
                return false
            }
        }
        return true
    }
}
#endif
