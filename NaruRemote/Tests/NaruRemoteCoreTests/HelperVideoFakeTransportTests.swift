import XCTest
@testable import NaruRemoteCore

final class HelperVideoFakeTransportTests: XCTestCase {
    func testFakeHarnessStartsStreamThroughLengthPrefixedMessages() throws {
        let harness = FakeHelperVideoStreamHarness(profileFingerprint: "sha256:test-pairing")

        let descriptor = try harness.startStream()

        XCTAssertEqual(harness.clientMessages, [.startStream])
        XCTAssertEqual(harness.serverMessages, [.startStream])
        XCTAssertEqual(descriptor.codec, .h264)
        XCTAssertEqual(descriptor.latencyMode, .lowLatency)
        XCTAssertTrue(descriptor.supportsFallbackSignal)
    }

    func testFakeHarnessReceivesAccessUnitWithBinaryPayloadOutsideJSON() throws {
        let harness = FakeHelperVideoStreamHarness(profileFingerprint: "sha256:test-pairing")
        let payload = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])

        let accessUnit = try harness.receiveAccessUnit(
            sequence: 7,
            kind: .keyframe,
            payload: payload
        )

        XCTAssertEqual(harness.serverMessages, [.videoAccessUnit])
        XCTAssertEqual(accessUnit.envelope.body.sequence, 7)
        XCTAssertEqual(accessUnit.envelope.body.kind, .keyframe)
        XCTAssertEqual(accessUnit.binaryPayload, payload)
        XCTAssertFalse(harness.lastServerJSONPayload.contains("payload"))
        XCTAssertFalse(harness.lastServerJSONPayload.contains("byteCount"))
        XCTAssertFalse(harness.lastServerJSONPayload.contains("width"))
        XCTAssertFalse(harness.lastServerJSONPayload.contains("height"))
    }

    func testCodecDecodesAccessUnitFromSplitJSONAndBinaryFrames() throws {
        let payload = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
        let envelope = HelperVideoWireEnvelope(
            messageType: .videoAccessUnit,
            profileFingerprint: "sha256:test-pairing",
            body: HelperVideoAccessUnitBody(sequence: 7, kind: .keyframe)
        )
        let frame = try HelperVideoWireCodec.frameAccessUnit(envelope, binaryPayload: payload)
        let jsonLength = try HelperVideoWireCodec.jsonPayloadLength(
            from: Data(frame.prefix(HelperVideoWireCodec.headerByteCount))
        )
        let jsonEnd = HelperVideoWireCodec.headerByteCount + jsonLength
        let binaryHeaderEnd = jsonEnd + HelperVideoWireCodec.headerByteCount

        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoAccessUnitBody>.self,
            fromJSONFrame: frame.subdata(in: 0..<jsonEnd),
            binaryHeader: frame.subdata(in: jsonEnd..<binaryHeaderEnd),
            binaryPayload: frame.subdata(in: binaryHeaderEnd..<frame.count)
        )

        XCTAssertEqual(decoded.envelope.messageType, .videoAccessUnit)
        XCTAssertEqual(decoded.envelope.body.sequence, 7)
        XCTAssertEqual(decoded.envelope.body.kind, .keyframe)
        XCTAssertEqual(decoded.binaryPayload, payload)
    }

    func testFakeHarnessRoutesStallMessageToVNCFallbackHealth() throws {
        let harness = FakeHelperVideoStreamHarness(profileFingerprint: "sha256:test-pairing")

        let health = try harness.receiveStall(reason: .noAccessUnit)

        XCTAssertEqual(harness.serverMessages, [.streamStalled])
        XCTAssertEqual(health.state, .stalled)
        XCTAssertEqual(health.sustainedUpdateBand, .stalled)
        XCTAssertTrue(health.shouldUseVNCVisualFallback)
        XCTAssertFalse(harness.lastServerJSONPayload.contains("payload"))
        XCTAssertFalse(harness.lastServerJSONPayload.contains("endpoint"))
    }

    func testCodecFramesRequestKeyframeWithoutBinaryPayload() throws {
        let pairingSecret = "test-pairing-secret"
        let profileFingerprint = "sha256:test-pairing"
        let requestID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let envelope = HelperVideoWireEnvelope(
            requestID: requestID,
            messageType: .requestKeyframe,
            profileFingerprint: profileFingerprint,
            authProof: HelperVideoAuthProof.make(
                requestID: requestID,
                messageType: .requestKeyframe,
                profileFingerprint: profileFingerprint,
                pairingSecret: pairingSecret
            ),
            body: HelperVideoKeyframeRequestBody(reason: .decoderRecovery)
        )

        let frame = try HelperVideoWireCodec.frame(envelope)
        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoKeyframeRequestBody>.self,
            from: frame
        )

        XCTAssertEqual(decoded.envelope.messageType, .requestKeyframe)
        XCTAssertEqual(decoded.envelope.body.reason, .decoderRecovery)
        XCTAssertNil(decoded.binaryPayload)
        XCTAssertTrue(
            HelperVideoAuthProof.verify(
                decoded.envelope.authProof,
                requestID: envelope.requestID,
                messageType: .requestKeyframe,
                profileFingerprint: profileFingerprint,
                pairingSecret: pairingSecret
            )
        )
    }

    func testFakeHarnessStopsStreamThroughClientMessage() throws {
        let harness = FakeHelperVideoStreamHarness(profileFingerprint: "sha256:test-pairing")

        let stop = try harness.stopStream(reason: .userDisabled)

        XCTAssertEqual(harness.clientMessages, [.stopStream])
        XCTAssertEqual(stop.reason, .userDisabled)
    }

    func testCodecRejectsUnexpectedBinaryPayloadForJSONOnlyMessage() throws {
        let envelope = HelperVideoWireEnvelope(
            messageType: .stopStream,
            body: HelperVideoStopStreamBody(reason: .sessionEnded)
        )
        var frame = try HelperVideoWireCodec.frame(envelope)
        frame.append(Data([0, 0, 0, 0]))

        XCTAssertThrowsError(
            try HelperVideoWireCodec.decodeFrame(
                HelperVideoWireEnvelope<HelperVideoStopStreamBody>.self,
                from: frame
            )
        ) { error in
            XCTAssertEqual(error as? HelperVideoWireCodecError, .unexpectedBinaryPayload)
        }
    }
}

