import Foundation
import NaruRemoteCore

public enum NaruHelperVideoTransportAuthorizationStatus: String, Codable, Equatable, Sendable {
    case accepted
    case rejected
}

public struct NaruHelperVideoTransportAuthorizationResult: Codable, Equatable, Sendable {
    public var status: NaruHelperVideoTransportAuthorizationStatus
    public var safeFailureCode: HelperVideoFailureCode?

    public init(
        status: NaruHelperVideoTransportAuthorizationStatus,
        safeFailureCode: HelperVideoFailureCode? = nil
    ) {
        self.status = status
        self.safeFailureCode = safeFailureCode
    }

    public static let accepted = NaruHelperVideoTransportAuthorizationResult(status: .accepted)
}

public struct NaruHelperVideoTransportRequestHandler: Sendable {
    public typealias CapabilityProvider = @Sendable () -> HelperVideoCapabilityResponseBody
    public typealias StartStreamProvider = @Sendable (
        HelperVideoStartStreamRequestBody
    ) -> HelperVideoStartStreamResponseBody

    private let expectedPairingSecret: String
    private let expectedProfileFingerprint: String
    private let revocationStore: any NaruHelperPairingRevocationStore
    private let capabilityProvider: CapabilityProvider
    private let startStreamProvider: StartStreamProvider

    public init(
        expectedPairingSecret: String,
        expectedProfileFingerprint: String,
        revocationStore: any NaruHelperPairingRevocationStore = InMemoryNaruHelperPairingRevocationStore(),
        capabilityProvider: @escaping CapabilityProvider,
        startStreamProvider: @escaping StartStreamProvider = Self.defaultStartStreamResponse
    ) {
        self.expectedPairingSecret = expectedPairingSecret
        self.expectedProfileFingerprint = expectedProfileFingerprint
        self.revocationStore = revocationStore
        self.capabilityProvider = capabilityProvider
        self.startStreamProvider = startStreamProvider
    }

    public func handleCapabilityFrame(_ frame: Data) throws -> Data {
        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoCapabilityRequestBody>.self,
            from: frame
        )
        let response = handleCapabilityRequest(decoded.envelope)
        return try HelperVideoWireCodec.frame(response)
    }

    public func handleStartStreamFrame(_ frame: Data) throws -> Data {
        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody>.self,
            from: frame
        )
        let response = handleStartStreamRequest(decoded.envelope)
        return try HelperVideoWireCodec.frame(response)
    }

    public func handleCapabilityRequest(
        _ envelope: HelperVideoWireEnvelope<HelperVideoCapabilityRequestBody>
    ) -> HelperVideoWireEnvelope<HelperVideoCapabilityResponseBody> {
        guard envelope.messageType == .capabilityRequest else {
            return responseEnvelope(
                for: envelope,
                messageType: .capabilityRequest,
                body: HelperVideoCapabilityResponseBody(
                    availability: .failed,
                    safeFailureCode: .transportFailed
                )
            )
        }

        let authorization = authorize(envelope)
        guard authorization.status == .accepted else {
            return responseEnvelope(
                for: envelope,
                messageType: .capabilityRequest,
                body: HelperVideoCapabilityResponseBody(
                    availability: .failed,
                    safeFailureCode: authorization.safeFailureCode
                )
            )
        }

        return responseEnvelope(
            for: envelope,
            messageType: .capabilityRequest,
            body: capabilityProvider()
        )
    }

    public func handleStartStreamRequest(
        _ envelope: HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody>
    ) -> HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody> {
        guard envelope.messageType == .startStream else {
            return responseEnvelope(
                for: envelope,
                messageType: .startStream,
                body: HelperVideoStartStreamResponseBody(
                    result: .rejected,
                    safeFailureCode: .transportFailed
                )
            )
        }

        let authorization = authorize(envelope)
        guard authorization.status == .accepted else {
            return responseEnvelope(
                for: envelope,
                messageType: .startStream,
                body: HelperVideoStartStreamResponseBody(
                    result: .rejected,
                    safeFailureCode: authorization.safeFailureCode
                )
            )
        }

        return responseEnvelope(
            for: envelope,
            messageType: .startStream,
            body: startStreamProvider(envelope.body)
        )
    }

    public func authorize<Body: Codable & Equatable & Sendable>(
        _ envelope: HelperVideoWireEnvelope<Body>
    ) -> NaruHelperVideoTransportAuthorizationResult {
        guard envelope.schemaVersion == naruHelperVideoStreamSchemaVersion else {
            return NaruHelperVideoTransportAuthorizationResult(
                status: .rejected,
                safeFailureCode: .transportFailed
            )
        }

        guard envelope.profileFingerprint == expectedProfileFingerprint else {
            return NaruHelperVideoTransportAuthorizationResult(
                status: .rejected,
                safeFailureCode: .authFailed
            )
        }

        guard !revocationStore.isRevoked(pairingSecret: expectedPairingSecret) else {
            return NaruHelperVideoTransportAuthorizationResult(
                status: .rejected,
                safeFailureCode: .revoked
            )
        }

        guard HelperVideoAuthProof.verify(
            envelope.authProof,
            requestID: envelope.requestID,
            messageType: envelope.messageType,
            profileFingerprint: envelope.profileFingerprint,
            pairingSecret: expectedPairingSecret
        ) else {
            return NaruHelperVideoTransportAuthorizationResult(
                status: .rejected,
                safeFailureCode: .authFailed
            )
        }

        return .accepted
    }

    public static func signedEnvelope<Body: Codable & Equatable & Sendable>(
        requestID: UUID = UUID(),
        messageType: HelperVideoMessageType,
        profileFingerprint: String,
        pairingSecret: String,
        body: Body
    ) -> HelperVideoWireEnvelope<Body> {
        let proof = HelperVideoAuthProof.make(
            requestID: requestID,
            messageType: messageType,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret
        )
        return HelperVideoWireEnvelope(
            requestID: requestID,
            messageType: messageType,
            profileFingerprint: profileFingerprint,
            authProof: proof,
            body: body
        )
    }

    private func responseEnvelope<
        RequestBody: Codable & Equatable & Sendable,
        ResponseBody: Codable & Equatable & Sendable
    >(
        for request: HelperVideoWireEnvelope<RequestBody>,
        messageType: HelperVideoMessageType,
        body: ResponseBody
    ) -> HelperVideoWireEnvelope<ResponseBody> {
        HelperVideoWireEnvelope(
            requestID: request.requestID,
            messageType: messageType,
            profileFingerprint: request.profileFingerprint,
            authProof: nil,
            body: body
        )
    }

    public static func defaultStartStreamResponse(
        request: HelperVideoStartStreamRequestBody
    ) -> HelperVideoStartStreamResponseBody {
        guard request.codec == .h264 else {
            return HelperVideoStartStreamResponseBody(
                result: .rejected,
                safeFailureCode: .codecUnsupported
            )
        }

        return HelperVideoStartStreamResponseBody(
            result: .accepted,
            streamDescriptor: HelperVideoStreamDescriptor(
                codec: .h264,
                codecProfile: .high,
                latencyMode: request.latencyMode,
                qualityBucket: request.qualityBucket,
                frameRateBucket: request.maxFrameRateBucket,
                colorMode: .standardDynamicRange,
                supportsKeyframeRequest: true,
                supportsFallbackSignal: true
            )
        )
    }
}
