import Foundation

public enum HelperTextBridgeAvailability: String, Codable, Equatable, CaseIterable, Sendable {
    case notConfigured
    case disabled
    case checking
    case reachable
    case unreachable
    case permissionMissing
    case revoked
    case versionUnsupported
}

public enum HelperTextBridgeFailureCode: String, Codable, Equatable, CaseIterable, Sendable {
    case none
    case notConfigured = "helper.notConfigured"
    case disabled = "helper.disabled"
    case unreachable = "helper.unreachable"
    case revoked = "helper.revoked"
    case permissionMissing = "helper.permissionMissing"
    case focusUnavailable = "helper.focusUnavailable"
    case insertRejected = "helper.insertRejected"
    case insertTimedOut = "helper.insertTimedOut"
    case restoreFailed = "helper.restoreFailed"
    case versionUnsupported = "helper.versionUnsupported"
}

public enum HelperTextBridgeLastCheckedBucket: String, Codable, Equatable, CaseIterable, Sendable {
    case never
    case recent
    case stale
}

public enum HelperTextInsertStrategy: String, Codable, Equatable, CaseIterable, Sendable {
    case nativeInsert
    case pasteboardPasteWithRestore
    case unsupported
}

public enum HelperTextPayloadSizeBucket: String, Codable, Equatable, CaseIterable, Sendable {
    case empty
    case small
    case medium
    case large

    public static func bucket(utf8ByteCount: Int) -> HelperTextPayloadSizeBucket {
        switch max(utf8ByteCount, 0) {
        case 0:
            return .empty
        case ...256:
            return .small
        case ...4_096:
            return .medium
        default:
            return .large
        }
    }
}

public enum HelperTextBridgeRouteCapability: String, Codable, Equatable, CaseIterable, Sendable {
    case unknown
    case available
    case granted
    case missing
    case revoked
    case disabled
    case unsupported
    case restoreUnsupported

    public static func fixedCatalogValue(_ value: String?) -> HelperTextBridgeRouteCapability {
        guard let value,
              let catalogValue = HelperTextBridgeRouteCapability(rawValue: value)
        else {
            return .unknown
        }
        return catalogValue
    }
}

public struct HelperTextBridgeCapabilitySummary: Codable, Equatable, Sendable {
    public var nativeInsert: HelperTextBridgeRouteCapability
    public var accessibilityValueInsert: HelperTextBridgeRouteCapability
    public var unicodeKeyboardEvent: HelperTextBridgeRouteCapability
    public var pasteboardFallback: HelperTextBridgeRouteCapability

    public init(
        nativeInsert: HelperTextBridgeRouteCapability = .unknown,
        accessibilityValueInsert: HelperTextBridgeRouteCapability = .unknown,
        unicodeKeyboardEvent: HelperTextBridgeRouteCapability = .unknown,
        pasteboardFallback: HelperTextBridgeRouteCapability = .unknown
    ) {
        self.nativeInsert = nativeInsert
        self.accessibilityValueInsert = accessibilityValueInsert
        self.unicodeKeyboardEvent = unicodeKeyboardEvent
        self.pasteboardFallback = pasteboardFallback
    }

    public init(response: NaruHelperCapabilityResponse) {
        self.init(
            nativeInsert: response.supportedStrategies.contains(.nativeInsert) ? .available : .missing,
            accessibilityValueInsert: HelperTextBridgeRouteCapability.fixedCatalogValue(
                response.permissionState.accessibilityValueInsert ?? response.permissionState.accessibility
            ),
            unicodeKeyboardEvent: HelperTextBridgeRouteCapability.fixedCatalogValue(
                response.permissionState.unicodeKeyboardEvent
            ),
            pasteboardFallback: HelperTextBridgeRouteCapability.fixedCatalogValue(
                response.permissionState.pasteboardFallback
            )
        )
    }
}

public struct HelperTextBridgeProfileState: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var pairingFingerprint: String?
    public var availability: HelperTextBridgeAvailability
    public var lastFailureCode: HelperTextBridgeFailureCode?
    public var lastCheckedBucket: HelperTextBridgeLastCheckedBucket
    public var capabilitySummary: HelperTextBridgeCapabilitySummary?

    public init(
        isEnabled: Bool = false,
        pairingFingerprint: String? = nil,
        availability: HelperTextBridgeAvailability = .notConfigured,
        lastFailureCode: HelperTextBridgeFailureCode? = nil,
        lastCheckedBucket: HelperTextBridgeLastCheckedBucket = .never,
        capabilitySummary: HelperTextBridgeCapabilitySummary? = nil
    ) {
        self.isEnabled = isEnabled
        self.pairingFingerprint = pairingFingerprint
        self.availability = availability
        self.lastFailureCode = lastFailureCode
        self.lastCheckedBucket = lastCheckedBucket
        self.capabilitySummary = capabilitySummary
    }
}

public struct HelperTextInsertRequestMetadata: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let payloadEncoding: TextInjectionPayloadEncoding
    public let payloadSizeBucket: HelperTextPayloadSizeBucket
    public let strategyPreferences: [HelperTextInsertStrategy]

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        payloadEncoding: TextInjectionPayloadEncoding,
        payloadSizeBucket: HelperTextPayloadSizeBucket,
        strategyPreferences: [HelperTextInsertStrategy] = [.nativeInsert]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.payloadEncoding = payloadEncoding
        self.payloadSizeBucket = payloadSizeBucket
        self.strategyPreferences = strategyPreferences
    }
}

public struct HelperTextInsertResult: Codable, Equatable, Sendable {
    public let requestID: UUID
    public var strategyUsed: HelperTextInsertStrategy
    public var status: TextInjectionStatus
    public var safeFailureCode: HelperTextBridgeFailureCode

    public init(
        requestID: UUID,
        strategyUsed: HelperTextInsertStrategy,
        status: TextInjectionStatus,
        safeFailureCode: HelperTextBridgeFailureCode = .none
    ) {
        self.requestID = requestID
        self.strategyUsed = strategyUsed
        self.status = status
        self.safeFailureCode = safeFailureCode
    }
}

public protocol HelperTextInsertClient: AnyObject {
    var availability: HelperTextBridgeAvailability { get }

    func insertText(
        _ text: String,
        metadata: HelperTextInsertRequestMetadata
    ) async throws -> HelperTextInsertResult
}

public extension HelperTextInsertClient {
    var availability: HelperTextBridgeAvailability { .notConfigured }
}

public enum HelperTextBridgeError: Error, Equatable, LocalizedError, Sendable {
    case unavailable(HelperTextBridgeFailureCode)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let code):
            return Self.safeMessage(for: code)
        }
    }

    public static func safeMessage(for code: HelperTextBridgeFailureCode) -> String {
        switch code {
        case .none:
            return "Text sent through helper."
        case .notConfigured:
            return "Helper text bridge is not configured for this profile."
        case .disabled:
            return "Helper text bridge is disabled for this profile."
        case .unreachable:
            return "Helper text bridge is not reachable."
        case .revoked:
            return "Helper text bridge pairing was revoked."
        case .permissionMissing:
            return "Helper text bridge needs permission on the Mac."
        case .focusUnavailable:
            return "Helper text bridge could not find an insertable focused app."
        case .insertRejected:
            return "Helper text bridge rejected the insert request."
        case .insertTimedOut:
            return "Helper text bridge insert timed out."
        case .restoreFailed:
            return "Helper text bridge inserted text but could not confirm pasteboard restore."
        case .versionUnsupported:
            return "Helper text bridge version is unsupported."
        }
    }
}
