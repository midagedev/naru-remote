import Foundation
import NaruRemoteCore

#if os(macOS) && canImport(CoreGraphics) && canImport(ScreenCaptureKit)
import CoreGraphics
import ScreenCaptureKit
#endif

public let naruHelperVideoCapabilitySchemaVersion = 2
public let naruHelperVideoPermissionRequestSchemaVersion = 2

public enum NaruHelperVideoScreenRecordingPermission: String, Codable, Equatable, CaseIterable, Sendable {
    case granted
    case missing
    case unsupported
}

public enum NaruHelperVideoScreenRecordingPermissionRequestResult: String, Codable, Equatable, CaseIterable, Sendable {
    case granted
    case notGranted
    case unsupported
}

public enum NaruHelperVideoCaptureSourceState: String, Codable, Equatable, CaseIterable, Sendable {
    case notChecked
    case available
    case unavailable
    case unsupported
}

public enum NaruHelperVideoCaptureAPI: String, Codable, Equatable, CaseIterable, Sendable {
    case screenCaptureKit
}

public enum NaruHelperVideoPermissionProcessKind: String, Codable, Equatable, CaseIterable, Sendable {
    case appBundle
    case commandLineTool
    case swiftPMBuildArtifact
    case unsupported
    case unknown
}

public enum NaruHelperVideoPermissionGrantHint: String, Codable, Equatable, CaseIterable, Sendable {
    case grantAppBundle
    case grantCurrentHelperExecutable
    case useStableHelperExecutable
    case unsupported
    case unknown
}

public struct NaruHelperVideoPermissionIdentityContext: Codable, Equatable, Sendable {
    public var processKind: NaruHelperVideoPermissionProcessKind
    public var grantHint: NaruHelperVideoPermissionGrantHint

    public init(
        processKind: NaruHelperVideoPermissionProcessKind,
        grantHint: NaruHelperVideoPermissionGrantHint
    ) {
        self.processKind = processKind
        self.grantHint = grantHint
    }

    public static let unknown = NaruHelperVideoPermissionIdentityContext(
        processKind: .unknown,
        grantHint: .unknown
    )

    public static let unsupported = NaruHelperVideoPermissionIdentityContext(
        processKind: .unsupported,
        grantHint: .unsupported
    )

    public static func classify(
        bundleURL: URL?,
        executableURL: URL?
    ) -> NaruHelperVideoPermissionIdentityContext {
        if bundleURL?.pathExtension == "app" {
            return NaruHelperVideoPermissionIdentityContext(
                processKind: .appBundle,
                grantHint: .grantAppBundle
            )
        }
        if executableURL?.pathComponents.contains(".build") == true {
            return NaruHelperVideoPermissionIdentityContext(
                processKind: .swiftPMBuildArtifact,
                grantHint: .useStableHelperExecutable
            )
        }
        return NaruHelperVideoPermissionIdentityContext(
            processKind: .commandLineTool,
            grantHint: .grantCurrentHelperExecutable
        )
    }

    public static func live() -> NaruHelperVideoPermissionIdentityContext {
        #if os(macOS)
        return classify(
            bundleURL: Bundle.main.bundleURL,
            executableURL: Bundle.main.executableURL
        )
        #else
        return .unsupported
        #endif
    }
}

public struct NaruHelperVideoCaptureCapabilityResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var availability: HelperVideoAvailability
    public var screenRecordingPermission: NaruHelperVideoScreenRecordingPermission
    public var captureSourceState: NaruHelperVideoCaptureSourceState
    public var captureAPI: NaruHelperVideoCaptureAPI?
    public var permissionIdentity: NaruHelperVideoPermissionIdentityContext
    public var safeFailureCode: HelperVideoFailureCode?

    public init(
        schemaVersion: Int = naruHelperVideoCapabilitySchemaVersion,
        availability: HelperVideoAvailability,
        screenRecordingPermission: NaruHelperVideoScreenRecordingPermission,
        captureSourceState: NaruHelperVideoCaptureSourceState,
        captureAPI: NaruHelperVideoCaptureAPI? = nil,
        permissionIdentity: NaruHelperVideoPermissionIdentityContext = .unknown,
        safeFailureCode: HelperVideoFailureCode? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.availability = availability
        self.screenRecordingPermission = screenRecordingPermission
        self.captureSourceState = captureSourceState
        self.captureAPI = captureAPI
        self.permissionIdentity = permissionIdentity
        self.safeFailureCode = safeFailureCode
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case availability
        case screenRecordingPermission
        case captureSourceState
        case captureAPI
        case permissionIdentity
        case safeFailureCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.availability = try container.decode(
            HelperVideoAvailability.self,
            forKey: .availability
        )
        self.screenRecordingPermission = try container.decode(
            NaruHelperVideoScreenRecordingPermission.self,
            forKey: .screenRecordingPermission
        )
        self.captureSourceState = try container.decode(
            NaruHelperVideoCaptureSourceState.self,
            forKey: .captureSourceState
        )
        self.captureAPI = try container.decodeIfPresent(
            NaruHelperVideoCaptureAPI.self,
            forKey: .captureAPI
        )
        self.permissionIdentity = try container.decodeIfPresent(
            NaruHelperVideoPermissionIdentityContext.self,
            forKey: .permissionIdentity
        ) ?? .unknown
        self.safeFailureCode = try container.decodeIfPresent(
            HelperVideoFailureCode.self,
            forKey: .safeFailureCode
        )
    }
}

