import Foundation
import CryptoKit

public let naruHelperVideoStreamSchemaVersion = 1
public let naruHelperVideoStreamDefaultPort = 5975

public enum HelperVideoMessageType: String, Codable, Equatable, CaseIterable, Sendable {
    case capabilityRequest
    case startStream
    case videoAccessUnit
    case requestKeyframe
    case streamStalled
    case stopStream
}

public enum HelperVideoAccessUnitKind: String, Codable, Equatable, CaseIterable, Sendable {
    case parameterSet
    case keyframe
    case delta
    case endOfStream
}

public enum HelperVideoStartStreamResult: String, Codable, Equatable, CaseIterable, Sendable {
    case accepted
    case rejected
}

public enum HelperVideoKeyframeRequestReason: String, Codable, Equatable, CaseIterable, Sendable {
    case decoderRecovery
    case startup
    case userVisibleRecovery
}

public enum HelperVideoStreamStallReason: String, Codable, Equatable, CaseIterable, Sendable {
    case noAccessUnit
    case encoderUnavailable
    case transportBackpressure
    case unknown
}

public enum HelperVideoStopStreamReason: String, Codable, Equatable, CaseIterable, Sendable {
    case userDisabled
    case fallbackToVNC
    case sessionEnded
}

public enum HelperVideoScreenRecordingPermission: String, Codable, Equatable, CaseIterable, Sendable {
    case granted
    case missing
    case unsupported
}

public struct HelperVideoCapabilityRequestBody: Codable, Equatable, Sendable {
    public init() {}
}

public struct HelperVideoCapabilityResponseBody: Codable, Equatable, Sendable {
    public var availability: HelperVideoAvailability
    public var screenRecordingPermission: HelperVideoScreenRecordingPermission
    public var codecSupport: HelperVideoCodec
    public var latencyModes: [HelperVideoLatencyMode]
    public var safeFailureCode: HelperVideoFailureCode?

    public init(
        availability: HelperVideoAvailability = .notConfigured,
        screenRecordingPermission: HelperVideoScreenRecordingPermission = .unsupported,
        codecSupport: HelperVideoCodec = .unknown,
        latencyModes: [HelperVideoLatencyMode] = [],
        safeFailureCode: HelperVideoFailureCode? = nil
    ) {
        self.availability = availability
        self.screenRecordingPermission = screenRecordingPermission
        self.codecSupport = codecSupport
        self.latencyModes = latencyModes
        self.safeFailureCode = safeFailureCode
    }
}

public struct HelperVideoWireEnvelope<Body: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestID: UUID
    public var messageType: HelperVideoMessageType
    public var profileFingerprint: String?
    public var authProof: String?
    public var body: Body

    public init(
        schemaVersion: Int = naruHelperVideoStreamSchemaVersion,
        requestID: UUID = UUID(),
        messageType: HelperVideoMessageType,
        profileFingerprint: String? = nil,
        authProof: String? = nil,
        body: Body
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.messageType = messageType
        self.profileFingerprint = profileFingerprint
        self.authProof = authProof
        self.body = body
    }
}

public struct HelperVideoStartStreamRequestBody: Codable, Equatable, Sendable {
    public var codec: HelperVideoCodec
    public var latencyMode: HelperVideoLatencyMode
    public var qualityBucket: HelperVideoQualityBucket
    public var maxFrameRateBucket: HelperVideoFrameRateBucket

    public init(
        codec: HelperVideoCodec = .h264,
        latencyMode: HelperVideoLatencyMode = .lowLatency,
        qualityBucket: HelperVideoQualityBucket = .readability,
        maxFrameRateBucket: HelperVideoFrameRateBucket = .upTo30
    ) {
        self.codec = codec
        self.latencyMode = latencyMode
        self.qualityBucket = qualityBucket
        self.maxFrameRateBucket = maxFrameRateBucket
    }
}

public struct HelperVideoStartStreamResponseBody: Codable, Equatable, Sendable {
    public var result: HelperVideoStartStreamResult
    public var streamDescriptor: HelperVideoStreamDescriptor
    public var safeFailureCode: HelperVideoFailureCode?

