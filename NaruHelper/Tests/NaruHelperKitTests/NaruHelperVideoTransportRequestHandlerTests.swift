import XCTest
import NaruHelperKit
import NaruRemoteCore

final class NaruHelperVideoTransportRequestHandlerTests: XCTestCase {
    private let pairingSecret = "test-pairing-secret"
    private let profileFingerprint = "sha256:test-profile"

    func testAuthProofVerifiesOnlyForMatchingMessageProfileAndSecret() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let proof = HelperVideoAuthProof.make(
            requestID: requestID,
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret
        )

        XCTAssertTrue(HelperVideoAuthProof.verify(
            proof,
            requestID: requestID,
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret
        ))
        XCTAssertFalse(HelperVideoAuthProof.verify(
            proof,
            requestID: requestID,
            messageType: .stopStream,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret
        ))
        XCTAssertFalse(HelperVideoAuthProof.verify(
            proof,
            requestID: requestID,
            messageType: .startStream,
            profileFingerprint: "sha256:other-profile",
            pairingSecret: pairingSecret
        ))
        XCTAssertFalse(HelperVideoAuthProof.verify(
            proof,
            requestID: requestID,
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            pairingSecret: "other-secret"
        ))
    }

    func testCapabilityFrameRequiresValidProofAndReturnsSafeCatalogLabels() throws {
        let handler = makeHandler()
        let request = signedEnvelope(
            messageType: .capabilityRequest,
            body: HelperVideoCapabilityRequestBody()
        )

        let responseFrame = try handler.handleCapabilityFrame(try HelperVideoWireCodec.frame(request))
        let response = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoCapabilityResponseBody>.self,
            from: responseFrame
        ).envelope

        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(response.messageType, .capabilityRequest)
        XCTAssertEqual(response.profileFingerprint, profileFingerprint)
        XCTAssertNil(response.authProof)
        XCTAssertEqual(response.body.availability, .available)
        XCTAssertEqual(response.body.screenRecordingPermission, .granted)
        XCTAssertEqual(response.body.codecSupport, .h264)
        XCTAssertEqual(response.body.latencyModes, [.lowLatency, .balanced])
        XCTAssertNil(response.body.safeFailureCode)

        let json = try jsonPayloadString(from: responseFrame)
        assertSafeResponseJSON(json)
    }

    func testStartStreamFrameAcceptsAuthenticatedH264Request() throws {
        let handler = makeHandler()
        let request = signedEnvelope(
            messageType: .startStream,
            body: HelperVideoStartStreamRequestBody(
                codec: .h264,
                latencyMode: .lowLatency,
                qualityBucket: .readability,
                maxFrameRateBucket: .upTo15
            )
        )

        let responseFrame = try handler.handleStartStreamFrame(try HelperVideoWireCodec.frame(request))
        let response = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
            from: responseFrame
        ).envelope

        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(response.messageType, .startStream)
        XCTAssertEqual(response.body.result, .accepted)
        XCTAssertEqual(response.body.streamDescriptor.codec, .h264)
        XCTAssertEqual(response.body.streamDescriptor.codecProfile, .high)
        XCTAssertEqual(response.body.streamDescriptor.frameRateBucket, .upTo15)
        XCTAssertEqual(response.body.streamDescriptor.latencyMode, .lowLatency)
        XCTAssertEqual(response.body.streamDescriptor.qualityBucket, .readability)
        XCTAssertTrue(response.body.streamDescriptor.supportsKeyframeRequest)
        XCTAssertNil(response.body.safeFailureCode)

        let json = try jsonPayloadString(from: responseFrame)
        assertSafeResponseJSON(json)
    }

    func testWrongProofRejectsCapabilityWithoutCallingProvider() throws {
        let recorder = CapabilityProviderRecorder()
        let capability = availableCapability()
        let handler = makeHandler(capabilityProvider: {
            recorder.record()
            return capability
        })
        var request = signedEnvelope(
            messageType: .capabilityRequest,
            body: HelperVideoCapabilityRequestBody()
        )
        request.authProof = "hmac-sha256:invalid"

        let response = handler.handleCapabilityRequest(request)

        XCTAssertEqual(response.body.availability, .failed)
        XCTAssertEqual(response.body.safeFailureCode, .authFailed)
        XCTAssertEqual(recorder.callCount, 0)
    }

    func testRevokedPairingRejectsStartStream() {
        let revocationStore = InMemoryNaruHelperPairingRevocationStore()
        revocationStore.revoke(pairingSecret: pairingSecret)
        let handler = makeHandler(revocationStore: revocationStore)
        let request = signedEnvelope(
            messageType: .startStream,
            body: HelperVideoStartStreamRequestBody()
        )

        let response = handler.handleStartStreamRequest(request)

        XCTAssertEqual(response.body.result, .rejected)
        XCTAssertEqual(response.body.safeFailureCode, .revoked)
    }

    func testWrongProfileFingerprintDoesNotRevealExpectedFingerprintInResponse() {
        let handler = makeHandler()
        var request = signedEnvelope(
            messageType: .capabilityRequest,
            body: HelperVideoCapabilityRequestBody()
        )
        request.profileFingerprint = "sha256:wrong-profile"
        request.authProof = HelperVideoAuthProof.make(
            requestID: request.requestID,
            messageType: request.messageType,
            profileFingerprint: request.profileFingerprint,
            pairingSecret: pairingSecret
        )

        let response = handler.handleCapabilityRequest(request)

        XCTAssertEqual(response.profileFingerprint, "sha256:wrong-profile")
        XCTAssertNotEqual(response.profileFingerprint, profileFingerprint)
        XCTAssertEqual(response.body.safeFailureCode, .authFailed)
    }

    func testMessageTypeMismatchIsRejectedBeforeAuthorization() {
        let handler = makeHandler()
        let request = signedEnvelope(
            messageType: .stopStream,
            body: HelperVideoCapabilityRequestBody()
        )

        let response = handler.handleCapabilityRequest(request)

        XCTAssertEqual(response.messageType, .capabilityRequest)
        XCTAssertEqual(response.body.availability, .failed)
        XCTAssertEqual(response.body.safeFailureCode, .transportFailed)
    }

    func testSchemaVersionMismatchIsRejectedBeforeAuthorization() {
        let handler = makeHandler()
        var request = signedEnvelope(
            messageType: .capabilityRequest,
            body: HelperVideoCapabilityRequestBody()
        )
        request.schemaVersion = naruHelperVideoStreamSchemaVersion + 1

        let response = handler.handleCapabilityRequest(request)

        XCTAssertEqual(response.body.availability, .failed)
        XCTAssertEqual(response.body.safeFailureCode, .transportFailed)
    }

    func testStartStreamAnswersHEVCWhenOfferAndProbeAreTrue() {
        let handler = makeHandler(hevcEncodeSupportProbe: { true })
        let request = signedEnvelope(
            messageType: .startStream,
            body: HelperVideoStartStreamRequestBody(acceptsHEVC: true)
        )

        let response = handler.handleStartStreamRequest(request)

        XCTAssertEqual(response.body.result, .accepted)
        XCTAssertEqual(response.body.streamDescriptor.codec, .hevc)
        XCTAssertEqual(request.body.codec, .h264)
    }

    func testStartStreamStaysH264WhenOldAppOmitsAcceptsHEVCEvenIfProbePasses() {
        let handler = makeHandler(hevcEncodeSupportProbe: { true })
        let request = signedEnvelope(
            messageType: .startStream,
            body: HelperVideoStartStreamRequestBody()
        )

        let response = handler.handleStartStreamRequest(request)

        XCTAssertEqual(response.body.result, .accepted)
        XCTAssertEqual(response.body.streamDescriptor.codec, .h264)
        XCTAssertNil(request.body.acceptsHEVC)
    }

    func testStartStreamStaysH264WhenProbeRejectsHEVCEncode() {
        let handler = makeHandler(hevcEncodeSupportProbe: { false })
        let request = signedEnvelope(
            messageType: .startStream,
            body: HelperVideoStartStreamRequestBody(acceptsHEVC: true)
        )

        let response = handler.handleStartStreamRequest(request)

        XCTAssertEqual(response.body.result, .accepted)
        XCTAssertEqual(response.body.streamDescriptor.codec, .h264)
    }

    func testUnsupportedCodecStartStreamUsesSafeFailureCode() {
        let handler = makeHandler()
        let request = signedEnvelope(
            messageType: .startStream,
            body: HelperVideoStartStreamRequestBody(codec: .unknown)
        )

        let response = handler.handleStartStreamRequest(request)

        XCTAssertEqual(response.body.result, .rejected)
        XCTAssertEqual(response.body.safeFailureCode, .codecUnsupported)
    }

    func testKeyframeAndStopEnvelopesUseSameAuthorizationBoundary() {
        let handler = makeHandler()
        let keyframe = signedEnvelope(
            messageType: .requestKeyframe,
            body: HelperVideoKeyframeRequestBody(reason: .decoderRecovery)
        )
        let stop = signedEnvelope(
            messageType: .stopStream,
            body: HelperVideoStopStreamBody(reason: .userDisabled)
        )

        XCTAssertEqual(handler.authorize(keyframe), .accepted)
        XCTAssertEqual(handler.authorize(stop), .accepted)
    }

    private func makeHandler(
        revocationStore: any NaruHelperPairingRevocationStore = InMemoryNaruHelperPairingRevocationStore(),
        capabilityProvider: @escaping @Sendable () -> HelperVideoCapabilityResponseBody = {
            HelperVideoCapabilityResponseBody(
                availability: .available,
                screenRecordingPermission: .granted,
                codecSupport: .h264,
                latencyModes: [.lowLatency, .balanced]
            )
        },
        hevcEncodeSupportProbe: @escaping @Sendable () -> Bool = { false }
    ) -> NaruHelperVideoTransportRequestHandler {
        NaruHelperVideoTransportRequestHandler(
            expectedPairingSecret: pairingSecret,
            expectedProfileFingerprint: profileFingerprint,
            revocationStore: revocationStore,
            capabilityProvider: capabilityProvider,
            hevcEncodeSupportProbe: hevcEncodeSupportProbe
        )
    }

    private func signedEnvelope<Body: Codable & Equatable & Sendable>(
        messageType: HelperVideoMessageType,
        body: Body
    ) -> HelperVideoWireEnvelope<Body> {
        NaruHelperVideoTransportRequestHandler.signedEnvelope(
            messageType: messageType,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            body: body
        )
    }

    private func availableCapability() -> HelperVideoCapabilityResponseBody {
        HelperVideoCapabilityResponseBody(
            availability: .available,
            screenRecordingPermission: .granted,
            codecSupport: .h264,
            latencyModes: [.lowLatency, .balanced]
        )
    }

    private func jsonPayloadString(from frame: Data) throws -> String {
        let length = try HelperVideoWireCodec.jsonPayloadLength(
            from: Data(frame.prefix(HelperVideoWireCodec.headerByteCount))
        )
        let start = HelperVideoWireCodec.headerByteCount
        let end = start + length
        return try XCTUnwrap(String(data: frame.subdata(in: start..<end), encoding: .utf8))
    }

    private func assertSafeResponseJSON(
        _ json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lowercased = json.lowercased()
        for forbidden in [
            pairingSecret.lowercased(),
            "authproof",
            "payload",
            "endpoint",
            "hostname",
            "host:",
            "displayid",
            "displayname",
            "bytecount",
            "width",
            "height"
        ] {
            XCTAssertFalse(
                lowercased.contains(forbidden),
                "Unexpected unsafe response term \(forbidden) in \(json)",
                file: file,
                line: line
            )
        }
    }
}

private final class CapabilityProviderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var callCount: Int {
        lock.withLock { count }
    }

    func record() {
        lock.withLock {
            count += 1
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
