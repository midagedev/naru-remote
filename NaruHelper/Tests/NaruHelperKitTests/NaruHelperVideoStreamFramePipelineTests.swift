import XCTest
import NaruHelperKit
import NaruRemoteCore

final class NaruHelperVideoStreamFramePipelineTests: XCTestCase {
    private let pairingSecret = "test-pairing-secret"
    private let profileFingerprint = "sha256:test-profile"

    func testAuthenticatedStartStreamEmitsResponseAndAccessUnitFrames() throws {
        let request = signedEnvelope(
            body: HelperVideoStartStreamRequestBody(maxFrameRateBucket: .upTo15)
        )
        let parameterSetPayload = Data([0x00, 0x00, 0x00, 0x01, 0x67])
        let keyframePayload = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
        let pipeline = makePipeline(accessUnits: [
            NaruHelperVideoAccessUnit(
                sequence: 0,
                kind: .parameterSet,
                binaryPayload: parameterSetPayload
            ),
            NaruHelperVideoAccessUnit(
                sequence: 1,
                kind: .keyframe,
                binaryPayload: keyframePayload
            )
        ])

        let frames = try pipeline.frames(
            forStartStreamFrame: try HelperVideoWireCodec.frame(request)
        )

        XCTAssertEqual(frames.count, 3)
        let response = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
            from: frames[0]
        ).envelope
        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(response.messageType, .startStream)
        XCTAssertEqual(response.profileFingerprint, profileFingerprint)
        XCTAssertNil(response.authProof)
        XCTAssertEqual(response.body.result, .accepted)
        XCTAssertEqual(response.body.streamDescriptor.frameRateBucket, .upTo15)

        let parameterSet = try decodeAccessUnit(from: frames[1])
        XCTAssertEqual(parameterSet.envelope.requestID, request.requestID)
        XCTAssertEqual(parameterSet.envelope.profileFingerprint, profileFingerprint)
        XCTAssertNil(parameterSet.envelope.authProof)
        XCTAssertEqual(parameterSet.envelope.body.sequence, 0)
        XCTAssertEqual(parameterSet.envelope.body.kind, .parameterSet)
        XCTAssertEqual(parameterSet.binaryPayload, parameterSetPayload)

        let keyframe = try decodeAccessUnit(from: frames[2])
        XCTAssertEqual(keyframe.envelope.body.sequence, 1)
        XCTAssertEqual(keyframe.envelope.body.kind, .keyframe)
        XCTAssertEqual(keyframe.binaryPayload, keyframePayload)

