import Foundation

public let naruHelperTextBridgeSchemaVersion = 1
public let naruHelperTextBridgeDefaultPort = 5974

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

public enum NaruHelperNetworkCommand: String, Codable, Equatable, Sendable {
    case capability
    case insertText
    case revokePairing
}

public struct NaruHelperNetworkCapabilityRequest: Codable, Equatable, Sendable {
    public var requestedCapability: String
    public var profilePairingFingerprint: String?

    public init(
        requestedCapability: String = "text.nativeInsert",
        profilePairingFingerprint: String? = nil
    ) {
        self.requestedCapability = requestedCapability
        self.profilePairingFingerprint = profilePairingFingerprint
    }
}

public struct NaruHelperNetworkRequest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestID: UUID
    public var command: NaruHelperNetworkCommand
    /// Pairing secret for the helper transport. This value must never be
    /// persisted in diagnostics or logs; only a non-secret fingerprint may be
    /// exported.
    public var pairingSecret: String
    public var capabilityRequest: NaruHelperNetworkCapabilityRequest?
    public var insertRequest: NaruHelperInsertTextRequest?

    public init(
        schemaVersion: Int = naruHelperTextBridgeSchemaVersion,
        requestID: UUID = UUID(),
        command: NaruHelperNetworkCommand,
        pairingSecret: String,
        capabilityRequest: NaruHelperNetworkCapabilityRequest? = nil,
        insertRequest: NaruHelperInsertTextRequest? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.command = command
        self.pairingSecret = pairingSecret
        self.capabilityRequest = capabilityRequest
        self.insertRequest = insertRequest
    }
}

public struct NaruHelperNetworkResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestID: UUID
    public var capabilityResponse: NaruHelperCapabilityResponse?
    public var insertResponse: NaruHelperInsertTextResponse?
    public var safeFailureCode: HelperTextBridgeFailureCode

    public init(
        schemaVersion: Int = naruHelperTextBridgeSchemaVersion,
        requestID: UUID,
        capabilityResponse: NaruHelperCapabilityResponse? = nil,
        insertResponse: NaruHelperInsertTextResponse? = nil,
        safeFailureCode: HelperTextBridgeFailureCode = .none
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.capabilityResponse = capabilityResponse
        self.insertResponse = insertResponse
        self.safeFailureCode = safeFailureCode
    }
}

public enum NaruHelperNetworkCodecError: Error, Equatable, Sendable {
    case invalidLength
    case oversizedFrame
}

public enum NaruHelperNetworkCodec {
    public static let maximumFrameByteCount = 1_048_576
    public static let headerByteCount = 4

    public static func frame<T: Encodable>(_ value: T) throws -> Data {
        let payload = try JSONEncoder().encode(value)
        guard payload.count <= maximumFrameByteCount else {
            throw NaruHelperNetworkCodecError.oversizedFrame
        }

        var length = UInt32(payload.count).bigEndian
        var data = Data(bytes: &length, count: headerByteCount)
        data.append(payload)
        return data
    }

    public static func payloadLength(from header: Data) throws -> Int {
        guard header.count == headerByteCount else {
            throw NaruHelperNetworkCodecError.invalidLength
        }

        let bytes = [UInt8](header)
        let value = UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
        let length = Int(value)
        guard (1...maximumFrameByteCount).contains(length) else {
            throw NaruHelperNetworkCodecError.oversizedFrame
        }
        return length
    }

    public static func decode<T: Decodable>(_ type: T.Type, from payload: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: payload)
    }
}