public struct NaruHelperVideoScreenRecordingPermissionRequestResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var availability: HelperVideoAvailability
    public var screenRecordingPermission: NaruHelperVideoScreenRecordingPermission
    public var requestResult: NaruHelperVideoScreenRecordingPermissionRequestResult
    public var captureAPI: NaruHelperVideoCaptureAPI?
    public var permissionIdentity: NaruHelperVideoPermissionIdentityContext
    public var safeFailureCode: HelperVideoFailureCode?

    public init(
        schemaVersion: Int = naruHelperVideoPermissionRequestSchemaVersion,
        availability: HelperVideoAvailability,
        screenRecordingPermission: NaruHelperVideoScreenRecordingPermission,
        requestResult: NaruHelperVideoScreenRecordingPermissionRequestResult,
        captureAPI: NaruHelperVideoCaptureAPI? = nil,
        permissionIdentity: NaruHelperVideoPermissionIdentityContext = .unknown,
        safeFailureCode: HelperVideoFailureCode? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.availability = availability
        self.screenRecordingPermission = screenRecordingPermission
        self.requestResult = requestResult
        self.captureAPI = captureAPI
        self.permissionIdentity = permissionIdentity
        self.safeFailureCode = safeFailureCode
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case availability
        case screenRecordingPermission
        case requestResult
        case captureAPI
        case permissionIdentity
        case safeFailureCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.availability = try container.decode(
            HelperVideoAvailability.self,
            forKey: .availability
        )
        self.screenRecordingPermission = try container.decode(
            NaruHelperVideoScreenRecordingPermission.self,
            forKey: .screenRecordingPermission
        )
        self.requestResult = try container.decode(
            NaruHelperVideoScreenRecordingPermissionRequestResult.self,
            forKey: .requestResult
        )
        self.captureAPI = try container.decodeIfPresent(
            NaruHelperVideoCaptureAPI.self,
            forKey: .captureAPI
        )
        self.permissionIdentity = try container.decodeIfPresent(
            NaruHelperVideoPermissionIdentityContext.self,
            forKey: .permissionIdentity
        ) ?? .unknown
        self.safeFailureCode = try container.decodeIfPresent(
            HelperVideoFailureCode.self,
            forKey: .safeFailureCode
        )
    }
}

public struct NaruHelperVideoScreenRecordingPermissionRequester: Sendable {
    public typealias PermissionRequest = @Sendable () -> Bool

    private let captureAPI: NaruHelperVideoCaptureAPI?
    private let permissionIdentityProvider: @Sendable () -> NaruHelperVideoPermissionIdentityContext
    private let permissionRequest: PermissionRequest

    public init(
        captureAPI: NaruHelperVideoCaptureAPI? = .screenCaptureKit,
        permissionIdentityProvider: @escaping @Sendable () -> NaruHelperVideoPermissionIdentityContext = {
            .unknown
        },
        permissionRequest: @escaping PermissionRequest
    ) {
        self.captureAPI = captureAPI
        self.permissionIdentityProvider = permissionIdentityProvider
        self.permissionRequest = permissionRequest
    }

    public func request() -> NaruHelperVideoScreenRecordingPermissionRequestResponse {
        let permissionIdentity = permissionIdentityProvider()
        guard let captureAPI else {
            return NaruHelperVideoScreenRecordingPermissionRequestResponse(
                availability: .failed,
                screenRecordingPermission: .unsupported,
                requestResult: .unsupported,
                permissionIdentity: permissionIdentity
            )
        }

        let isGranted = permissionRequest()
        return NaruHelperVideoScreenRecordingPermissionRequestResponse(
            availability: isGranted ? .available : .permissionMissing,
            screenRecordingPermission: isGranted ? .granted : .missing,
            requestResult: isGranted ? .granted : .notGranted,
            captureAPI: captureAPI,
            permissionIdentity: permissionIdentity,
            safeFailureCode: isGranted ? nil : .permissionMissing
        )
    }

