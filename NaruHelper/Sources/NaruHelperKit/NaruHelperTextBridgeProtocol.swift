import Foundation
import NaruRemoteCore

public let naruHelperTextBridgeSchemaVersion = 1

public struct NaruHelperPermissionState: Codable, Equatable, Sendable {
    public var accessibility: String
    public var inputMonitoring: String
    public var pasteboardFallback: String
    public var activeUserSession: String

    public init(
        accessibility: String,
        inputMonitoring: String,
        pasteboardFallback: String,
        activeUserSession: String
    ) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.pasteboardFallback = pasteboardFallback
        self.activeUserSession = activeUserSession
    }
}

public struct NaruHelperCapabilityResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var availability: HelperTextBridgeAvailability
    public var permissionState: NaruHelperPermissionState
    public var supportedStrategies: [HelperTextInsertStrategy]

    public init(
        schemaVersion: Int = naruHelperTextBridgeSchemaVersion,
        availability: HelperTextBridgeAvailability,
        permissionState: NaruHelperPermissionState,
        supportedStrategies: [HelperTextInsertStrategy]
    ) {
        self.schemaVersion = schemaVersion
        self.availability = availability
        self.permissionState = permissionState
        self.supportedStrategies = supportedStrategies
    }
}

public struct NaruHelperInsertTextRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestID
        case payloadEncoding
        case payloadSizeBucket
        case strategyPreference
        case text
    }

    public var schemaVersion: Int
    public var requestID: UUID
    public var payloadEncoding: TextInjectionPayloadEncoding
    public var payloadSizeBucket: HelperTextPayloadSizeBucket
    public var strategyPreference: [HelperTextInsertStrategy]
    public var text: String

    public init(
        schemaVersion: Int = naruHelperTextBridgeSchemaVersion,
        requestID: UUID,
        payloadEncoding: TextInjectionPayloadEncoding,
        payloadSizeBucket: HelperTextPayloadSizeBucket,
        strategyPreference: [HelperTextInsertStrategy] = [.nativeInsert, .pasteboardPasteWithRestore],
        text: String
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.payloadEncoding = payloadEncoding
        self.payloadSizeBucket = payloadSizeBucket
        self.strategyPreference = strategyPreference
        self.text = text
    }
}

public struct NaruHelperInsertTextResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestID
        case status
        case strategyUsed
        case safeFailureCode
    }

    public var schemaVersion: Int
    public var requestID: UUID
    public var status: TextInjectionStatus
    public var strategyUsed: HelperTextInsertStrategy
    public var safeFailureCode: HelperTextBridgeFailureCode

    public init(
        schemaVersion: Int = naruHelperTextBridgeSchemaVersion,
        requestID: UUID,
        status: TextInjectionStatus,
        strategyUsed: HelperTextInsertStrategy,
        safeFailureCode: HelperTextBridgeFailureCode = .none
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.status = status
        self.strategyUsed = strategyUsed
        self.safeFailureCode = safeFailureCode
    }
}
