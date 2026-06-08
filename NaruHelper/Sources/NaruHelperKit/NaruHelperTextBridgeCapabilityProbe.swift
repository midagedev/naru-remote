import Foundation
import NaruRemoteCore

#if os(macOS)
import ApplicationServices
import CoreGraphics
#endif

public let naruHelperTextPermissionRequestSchemaVersion = 1

public enum NaruHelperTextPermissionRequestResult: String, Codable, Equatable, CaseIterable, Sendable {
    case granted
    case notGranted
    case unsupported
}

public struct NaruHelperTextPermissionRequestResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var availability: HelperTextBridgeAvailability
    public var accessibilityValueInsert: HelperTextBridgeRouteCapability
    public var unicodeKeyboardEvent: HelperTextBridgeRouteCapability
    public var pasteboardFallback: HelperTextBridgeRouteCapability
    public var requestResult: NaruHelperTextPermissionRequestResult
    public var permissionIdentity: NaruHelperVideoPermissionIdentityContext
    public var safeFailureCode: HelperTextBridgeFailureCode?

    public init(
        schemaVersion: Int = naruHelperTextPermissionRequestSchemaVersion,
        availability: HelperTextBridgeAvailability,
        accessibilityValueInsert: HelperTextBridgeRouteCapability,
        unicodeKeyboardEvent: HelperTextBridgeRouteCapability,
        pasteboardFallback: HelperTextBridgeRouteCapability,
        requestResult: NaruHelperTextPermissionRequestResult,
        permissionIdentity: NaruHelperVideoPermissionIdentityContext = .unknown,
        safeFailureCode: HelperTextBridgeFailureCode? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.availability = availability
        self.accessibilityValueInsert = accessibilityValueInsert
        self.unicodeKeyboardEvent = unicodeKeyboardEvent
        self.pasteboardFallback = pasteboardFallback
        self.requestResult = requestResult
        self.permissionIdentity = permissionIdentity
        self.safeFailureCode = safeFailureCode
    }
}

public enum NaruHelperTextBridgeCapabilityProbe {
    public static func response(
        platformSupported: Bool = true,
        canInsertWithAccessibility: Bool,
        canInsertWithUnicodeEvents: Bool,
        canFallbackToPasteboard: Bool
    ) -> NaruHelperCapabilityResponse {
        guard platformSupported else {
            return NaruHelperCapabilityResponse(
                availability: .versionUnsupported,
                permissionState: NaruHelperPermissionState(
                    accessibility: "unsupported",
                    accessibilityValueInsert: "unsupported",
                    unicodeKeyboardEvent: "unsupported",
                    inputMonitoring: "notRequired",
                    pasteboardFallback: "unsupported",
                    activeUserSession: "unsupported"
                ),
                supportedStrategies: []
            )
        }

        let canInsertNatively = canInsertWithAccessibility || canInsertWithUnicodeEvents
        var supportedStrategies: [HelperTextInsertStrategy] = []
        if canInsertNatively {
            supportedStrategies.append(.nativeInsert)
        }
        if canFallbackToPasteboard {
            supportedStrategies.append(.pasteboardPasteWithRestore)
        }

        return NaruHelperCapabilityResponse(
            availability: supportedStrategies.isEmpty ? .permissionMissing : .reachable,
            permissionState: NaruHelperPermissionState(
                accessibility: canInsertWithAccessibility ? "granted" : "missing",
                accessibilityValueInsert: canInsertWithAccessibility ? "granted" : "missing",
                unicodeKeyboardEvent: canInsertWithUnicodeEvents ? "granted" : "missing",
                inputMonitoring: "notRequired",
                pasteboardFallback: canFallbackToPasteboard ? "available" : "missing",
                activeUserSession: "available"
            ),
            supportedStrategies: supportedStrategies
        )
    }
}

public struct NaruHelperTextPermissionRequester {
    public typealias PermissionProvider = () -> Bool
    public typealias PermissionRequest = () -> Bool

    private let platformSupported: Bool
    private let accessibilityPermissionProvider: PermissionProvider
    private let postEventPermissionProvider: PermissionProvider
    private let accessibilityPermissionRequest: PermissionRequest
    private let postEventPermissionRequest: PermissionRequest
    private let permissionIdentityProvider: () -> NaruHelperVideoPermissionIdentityContext

    public init(
        platformSupported: Bool = true,
        accessibilityPermissionProvider: @escaping PermissionProvider,
        postEventPermissionProvider: @escaping PermissionProvider,
        accessibilityPermissionRequest: @escaping PermissionRequest,
        postEventPermissionRequest: @escaping PermissionRequest,
        permissionIdentityProvider: @escaping () -> NaruHelperVideoPermissionIdentityContext = {
            .unknown
        }
    ) {
        self.platformSupported = platformSupported
        self.accessibilityPermissionProvider = accessibilityPermissionProvider
        self.postEventPermissionProvider = postEventPermissionProvider
        self.accessibilityPermissionRequest = accessibilityPermissionRequest
        self.postEventPermissionRequest = postEventPermissionRequest
        self.permissionIdentityProvider = permissionIdentityProvider
    }

    public func request() -> NaruHelperTextPermissionRequestResponse {
        let permissionIdentity = permissionIdentityProvider()
        guard platformSupported else {
            return NaruHelperTextPermissionRequestResponse(
                availability: .versionUnsupported,
                accessibilityValueInsert: .unsupported,
                unicodeKeyboardEvent: .unsupported,
                pasteboardFallback: .unsupported,
                requestResult: .unsupported,
                permissionIdentity: permissionIdentity,
                safeFailureCode: .versionUnsupported
            )
        }

        _ = accessibilityPermissionRequest()
        _ = postEventPermissionRequest()

        let accessibilityGranted = accessibilityPermissionProvider()
        let postEventGranted = postEventPermissionProvider()
        let nativeAvailable = accessibilityGranted || postEventGranted

        return NaruHelperTextPermissionRequestResponse(
            availability: nativeAvailable ? .reachable : .permissionMissing,
            accessibilityValueInsert: accessibilityGranted ? .granted : .missing,
            unicodeKeyboardEvent: postEventGranted ? .granted : .missing,
            pasteboardFallback: postEventGranted ? .available : .missing,
            requestResult: nativeAvailable ? .granted : .notGranted,
            permissionIdentity: permissionIdentity,
            safeFailureCode: nativeAvailable ? nil : .permissionMissing
        )
    }

    public static func live() -> NaruHelperTextPermissionRequester {
        #if os(macOS)
        return NaruHelperTextPermissionRequester(
            accessibilityPermissionProvider: {
                AXIsProcessTrusted()
            },
            postEventPermissionProvider: {
                CGPreflightPostEventAccess()
            },
            accessibilityPermissionRequest: {
                let options = [
                    "AXTrustedCheckOptionPrompt": true
                ] as CFDictionary
                return AXIsProcessTrustedWithOptions(options)
            },
            postEventPermissionRequest: {
                CGRequestPostEventAccess()
            },
            permissionIdentityProvider: {
                .live()
            }
        )
        #else
        return NaruHelperTextPermissionRequester(
            platformSupported: false,
            accessibilityPermissionProvider: {
                false
            },
            postEventPermissionProvider: {
                false
            },
            accessibilityPermissionRequest: {
                false
            },
            postEventPermissionRequest: {
                false
            },
            permissionIdentityProvider: {
                .unsupported
            }
        )
        #endif
    }
}
