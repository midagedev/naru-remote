import Foundation
import NaruRemoteCore

#if os(macOS) && canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(Network)
public enum NaruHelperVideoListenSourceMode: String, Equatable, CaseIterable, Sendable {
    case screenCaptureKit = "screen-capturekit"
    case syntheticEncoded = "synthetic-encoded"

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }

    public static func parse(_ rawValue: String) -> NaruHelperVideoListenSourceMode? {
        NaruHelperVideoListenSourceMode(rawValue: rawValue)
    }
}

public struct NaruHelperVideoListenConfiguration: Equatable, Sendable {
    public var pairingSecret: String
    public var profileFingerprint: String
    public var port: UInt16
    public var sourceMode: NaruHelperVideoListenSourceMode
    /// A value of `0` means the listen runtime serves a sustained stream until
    /// the client disconnects. Benchmarks pass a positive value to keep runs
    /// bounded and reproducible.
    public var frameCount: Int

    public init(
        pairingSecret: String,
        profileFingerprint: String,
        port: UInt16 = UInt16(naruHelperVideoStreamDefaultPort),
        sourceMode: NaruHelperVideoListenSourceMode = .screenCaptureKit,
        frameCount: Int = 0
    ) {
        self.pairingSecret = pairingSecret
        self.profileFingerprint = profileFingerprint
        self.port = port
        self.sourceMode = sourceMode
        self.frameCount = max(frameCount, 0)
    }