        try assertSafeJSONPayload(in: frames[0])
        try assertSafeJSONPayload(in: frames[1])
        try assertSafeJSONPayload(in: frames[2])
    }

    func testRejectedStartStreamDoesNotCallAccessUnitSource() throws {
        var request = signedEnvelope(body: HelperVideoStartStreamRequestBody())
        request.authProof = "hmac-sha256:invalid"
        let source = RecordingAccessUnitSource(accessUnits: [
            NaruHelperVideoAccessUnit(
                sequence: 0,
                kind: .keyframe,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
            )
        ])
        let pipeline = makePipeline(accessUnitSource: source)

        let frames = try pipeline.frames(
            forStartStreamFrame: try HelperVideoWireCodec.frame(request)
        )

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(source.callCount, 0)
        XCTAssertEqual(source.streamCallCount, 0)
        let response = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
            from: frames[0]
        ).envelope
        XCTAssertEqual(response.body.result, .rejected)
        XCTAssertEqual(response.body.safeFailureCode, .authFailed)
        try assertSafeJSONPayload(in: frames[0])
    }

    func testOpenFrameStreamDefersAccessUnitSourceUntilStreamStarts() throws {
        let request = signedEnvelope(body: HelperVideoStartStreamRequestBody())
        let source = RecordingAccessUnitSource(accessUnits: [
            NaruHelperVideoAccessUnit(
                sequence: 0,
                kind: .keyframe,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
            )
        ])
        let pipeline = makePipeline(accessUnitSource: source)

        let openedStream = try pipeline.openFrameStream(
            forStartStreamFrame: try HelperVideoWireCodec.frame(request)
        )

        XCTAssertTrue(openedStream.isAccepted)
        XCTAssertEqual(source.callCount, 0)
        XCTAssertEqual(source.streamCallCount, 0)
        let response = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
            from: openedStream.responseFrame
        ).envelope
        XCTAssertEqual(response.body.result, .accepted)
        XCTAssertEqual(response.requestID, request.requestID)

        _ = try openedStream.makeAccessUnitStream()

        XCTAssertEqual(source.callCount, 0)
        XCTAssertEqual(source.streamCallCount, 1)
    }

    func testOpenRejectedFrameStreamNeverStartsAccessUnitSource() throws {
        var request = signedEnvelope(body: HelperVideoStartStreamRequestBody())
        request.authProof = "hmac-sha256:invalid"
        let source = RecordingAccessUnitSource(accessUnits: [
            NaruHelperVideoAccessUnit(
                sequence: 0,
                kind: .keyframe,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
            )
        ])
        let pipeline = makePipeline(accessUnitSource: source)

        let openedStream = try pipeline.openFrameStream(
            forStartStreamFrame: try HelperVideoWireCodec.frame(request)
        )

        XCTAssertFalse(openedStream.isAccepted)
        XCTAssertEqual(source.callCount, 0)
        XCTAssertEqual(source.streamCallCount, 0)
        let response = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
            from: openedStream.responseFrame
        ).envelope
        XCTAssertEqual(response.body.result, .rejected)
        XCTAssertEqual(response.body.safeFailureCode, .authFailed)
    }

    func testAcceptedStartWithNoAccessUnitsEmitsSafeStallFrame() throws {
        let request = signedEnvelope(body: HelperVideoStartStreamRequestBody())
        let pipeline = makePipeline(accessUnits: [])

        let frames = try pipeline.frames(
            forStartStreamFrame: try HelperVideoWireCodec.frame(request)
        )

        XCTAssertEqual(frames.count, 2)
        let response = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
            from: frames[0]
        ).envelope
        XCTAssertEqual(response.body.result, .accepted)

        let stall = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStreamStallBody>.self,
            from: frames[1]
        ).envelope
        XCTAssertEqual(stall.requestID, request.requestID)
        XCTAssertEqual(stall.messageType, .streamStalled)
        XCTAssertEqual(stall.body.reason, .noAccessUnit)
        XCTAssertEqual(stall.body.health.state, .stalled)
        XCTAssertTrue(stall.body.health.shouldUseVNCVisualFallback)
        XCTAssertNil(stall.authProof)
        try assertSafeJSONPayload(in: frames[1])
    }

    func testFrameStreamEmitsSafeStallWhenScreenCaptureFailsBeforeFirstAccessUnit() async throws {
        let request = signedEnvelope(body: HelperVideoStartStreamRequestBody())
        let pipeline = makePipeline(
            accessUnitSource: FailingStreamAccessUnitSource(
                error: NaruHelperVideoScreenCaptureKitAccessUnitSourceError.captureTimedOut
            )
        )

        let frames = try await collectFrames(
            from: try pipeline.frameStream(
                forStartStreamFrame: try HelperVideoWireCodec.frame(request)
            )
        )

        XCTAssertEqual(frames.count, 2)
        let response = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
            from: frames[0]
        ).envelope
        XCTAssertEqual(response.body.result, .accepted)

        let stall = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStreamStallBody>.self,
            from: frames[1]
        ).envelope
        XCTAssertEqual(stall.body.reason, .screenCaptureTimedOut)
        XCTAssertEqual(stall.body.health.state, .stalled)
        XCTAssertTrue(stall.body.health.shouldUseVNCVisualFallback)
        try assertSafeJSONPayload(in: frames[1])
    }

    func testFrameStreamEmitsSafeStallWithScreenCaptureCallbackStageReason() async throws {
        let cases: [
            (
                error: NaruHelperVideoScreenCaptureKitAccessUnitSourceError,
                reason: HelperVideoStreamStallReason
            )
        ] = [
            (.captureNoOutputCallbacks, .screenCaptureNoOutputCallbacks),
            (.captureNonScreenOutputCallbacks, .screenCaptureNonScreenCallbacks),
            (.captureNonDisplayableScreenFrames, .screenCaptureNonDisplayableFrames),
            (.capturedFrameMissingImageBuffer, .screenCaptureMissingImageBuffer),
            (.captureInsufficientDisplayableFrames, .screenCaptureInsufficientDisplayableFrames)
        ]

        for testCase in cases {
            let request = signedEnvelope(body: HelperVideoStartStreamRequestBody())
            let pipeline = makePipeline(
                accessUnitSource: FailingStreamAccessUnitSource(error: testCase.error)
            )

            let frames = try await collectFrames(
                from: try pipeline.frameStream(
                    forStartStreamFrame: try HelperVideoWireCodec.frame(request)
                )
            )

            XCTAssertEqual(frames.count, 2)
            let stall = try HelperVideoWireCodec.decodeFrame(
                HelperVideoWireEnvelope<HelperVideoStreamStallBody>.self,
                from: frames[1]
            ).envelope
            XCTAssertEqual(stall.body.reason, testCase.reason)
            XCTAssertEqual(stall.body.health.state, .stalled)
            XCTAssertTrue(stall.body.health.shouldUseVNCVisualFallback)
            try assertSafeJSONPayload(in: frames[1])
        }
    }

    func testFrameStreamEmitsSafeStallWhenScreenCaptureFailureHappensBeforeFirstAccessUnit() async throws {
        let request = signedEnvelope(body: HelperVideoStartStreamRequestBody())
        let pipeline = makePipeline(
            accessUnitSource: FailingStreamAccessUnitSource(
                error: NaruHelperVideoScreenCaptureKitAccessUnitSourceError.captureFailed
            )
        )

        let frames = try await collectFrames(
            from: try pipeline.frameStream(
                forStartStreamFrame: try HelperVideoWireCodec.frame(request)
            )
        )

        XCTAssertEqual(frames.count, 2)
        let stall = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStreamStallBody>.self,
            from: frames[1]
        ).envelope
        XCTAssertEqual(stall.body.reason, .screenCaptureFailed)
        XCTAssertEqual(stall.body.health.state, .stalled)
        XCTAssertTrue(stall.body.health.shouldUseVNCVisualFallback)
        try assertSafeJSONPayload(in: frames[1])
    }

    func testFrameStreamPropagatesSourceFailureAfterAccessUnitEmission() async throws {
        let request = signedEnvelope(body: HelperVideoStartStreamRequestBody())
        let accessUnit = NaruHelperVideoAccessUnit(
            sequence: 0,
            kind: .keyframe,
            binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
        )
        let pipeline = makePipeline(
            accessUnitSource: FailingStreamAccessUnitSource(
                accessUnitsBeforeFailure: [accessUnit],
                error: NaruHelperVideoScreenCaptureKitAccessUnitSourceError.captureFailed
            )
        )
        var frames: [Data] = []

        do {
            let stream = try pipeline.frameStream(
                forStartStreamFrame: try HelperVideoWireCodec.frame(request)
            )
            for try await frame in stream {
                frames.append(frame)
            }
            XCTFail("Expected the post-access-unit source failure to propagate.")
        } catch {
            XCTAssertEqual(
                error as? NaruHelperVideoScreenCaptureKitAccessUnitSourceError,
                .captureFailed
            )
        }

        XCTAssertEqual(frames.count, 2)
        let emitted = try decodeAccessUnit(from: frames[1])
        XCTAssertEqual(emitted.envelope.body.sequence, accessUnit.sequence)
        XCTAssertEqual(emitted.envelope.body.kind, accessUnit.kind)
    }

    func testOversizedAccessUnitPayloadIsRejectedBeforeFrameEmission() throws {
        let request = signedEnvelope(body: HelperVideoStartStreamRequestBody())
        let pipeline = makePipeline(accessUnits: [
            NaruHelperVideoAccessUnit(
                sequence: 0,
                kind: .keyframe,
                binaryPayload: Data(
                    count: HelperVideoWireCodec.maximumBinaryPayloadByteCount + 1
                )
            )
        ])

        XCTAssertThrowsError(
            try pipeline.frames(forStartStreamFrame: try HelperVideoWireCodec.frame(request))
        ) { error in
            XCTAssertEqual(error as? HelperVideoWireCodecError, .oversizedBinaryPayload)
        }
    }

    private func makePipeline(
        accessUnits: [NaruHelperVideoAccessUnit]
    ) -> NaruHelperVideoStreamFramePipeline {
        makePipeline(
            accessUnitSource: NaruHelperVideoStaticAccessUnitSource(accessUnits: accessUnits)
        )
    }

    private func makePipeline(
        accessUnitSource: any NaruHelperVideoAccessUnitSource
    ) -> NaruHelperVideoStreamFramePipeline {
        NaruHelperVideoStreamFramePipeline(
            requestHandler: NaruHelperVideoTransportRequestHandler(
                expectedPairingSecret: pairingSecret,
                expectedProfileFingerprint: profileFingerprint,
                capabilityProvider: {
                    HelperVideoCapabilityResponseBody(
                        availability: .available,
                        screenRecordingPermission: .granted,
                        codecSupport: .h264,
                        latencyModes: [.lowLatency, .balanced]
                    )
                }
            ),
            accessUnitSource: accessUnitSource
        )
    }

    private func signedEnvelope(
        body: HelperVideoStartStreamRequestBody
    ) -> HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody> {
        NaruHelperVideoTransportRequestHandler.signedEnvelope(
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            body: body
        )
    }

    private func decodeAccessUnit(
        from frame: Data
    ) throws -> HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>> {
        try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoAccessUnitBody>.self,
            from: frame,
            expectsBinaryPayload: true
        )
    }

    private func collectFrames(
        from stream: AsyncThrowingStream<Data, any Error>
    ) async throws -> [Data] {
        var frames: [Data] = []
        for try await frame in stream {
            frames.append(frame)
        }
        return frames
    }

    private func assertSafeJSONPayload(
        in frame: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let json = try jsonPayloadString(from: frame)
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

    private func jsonPayloadString(from frame: Data) throws -> String {
        let length = try HelperVideoWireCodec.jsonPayloadLength(
            from: Data(frame.prefix(HelperVideoWireCodec.headerByteCount))
        )
        let start = HelperVideoWireCodec.headerByteCount
        let end = start + length
        return try XCTUnwrap(String(data: frame.subdata(in: start..<end), encoding: .utf8))
    }
}