private final class FakeHelperVideoStreamHarness {
    struct AccessUnit: Equatable {
        var envelope: HelperVideoWireEnvelope<HelperVideoAccessUnitBody>
        var binaryPayload: Data
    }

    private let profileFingerprint: String
    private let authProof = "test-auth-proof"
    private(set) var clientMessages: [HelperVideoMessageType] = []
    private(set) var serverMessages: [HelperVideoMessageType] = []
    private(set) var lastServerJSONPayload = ""

    init(profileFingerprint: String) {
        self.profileFingerprint = profileFingerprint
    }

    func startStream() throws -> HelperVideoStreamDescriptor {
        let request = HelperVideoWireEnvelope(
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            authProof: authProof,
            body: HelperVideoStartStreamRequestBody()
        )
        let receivedRequest = try receiveClientMessage(request)
        XCTAssertEqual(receivedRequest.body.codec, .h264)

        let response = HelperVideoWireEnvelope(
            requestID: receivedRequest.requestID,
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            body: HelperVideoStartStreamResponseBody()
        )
        let receivedResponse = try receiveServerMessage(response)
        return receivedResponse.body.streamDescriptor
    }

    func receiveAccessUnit(
        sequence: Int,
        kind: HelperVideoAccessUnitKind,
        payload: Data
    ) throws -> AccessUnit {
        let envelope = HelperVideoWireEnvelope(
            messageType: .videoAccessUnit,
            profileFingerprint: profileFingerprint,
            body: HelperVideoAccessUnitBody(sequence: sequence, kind: kind)
        )
        let frame = try HelperVideoWireCodec.frameAccessUnit(envelope, binaryPayload: payload)
        lastServerJSONPayload = try Self.jsonPayloadString(from: frame)

        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoAccessUnitBody>.self,
            from: frame,
            expectsBinaryPayload: true
        )
        serverMessages.append(decoded.envelope.messageType)

        return AccessUnit(
            envelope: decoded.envelope,
            binaryPayload: decoded.binaryPayload ?? Data()
        )
    }

    func receiveStall(reason: HelperVideoStreamStallReason) throws -> HelperVideoStreamHealth {
        let health = HelperVideoStreamHealth(
            state: .stalled,
            startupBand: .usable,
            sustainedUpdateBand: .stalled,
            decodePressure: .medium,
            fallbackCountBucket: .one
        )
        let envelope = HelperVideoWireEnvelope(
            messageType: .streamStalled,
            profileFingerprint: profileFingerprint,
            body: HelperVideoStreamStallBody(reason: reason, health: health)
        )
        let decoded = try receiveServerMessage(envelope)
        return decoded.body.health
    }

    func stopStream(reason: HelperVideoStopStreamReason) throws -> HelperVideoStopStreamBody {
        let envelope = HelperVideoWireEnvelope(
            messageType: .stopStream,
            profileFingerprint: profileFingerprint,
            authProof: authProof,
            body: HelperVideoStopStreamBody(reason: reason)
        )
        return try receiveClientMessage(envelope).body
    }

    private func receiveClientMessage<Body>(
        _ envelope: HelperVideoWireEnvelope<Body>
    ) throws -> HelperVideoWireEnvelope<Body> {
        let frame = try HelperVideoWireCodec.frame(envelope)
        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<Body>.self,
            from: frame
        )
        clientMessages.append(decoded.envelope.messageType)
        return decoded.envelope
    }

    private func receiveServerMessage<Body>(
        _ envelope: HelperVideoWireEnvelope<Body>
    ) throws -> HelperVideoWireEnvelope<Body> {
        let frame = try HelperVideoWireCodec.frame(envelope)
        lastServerJSONPayload = try Self.jsonPayloadString(from: frame)
        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<Body>.self,
            from: frame
        )
        serverMessages.append(decoded.envelope.messageType)
        return decoded.envelope
    }

    private static func jsonPayloadString(from frame: Data) throws -> String {
        let length = try HelperVideoWireCodec.jsonPayloadLength(
            from: Data(frame.prefix(HelperVideoWireCodec.headerByteCount))
        )
        let start = HelperVideoWireCodec.headerByteCount
        let end = start + length
        return try XCTUnwrap(String(data: frame.subdata(in: start..<end), encoding: .utf8))
    }
}