    public init(
        result: HelperVideoStartStreamResult = .accepted,
        streamDescriptor: HelperVideoStreamDescriptor = HelperVideoStreamDescriptor(),
        safeFailureCode: HelperVideoFailureCode? = nil
    ) {
        self.result = result
        self.streamDescriptor = streamDescriptor
        self.safeFailureCode = safeFailureCode
    }
}

public enum HelperVideoAuthProof {
    public static let scheme = "hmac-sha256"

    public static func make(
        requestID: UUID,
        messageType: HelperVideoMessageType,
        profileFingerprint: String?,
        pairingSecret: String
    ) -> String {
        let key = SymmetricKey(data: Data(pairingSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(
            for: canonicalMessage(
                requestID: requestID,
                messageType: messageType,
                profileFingerprint: profileFingerprint
            ),
            using: key
        )
        return "\(scheme):\(Data(signature).hexEncodedString())"
    }

    public static func verify(
        _ proof: String?,
        requestID: UUID,
        messageType: HelperVideoMessageType,
        profileFingerprint: String?,
        pairingSecret: String
    ) -> Bool {
        guard let proof, !pairingSecret.isEmpty else {
            return false
        }
        let expected = make(
            requestID: requestID,
            messageType: messageType,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret
        )
        return constantTimeEqual(proof, expected)
    }

    private static func canonicalMessage(
        requestID: UUID,
        messageType: HelperVideoMessageType,
        profileFingerprint: String?
    ) -> Data {
        [
            String(naruHelperVideoStreamSchemaVersion),
            requestID.uuidString.lowercased(),
            messageType.rawValue,
            profileFingerprint ?? ""
        ].reduce(into: Data()) { data, field in
            let fieldData = Data(field.utf8)
            var length = UInt32(fieldData.count).bigEndian
            data.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
            data.append(fieldData)
        }
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else {
            return false
        }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
}

public struct HelperVideoAccessUnitBody: Codable, Equatable, Sendable {
    public var sequence: Int
    public var kind: HelperVideoAccessUnitKind

    public init(sequence: Int, kind: HelperVideoAccessUnitKind) {
        self.sequence = max(sequence, 0)
        self.kind = kind
    }
}

public struct HelperVideoKeyframeRequestBody: Codable, Equatable, Sendable {
    public var reason: HelperVideoKeyframeRequestReason

    public init(reason: HelperVideoKeyframeRequestReason = .decoderRecovery) {
        self.reason = reason
    }
}

public struct HelperVideoStreamStallBody: Codable, Equatable, Sendable {
    public var reason: HelperVideoStreamStallReason
    public var health: HelperVideoStreamHealth

    public init(
        reason: HelperVideoStreamStallReason = .unknown,
        health: HelperVideoStreamHealth = HelperVideoStreamHealth(state: .stalled)
    ) {
        self.reason = reason
        self.health = health
    }
}

public struct HelperVideoStopStreamBody: Codable, Equatable, Sendable {
    public var reason: HelperVideoStopStreamReason

    public init(reason: HelperVideoStopStreamReason = .userDisabled) {
        self.reason = reason
    }
}

public struct HelperVideoDecodedFrame<Envelope: Decodable & Equatable & Sendable>: Equatable, Sendable {
    public var envelope: Envelope
    public var binaryPayload: Data?

    public init(envelope: Envelope, binaryPayload: Data? = nil) {
        self.envelope = envelope
        self.binaryPayload = binaryPayload
    }
}

public enum HelperVideoWireCodecError: Error, Equatable, Sendable {
    case invalidLength
    case oversizedJSONFrame
    case oversizedBinaryPayload
    case truncatedFrame
    case unexpectedBinaryPayload
}

public enum HelperVideoWireCodec {
    public static let headerByteCount = 4
    public static let maximumJSONFrameByteCount = 65_536
    public static let maximumBinaryPayloadByteCount = 16_777_216

    public static func frame<T: Encodable>(_ envelope: T) throws -> Data {
        try framedJSON(envelope)
    }

    public static func frameAccessUnit(
        _ envelope: HelperVideoWireEnvelope<HelperVideoAccessUnitBody>,
        binaryPayload: Data
    ) throws -> Data {
        guard binaryPayload.count <= maximumBinaryPayloadByteCount else {
            throw HelperVideoWireCodecError.oversizedBinaryPayload
        }

        var frame = try framedJSON(envelope)
        var length = UInt32(binaryPayload.count).bigEndian
        frame.append(Data(bytes: &length, count: headerByteCount))
        frame.append(binaryPayload)
        return frame
    }

    public static func decodeFrame<Envelope: Decodable & Equatable & Sendable>(
        _ type: Envelope.Type,
        from frame: Data,
        expectsBinaryPayload: Bool = false
    ) throws -> HelperVideoDecodedFrame<Envelope> {
        guard frame.count >= headerByteCount else {
            throw HelperVideoWireCodecError.truncatedFrame
        }

        let jsonLength = try jsonPayloadLength(from: frame.prefixData(headerByteCount))
        let jsonStart = headerByteCount
        let jsonEnd = jsonStart + jsonLength
        guard frame.count >= jsonEnd else {
            throw HelperVideoWireCodecError.truncatedFrame
        }

        let jsonPayload = frame.subdata(in: jsonStart..<jsonEnd)
        let envelope = try JSONDecoder().decode(type, from: jsonPayload)
        let remaining = frame.count - jsonEnd

        guard expectsBinaryPayload else {
            guard remaining == 0 else {
                throw HelperVideoWireCodecError.unexpectedBinaryPayload
            }
            return HelperVideoDecodedFrame(envelope: envelope)
        }

        guard remaining >= headerByteCount else {
            throw HelperVideoWireCodecError.truncatedFrame
        }

        let binaryLengthStart = jsonEnd
        let binaryLengthEnd = binaryLengthStart + headerByteCount
        let binaryLength = try binaryPayloadLength(from: frame.subdata(in: binaryLengthStart..<binaryLengthEnd))
        let binaryStart = binaryLengthEnd
        let binaryEnd = binaryStart + binaryLength
        guard frame.count >= binaryEnd else {
            throw HelperVideoWireCodecError.truncatedFrame
        }
        guard frame.count == binaryEnd else {
            throw HelperVideoWireCodecError.unexpectedBinaryPayload
        }

        return HelperVideoDecodedFrame(
            envelope: envelope,
            binaryPayload: frame.subdata(in: binaryStart..<binaryEnd)
        )
    }

    public static func jsonPayloadLength(from header: Data) throws -> Int {
        try payloadLength(
            from: header,
            maximumByteCount: maximumJSONFrameByteCount,
            allowsZero: false,
            oversizedError: .oversizedJSONFrame
        )
    }

    public static func binaryPayloadLength(from header: Data) throws -> Int {
        try payloadLength(
            from: header,
            maximumByteCount: maximumBinaryPayloadByteCount,
            allowsZero: true,
            oversizedError: .oversizedBinaryPayload
        )
    }

    private static func framedJSON<T: Encodable>(_ envelope: T) throws -> Data {
        let payload = try JSONEncoder().encode(envelope)
        guard payload.count <= maximumJSONFrameByteCount else {
            throw HelperVideoWireCodecError.oversizedJSONFrame
        }

        var length = UInt32(payload.count).bigEndian
        var data = Data(bytes: &length, count: headerByteCount)
        data.append(payload)
        return data
    }

    private static func payloadLength(
        from header: Data,
        maximumByteCount: Int,
        allowsZero: Bool,
        oversizedError: HelperVideoWireCodecError
    ) throws -> Int {
        guard header.count == headerByteCount else {
            throw HelperVideoWireCodecError.invalidLength
        }

        let bytes = [UInt8](header)
        let value = UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
        let length = Int(value)
        let range = allowsZero ? 0...maximumByteCount : 1...maximumByteCount
        guard range.contains(length) else {
            throw oversizedError
        }
        return length
    }
}

private extension Data {
    func prefixData(_ count: Int) -> Data {
        Data(prefix(count))
    }

    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
