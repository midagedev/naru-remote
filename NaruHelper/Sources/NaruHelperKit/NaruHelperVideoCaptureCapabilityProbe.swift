import Foundation
import NaruRemoteCore

#if os(macOS) && canImport(CoreGraphics) && canImport(ScreenCaptureKit)
import CoreGraphics
import ScreenCaptureKit
#endif

public let naruHelperVideoCapabilitySchemaVersion = 1
public let naruHelperVideoPermissionRequestSchemaVersion = 1

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

public struct NaruHelperVideoCaptureCapabilityResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var availability: HelperVideoAvailability
    public var screenRecordingPermission: NaruHelperVideoScreenRecordingPermission
    public var captureSourceState: NaruHelperVideoCaptureSourceState
    public var captureAPI: NaruHelperVideoCaptureAPI?
    public var safeFailureCode: HelperVideoFailureCode?

    public init(
        schemaVersion: Int = naruHelperVideoCapabilitySchemaVersion,
        availability: HelperVideoAvailability,
        screenRecordingPermission: NaruHelperVideoScreenRecordingPermission,
        captureSourceState: NaruHelperVideoCaptureSourceState,
        captureAPI: NaruHelperVideoCaptureAPI? = nil,
        safeFailureCode: HelperVideoFailureCode? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.availability = availability
        self.screenRecordingPermission = screenRecordingPermission
        self.captureSourceState = captureSourceState
        self.captureAPI = captureAPI
        self.safeFailureCode = safeFailureCode
    }
}

public struct NaruHelperVideoScreenRecordingPermissionRequestResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var availability: HelperVideoAvailability
    public var screenRecordingPermission: NaruHelperVideoScreenRecordingPermission
    public var requestResult: NaruHelperVideoScreenRecordingPermissionRequestResult
    public var captureAPI: NaruHelperVideoCaptureAPI?
    public var safeFailureCode: HelperVideoFailureCode?

    public init(
        schemaVersion: Int = naruHelperVideoPermissionRequestSchemaVersion,
        availability: HelperVideoAvailability,
        screenRecordingPermission: NaruHelperVideoScreenRecordingPermission,
        requestResult: NaruHelperVideoScreenRecordingPermissionRequestResult,
        captureAPI: NaruHelperVideoCaptureAPI? = nil,
        safeFailureCode: HelperVideoFailureCode? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.availability = availability
        self.screenRecordingPermission = screenRecordingPermission
        self.requestResult = requestResult
        self.captureAPI = captureAPI
        self.safeFailureCode = safeFailureCode
    }
}

public struct NaruHelperVideoScreenRecordingPermissionRequester: Sendable {
    public typealias PermissionRequest = @Sendable () -> Bool

    private let captureAPI: NaruHelperVideoCaptureAPI?
    private let permissionRequest: PermissionRequest

    public init(
        captureAPI: NaruHelperVideoCaptureAPI? = .screenCaptureKit,
        permissionRequest: @escaping PermissionRequest
    ) {
        self.captureAPI = captureAPI
        self.permissionRequest = permissionRequest
    }

    public func request() -> NaruHelperVideoScreenRecordingPermissionRequestResponse {
        guard let captureAPI else {
            return NaruHelperVideoScreenRecordingPermissionRequestResponse(
                availability: .failed,
                screenRecordingPermission: .unsupported,
                requestResult: .unsupported
            )
        }

        let isGranted = permissionRequest()
        return NaruHelperVideoScreenRecordingPermissionRequestResponse(
            availability: isGranted ? .available : .permissionMissing,
            screenRecordingPermission: isGranted ? .granted : .missing,
            requestResult: isGranted ? .granted : .notGranted,
            captureAPI: captureAPI,
            safeFailureCode: isGranted ? nil : .permissionMissing
        )
    }

    public static func live() -> NaruHelperVideoScreenRecordingPermissionRequester {
        #if os(macOS) && canImport(CoreGraphics) && canImport(ScreenCaptureKit)
        return NaruHelperVideoScreenRecordingPermissionRequester(
            permissionRequest: {
                CGRequestScreenCaptureAccess()
            }
        )
        #else
        return NaruHelperVideoScreenRecordingPermissionRequester(
            captureAPI: nil,
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
    private let captureAPI: NaruHelperVideoCaptureAPI?

    public init(
        captureAPI: NaruHelperVideoCaptureAPI? = .screenCaptureKit,
        permissionProvider: @escaping PermissionProvider,
        captureSourceProvider: @escaping CaptureSourceProvider
    ) {
        self.captureAPI = captureAPI
        self.permissionProvider = permissionProvider
        self.captureSourceProvider = captureSourceProvider
    }

    public func capability() async -> NaruHelperVideoCaptureCapabilityResponse {
        let permission = permissionProvider()
        guard permission == .granted else {
            return NaruHelperVideoCaptureCapabilityResponse(
                availability: permission == .missing ? .permissionMissing : .failed,
                screenRecordingPermission: permission,
                captureSourceState: permission == .unsupported ? .unsupported : .notChecked,
                captureAPI: permission == .unsupported ? nil : captureAPI,
                safeFailureCode: permission == .missing ? .permissionMissing : nil
            )
        }

        let sourceState = await captureSourceProvider()
        guard sourceState == .available else {
            return NaruHelperVideoCaptureCapabilityResponse(
                availability: .failed,
                screenRecordingPermission: .granted,
                captureSourceState: sourceState,
                captureAPI: captureAPI
            )
        }

        return NaruHelperVideoCaptureCapabilityResponse(
            availability: .available,
            screenRecordingPermission: .granted,
            captureSourceState: .available,
            captureAPI: captureAPI
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