    public static func parse(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> NaruHelperVideoListenConfiguration {
        let pairingSecret = try requiredEnvironmentOptionValue(
            directArgument: "--token",
            environmentNameAfter: "--token-env",
            in: arguments,
            environment: environment,
            directArgumentError: .directTokenArgumentUnsupported,
            missingValueError: .missingToken
        )

        let profileFingerprint = try requiredEnvironmentOptionValue(
            directArgument: "--profile-fingerprint",
            environmentNameAfter: "--profile-fingerprint-env",
            in: arguments,
            environment: environment,
            directArgumentError: .directProfileFingerprintArgumentUnsupported,
            missingValueError: .missingProfileFingerprint
        )

        let port = try optionalOptionValue(
            after: "--port",
            in: arguments,
            missingValueError: .invalidPort
        )
            .map(parsePort)
            ?? UInt16(naruHelperVideoStreamDefaultPort)
        let sourceMode = try optionalOptionValue(
            after: "--video-source",
            in: arguments,
            missingValueError: .invalidSourceMode
        )
            .map(parseSourceMode)
            ?? .screenCaptureKit
        let frameCount = try optionalOptionValue(
            after: "--video-frame-count",
            in: arguments,
            missingValueError: .invalidFrameCount
        )
            .map(parseFrameCount)
            ?? 0

        return NaruHelperVideoListenConfiguration(
            pairingSecret: pairingSecret,
            profileFingerprint: profileFingerprint,
            port: port,
            sourceMode: sourceMode,
            frameCount: frameCount
        )
    }

    private static func requiredEnvironmentOptionValue(
        directArgument: String,
        environmentNameAfter environmentName: String,
        in arguments: [String],
        environment: [String: String],
        directArgumentError: NaruHelperVideoListenConfigurationError,
        missingValueError: NaruHelperVideoListenConfigurationError
    ) throws -> String {
        if arguments.contains(directArgument) {
            throw directArgumentError
        }

        guard let environmentVariableName = try optionalOptionValue(
            after: environmentName,
            in: arguments,
            missingValueError: missingValueError
        ) else {
            throw missingValueError
        }
        guard let value = environment[environmentVariableName],
              isConcreteArgumentValue(value)
        else {
            throw missingValueError
        }
        return value
    }

    private static func optionalOptionValue(
        after name: String,
        in arguments: [String],
        missingValueError: NaruHelperVideoListenConfigurationError
    ) throws -> String? {
        guard arguments.contains(name) else {
            return nil
        }
        guard let value = optionValue(after: name, in: arguments),
              isConcreteArgumentValue(value)
        else {
            throw missingValueError
        }
        return value
    }

    private static func optionValue(after name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

    private static func isConcreteArgumentValue(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("--")
    }

    private static func parsePort(_ rawValue: String) throws -> UInt16 {
        guard let port = UInt16(rawValue), port > 0 else {
            throw NaruHelperVideoListenConfigurationError.invalidPort
        }
        return port
    }

    private static func parseSourceMode(_ rawValue: String) throws -> NaruHelperVideoListenSourceMode {
        guard let sourceMode = NaruHelperVideoListenSourceMode.parse(rawValue) else {
            throw NaruHelperVideoListenConfigurationError.invalidSourceMode
        }
        return sourceMode
    }

    private static func parseFrameCount(_ rawValue: String) throws -> Int {
        if rawValue == "continuous" {
            return 0
        }
        guard let frameCount = Int(rawValue), frameCount >= 0 else {
            throw NaruHelperVideoListenConfigurationError.invalidFrameCount
        }
        return frameCount
    }
}

public enum NaruHelperVideoListenConfigurationError: Error, Equatable, Sendable {
    case missingToken
    case missingProfileFingerprint
    case directTokenArgumentUnsupported
    case directProfileFingerprintArgumentUnsupported
    case invalidPort
    case invalidSourceMode
    case invalidFrameCount
    case unsupportedPlatform
}

public struct NaruHelperVideoListenRuntime: Sendable {
    public typealias ScreenRecordingPermissionProvider =
        @Sendable () -> HelperVideoScreenRecordingPermission

    public var configuration: NaruHelperVideoListenConfiguration
    private let screenRecordingPermissionProvider: ScreenRecordingPermissionProvider

    public init(
        configuration: NaruHelperVideoListenConfiguration,
        screenRecordingPermissionProvider: @escaping ScreenRecordingPermissionProvider =
            Self.liveScreenRecordingPermission
    ) {
        self.configuration = configuration
        self.screenRecordingPermissionProvider = screenRecordingPermissionProvider
    }

    public func makeServer(
        accessUnitSource overrideAccessUnitSource: (any NaruHelperVideoAccessUnitSource)? = nil,
        capabilityProvider overrideCapabilityProvider: NaruHelperVideoTransportRequestHandler
            .CapabilityProvider? = nil
    ) throws -> NaruHelperVideoStreamNetworkServer {
        let accessUnitSource = try overrideAccessUnitSource ?? makeAccessUnitSource()
        let requestHandler = NaruHelperVideoTransportRequestHandler(
            expectedPairingSecret: configuration.pairingSecret,
            expectedProfileFingerprint: configuration.profileFingerprint,
            capabilityProvider: overrideCapabilityProvider ?? defaultCapabilityProvider(),
            startStreamProvider: defaultStartStreamProvider()
        )
        let pipeline = NaruHelperVideoStreamFramePipeline(
            requestHandler: requestHandler,
            accessUnitSource: accessUnitSource
        )

        if configuration.port == 0 {
            return try NaruHelperVideoStreamNetworkServer(
                pipeline: pipeline,
                transportProtection: .authenticatedPrivateProfile
            )
        }
        return try NaruHelperVideoStreamNetworkServer(
            port: configuration.port,
            pipeline: pipeline,
            transportProtection: .authenticatedPrivateProfile
        )
    }

    private func makeAccessUnitSource() throws -> any NaruHelperVideoAccessUnitSource {
        switch configuration.sourceMode {
        case .syntheticEncoded:
            return NaruHelperVideoToolboxSyntheticAccessUnitSource(
                frameCount: configuration.frameCount
            )
        case .screenCaptureKit:
            #if os(macOS)
            return NaruHelperVideoScreenCaptureKitAccessUnitSource(
                frameCount: configuration.frameCount
            )
            #else
            throw NaruHelperVideoListenConfigurationError.unsupportedPlatform
            #endif
        }
    }

    private func defaultCapabilityProvider() -> NaruHelperVideoTransportRequestHandler
        .CapabilityProvider
    {
        {
            let screenRecordingPermission = screenRecordingPermissionStatus()
            let isAvailable = configuration.sourceMode == .syntheticEncoded
                || screenRecordingPermission == .granted
            return HelperVideoCapabilityResponseBody(
                availability: isAvailable ? .available : .permissionMissing,
                screenRecordingPermission: screenRecordingPermission,
                codecSupport: isAvailable ? .h264 : .unknown,
                latencyModes: isAvailable ? [.lowLatency] : [],
                safeFailureCode: isAvailable ? nil : .permissionMissing
            )
        }
    }

    private func defaultStartStreamProvider() -> NaruHelperVideoTransportRequestHandler
        .StartStreamProvider
    {
        {
            request in
            let response = NaruHelperVideoTransportRequestHandler
                .defaultStartStreamResponse(request: request)
            guard response.result == .accepted else {
                return response
            }
            guard configuration.sourceMode == .screenCaptureKit else {
                return response
            }
            guard screenRecordingPermissionStatus() == .granted else {
                return HelperVideoStartStreamResponseBody(
                    result: .rejected,
                    safeFailureCode: .permissionMissing
                )
            }
            return response
        }
    }

    private func screenRecordingPermissionStatus() -> HelperVideoScreenRecordingPermission {
        switch configuration.sourceMode {
        case .screenCaptureKit:
            return screenRecordingPermissionProvider()
        case .syntheticEncoded:
            return .unsupported
        }
    }

    public static func liveScreenRecordingPermission() -> HelperVideoScreenRecordingPermission {
        #if os(macOS) && canImport(CoreGraphics)
        return CGPreflightScreenCaptureAccess() ? .granted : .missing
        #else
        return .unsupported
        #endif
    }
}
#endif
