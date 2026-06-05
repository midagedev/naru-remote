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

public struct HelperTextBridgeProfileState: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var pairingFingerprint: String?
    public var availability: HelperTextBridgeAvailability
    public var lastFailureCode: HelperTextBridgeFailureCode?
    public var lastCheckedBucket: HelperTextBridgeLastCheckedBucket

    public init(
        isEnabled: Bool = false,
        pairingFingerprint: String? = nil,
        availability: HelperTextBridgeAvailability = .notConfigured,
        lastFailureCode: HelperTextBridgeFailureCode? = nil,
        lastCheckedBucket: HelperTextBridgeLastCheckedBucket = .never
    ) {
        self.isEnabled = isEnabled
        self.pairingFingerprint = pairingFingerprint
        self.availability = availability
        self.lastFailureCode = lastFailureCode
        self.lastCheckedBucket = lastCheckedBucket
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
        strategyPreferences: [HelperTextInsertStrategy] = [.nativeInsert, .pasteboardPasteWithRestore]
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