    public static func live() -> NaruHelperVideoScreenRecordingPermissionRequester {
        #if os(macOS) && canImport(CoreGraphics) && canImport(ScreenCaptureKit)
        return NaruHelperVideoScreenRecordingPermissionRequester(
            permissionIdentityProvider: {
                .live()
            },
            permissionRequest: {
                CGRequestScreenCaptureAccess()
            }
        )
        #else
        return NaruHelperVideoScreenRecordingPermissionRequester(
            captureAPI: nil,
            permissionIdentityProvider: {
                .unsupported
            },
            permissionRequest: {
                false
            }
        )
        #endif
    }
}

public struct NaruHelperVideoCaptureCapabilityProbe: Sendable {
    public typealias PermissionProvider = @Sendable () -> NaruHelperVideoScreenRecordingPermission
    public typealias CaptureSourceProvider = @Sendable () async -> NaruHelperVideoCaptureSourceState

    private let permissionProvider: PermissionProvider
    private let captureSourceProvider: CaptureSourceProvider
    private let permissionIdentityProvider: @Sendable () -> NaruHelperVideoPermissionIdentityContext
    private let captureAPI: NaruHelperVideoCaptureAPI?

    public init(
        captureAPI: NaruHelperVideoCaptureAPI? = .screenCaptureKit,
        permissionProvider: @escaping PermissionProvider,
        captureSourceProvider: @escaping CaptureSourceProvider,
        permissionIdentityProvider: @escaping @Sendable () -> NaruHelperVideoPermissionIdentityContext = {
            .unknown
        }
    ) {
        self.captureAPI = captureAPI
        self.permissionProvider = permissionProvider
        self.captureSourceProvider = captureSourceProvider
        self.permissionIdentityProvider = permissionIdentityProvider
    }

    public func capability() async -> NaruHelperVideoCaptureCapabilityResponse {
        let permission = permissionProvider()
        let permissionIdentity = permissionIdentityProvider()
        guard permission == .granted else {
            return NaruHelperVideoCaptureCapabilityResponse(
                availability: permission == .missing ? .permissionMissing : .failed,
                screenRecordingPermission: permission,
                captureSourceState: permission == .unsupported ? .unsupported : .notChecked,
                captureAPI: permission == .unsupported ? nil : captureAPI,
                permissionIdentity: permissionIdentity,
                safeFailureCode: permission == .missing ? .permissionMissing : nil
            )
        }

        let sourceState = await captureSourceProvider()
        guard sourceState == .available else {
            return NaruHelperVideoCaptureCapabilityResponse(
                availability: .failed,
                screenRecordingPermission: .granted,
                captureSourceState: sourceState,
                captureAPI: captureAPI,
                permissionIdentity: permissionIdentity
            )
        }

        return NaruHelperVideoCaptureCapabilityResponse(
            availability: .available,
            screenRecordingPermission: .granted,
            captureSourceState: .available,
            captureAPI: captureAPI,
            permissionIdentity: permissionIdentity
        )
    }

    public static func live() -> NaruHelperVideoCaptureCapabilityProbe {
        #if os(macOS) && canImport(CoreGraphics) && canImport(ScreenCaptureKit)
        return NaruHelperVideoCaptureCapabilityProbe(
            permissionProvider: {
                CGPreflightScreenCaptureAccess() ? .granted : .missing
            },
            captureSourceProvider: {
                await LiveNaruHelperScreenCaptureKitProbe.captureSourceState()
            },
            permissionIdentityProvider: {
                .live()
            }
        )
        #else
        return NaruHelperVideoCaptureCapabilityProbe(
            captureAPI: nil,
            permissionProvider: {
                .unsupported
            },
            captureSourceProvider: {
                .unsupported
            },
            permissionIdentityProvider: {
                .unsupported
            }
        )
        #endif
    }
}

#if os(macOS) && canImport(ScreenCaptureKit)
private enum LiveNaruHelperScreenCaptureKitProbe {
    static func captureSourceState() async -> NaruHelperVideoCaptureSourceState {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return content.displays.isEmpty ? .unavailable : .available
        } catch {
            return .unavailable
        }
    }
}
#endif