private final class RecordingAccessUnitSource: NaruHelperVideoAccessUnitSource, @unchecked Sendable {
    private let lock = NSLock()
    private let accessUnits: [NaruHelperVideoAccessUnit]
    private var count = 0
    private var streamCount = 0

    var callCount: Int {
        lock.withLock { count }
    }

    var streamCallCount: Int {
        lock.withLock { streamCount }
    }

    init(accessUnits: [NaruHelperVideoAccessUnit]) {
        self.accessUnits = accessUnits
    }

    func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        lock.withLock {
            count += 1
        }
        return accessUnits
    }

    func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        lock.withLock {
            streamCount += 1
        }
        let accessUnits = accessUnits
        return AsyncThrowingStream { continuation in
            for accessUnit in accessUnits {
                continuation.yield(accessUnit)
            }
            continuation.finish()
        }
    }
}

private final class FailingStreamAccessUnitSource:
    NaruHelperVideoAccessUnitSource,
    @unchecked Sendable
{
    private let accessUnitsBeforeFailure: [NaruHelperVideoAccessUnit]
    private let error: any Error

    init(
        accessUnitsBeforeFailure: [NaruHelperVideoAccessUnit] = [],
        error: any Error
    ) {
        self.accessUnitsBeforeFailure = accessUnitsBeforeFailure
        self.error = error
    }

    func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        accessUnitsBeforeFailure
    }

    func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        let accessUnitsBeforeFailure = accessUnitsBeforeFailure
        let error = error
        return AsyncThrowingStream { continuation in
            for accessUnit in accessUnitsBeforeFailure {
                continuation.yield(accessUnit)
            }
            continuation.finish(throwing: error)
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
