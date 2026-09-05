import Foundation
import NaruRemoteCore

#if os(macOS) && canImport(VideoToolbox)
import VideoToolbox
#endif

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
    /// Spec 041 FR-007: `nil` from a provider means the pairing state is
    /// gone — refusal, never a launch-time fallback.
    private let pairingSecretProvider: (@Sendable () -> String?)?
    private let profileFingerprintProvider: (@Sendable () -> String?)?
    private let revocationStore: any NaruHelperPairingRevocationStore
    private let onAuthorizedRequest: (@Sendable () -> Void)?
    private let capabilityProvider: CapabilityProvider
    private let startStreamProvider: StartStreamProvider
    private let hevcEncodeSupportProbe: @Sendable () -> Bool

    public init(
        expectedPairingSecret: String,
        expectedProfileFingerprint: String,
        pairingSecretProvider: (@Sendable () -> String?)? = nil,
        profileFingerprintProvider: (@Sendable () -> String?)? = nil,
        revocationStore: any NaruHelperPairingRevocationStore = InMemoryNaruHelperPairingRevocationStore(),
        onAuthorizedRequest: (@Sendable () -> Void)? = nil,
        capabilityProvider: @escaping CapabilityProvider,
        startStreamProvider: @escaping StartStreamProvider = Self.defaultStartStreamResponse,
        hevcEncodeSupportProbe: @escaping @Sendable () -> Bool = defaultHEVCEncodeSupportProbe
    ) {
        self.expectedPairingSecret = expectedPairingSecret
        self.expectedProfileFingerprint = expectedProfileFingerprint
        self.pairingSecretProvider = pairingSecretProvider
        self.profileFingerprintProvider = profileFingerprintProvider
        self.revocationStore = revocationStore
        self.onAuthorizedRequest = onAuthorizedRequest
        self.capabilityProvider = capabilityProvider
        self.startStreamProvider = startStreamProvider
        self.hevcEncodeSupportProbe = hevcEncodeSupportProbe
    }

    public static func defaultHEVCEncodeSupportProbe() -> Bool {
        #if os(macOS) && canImport(VideoToolbox)
        hevcHardwareEncoderIsAvailable()
        #else
        false
        #endif
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

        var body = startStreamProvider(envelope.body)
        if body.result == .accepted {
            let negotiated = Self.negotiatedCodec(
                request: envelope.body,
                hevcEncodeSupported: envelope.body.acceptsHEVC == true
                    && hevcEncodeSupportProbe()
            )
            body.streamDescriptor.codec = negotiated
            if negotiated == .hevc {
                body.streamDescriptor.codecProfile = .main
            }
        }
        return responseEnvelope(
            for: envelope,
            messageType: .startStream,
            body: body
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

        // Rotation (spec 040 FR-002) and revoke (spec 041 FR-007): when
        // providers are attached, every authorization reads the *current*
        // pairing state, so a token minted by a later `--pair` run takes
        // effect without restarting the listener, a superseded token is
        // refused from its next handshake, and a `nil` answer — the state
        // file is gone — is a refusal. The fixed configuration strings are
        // consulted only when no provider is attached (the env-pinned
        // benchmark path).
        let currentFingerprint: String
        if let profileFingerprintProvider {
            guard let providedFingerprint = profileFingerprintProvider() else {
                return NaruHelperVideoTransportAuthorizationResult(
                    status: .rejected,
                    safeFailureCode: .revoked
                )
            }
            currentFingerprint = providedFingerprint
        } else {
            currentFingerprint = expectedProfileFingerprint
        }
        let currentSecret: String
        if let pairingSecretProvider {
            guard let providedSecret = pairingSecretProvider() else {
                return NaruHelperVideoTransportAuthorizationResult(
                    status: .rejected,
                    safeFailureCode: .revoked
                )
            }
            currentSecret = providedSecret
        } else {
            currentSecret = expectedPairingSecret
        }

        guard envelope.profileFingerprint == currentFingerprint else {
            return NaruHelperVideoTransportAuthorizationResult(
                status: .rejected,
                safeFailureCode: .authFailed
            )
        }

        guard !revocationStore.isRevoked(pairingSecret: currentSecret) else {
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
            pairingSecret: currentSecret
        ) else {
            return NaruHelperVideoTransportAuthorizationResult(
                status: .rejected,
                safeFailureCode: .authFailed
            )
        }

        onAuthorizedRequest?()
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

    static func negotiatedCodec(
        request: HelperVideoStartStreamRequestBody,
        hevcEncodeSupported: Bool
    ) -> HelperVideoCodec {
        if request.acceptsHEVC == true, hevcEncodeSupported {
            return .hevc
        }
        return .h264
    }
}

#if os(macOS) && canImport(VideoToolbox)
extension NaruHelperVideoTransportRequestHandler {
    private static func hevcHardwareEncoderIsAvailable() -> Bool {
        let encoderSpecification: CFDictionary = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any,
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: kCFBooleanTrue as Any
        ] as CFDictionary
        var supportedProperties: CFDictionary?
        let status = VTCopySupportedPropertyDictionaryForEncoder(
            width: 64,
            height: 64,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: encoderSpecification,
            encoderIDOut: nil,
            supportedPropertiesOut: &supportedProperties
        )
        return status == noErr && supportedProperties != nil
    }
}
#endif
