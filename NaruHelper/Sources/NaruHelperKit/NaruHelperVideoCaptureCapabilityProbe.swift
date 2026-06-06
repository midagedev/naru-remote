import Foundation
import NaruRemoteCore

#if os(macOS) && canImport(CoreGraphics) && canImport(ScreenCaptureKit)
import CoreGraphics
import ScreenCaptureKit
#endif

public let naruHelperVideoCapabilitySchemaVersion = 1

public enum NaruHelperVideoScreenRecordingPermission: String, Codable, Equatable, CaseIterable, Sendable {
    case granted
    case missing
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
