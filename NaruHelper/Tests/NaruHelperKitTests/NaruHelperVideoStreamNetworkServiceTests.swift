import XCTest
import NaruHelperKit
import NaruRemoteCore

#if canImport(Network)
final class NaruHelperVideoStreamNetworkServiceTests: XCTestCase {
    private let pairingSecret = "test-pairing-secret"
    private let profileFingerprint = "sha256:test-profile"

    func testNetworkClientRejectsUnprotectedTransportBeforeConnecting() async throws {
        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: 1,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .unprotected,
            timeout: 0.1
        )

        do {
            _ = try await client.startStream()
            XCTFail("Expected unprotected helper-video frame transport to be rejected.")
        } catch {
            XCTAssertEqual(
                error as? HelperVideoStreamNetworkClientError,
                .transportProtectionRequired
            )
        }
    }

    func testNetworkEventStreamRejectsUnprotectedTransportBeforeConnecting() async throws {
        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: 1,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .unprotected,
            timeout: 0.1
        )

        var iterator = client.streamEvents().makeAsyncIterator()
        do {
            _ = try await iterator.next()
            XCTFail("Expected unprotected helper-video frame transport to be rejected.")
        } catch {
            XCTAssertEqual(
                error as? HelperVideoStreamNetworkClientError,
                .transportProtectionRequired
            )
        }
    }

    func testNetworkServerRejectsUnprotectedTransportBeforeListening() throws {
        let pipeline = makePipeline(
            source: NaruHelperVideoStaticAccessUnitSource(accessUnits: [])
        )

        XCTAssertThrowsError(
            try NaruHelperVideoStreamNetworkServer(
                pipeline: pipeline,
                transportProtection: .unprotected
            )
        ) { error in
            XCTAssertEqual(
                error as? HelperVideoStreamNetworkServerError,
                .transportProtectionRequired
            )
        }
    }

    func testNetworkClientReceivesStartResponseAndAccessUnitsFromHelperServer() async throws {
        let parameterSetPayload = Data([0x00, 0x00, 0x00, 0x01, 0x67])
        let keyframePayload = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
        let server = try makeServer(accessUnits: [
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
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 3
        )
        let result = try await client.startStream(maxServerFrames: 3)

        XCTAssertEqual(result.startResponse.body.result, .accepted)
        XCTAssertEqual(result.startResponse.body.streamDescriptor.codec, .h264)
        XCTAssertNil(result.startResponse.authProof)
        XCTAssertNil(result.stall)
        XCTAssertEqual(result.accessUnits.count, 2)
        XCTAssertEqual(result.accessUnits[0].envelope.body.sequence, 0)
        XCTAssertEqual(result.accessUnits[0].envelope.body.kind, .parameterSet)
        XCTAssertEqual(result.accessUnits[0].binaryPayload, parameterSetPayload)
        XCTAssertEqual(result.accessUnits[1].envelope.body.sequence, 1)
        XCTAssertEqual(result.accessUnits[1].envelope.body.kind, .keyframe)
        XCTAssertEqual(result.accessUnits[1].binaryPayload, keyframePayload)
    }

    func testNetworkClientStreamsStartResponseAndAccessUnitsFromHelperServer() async throws {
        let parameterSetPayload = Data([0x00, 0x00, 0x00, 0x01, 0x67])
        let keyframePayload = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
        let server = try makeServer(source: AsyncOnlyAccessUnitSource(accessUnits: [
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
        ]))
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 3
        )
        var events: [HelperVideoStreamNetworkEvent] = []
        for try await event in client.streamEvents() {
            events.append(event)
        }

        XCTAssertEqual(events.count, 3)
        guard case .startResponse(let response) = events[0] else {
            XCTFail("Expected start response event.")
            return
        }
        guard case .accessUnit(let parameterSet) = events[1] else {
            XCTFail("Expected parameter set access unit event.")
            return
        }
        guard case .accessUnit(let keyframe) = events[2] else {
            XCTFail("Expected keyframe access unit event.")
            return
        }

        XCTAssertEqual(response.body.result, .accepted)
        XCTAssertEqual(parameterSet.envelope.body.sequence, 0)
        XCTAssertEqual(parameterSet.binaryPayload, parameterSetPayload)
        XCTAssertEqual(keyframe.envelope.body.sequence, 1)
        XCTAssertEqual(keyframe.binaryPayload, keyframePayload)
    }

    func testNetworkClientStreamTimeoutIsIdleTimeoutAcrossSustainedEvents() async throws {
        let accessUnits = (0..<4).map { index in
            NaruHelperVideoAccessUnit(
                sequence: index,
                kind: index == 0 ? .parameterSet : .delta,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, UInt8(0x60 + index)])
            )
        }
        let server = try makeServer(source: AsyncOnlyAccessUnitSource(
            accessUnits: accessUnits,
            perAccessUnitDelay: .milliseconds(180)
        ))
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 0.35
        )
        var events: [HelperVideoStreamNetworkEvent] = []
        for try await event in client.streamEvents() {
            events.append(event)
        }

        XCTAssertEqual(events.count, accessUnits.count + 1)
        XCTAssertTrue({
            if case .startResponse = events[0] {
                return true
            }
            return false
        }())
        XCTAssertEqual(events.dropFirst().compactMap { event -> Int? in
            if case .accessUnit(let accessUnit) = event {
                return accessUnit.envelope.body.sequence
            }
            return nil
        }, Array(0..<accessUnits.count))
    }

    func testNetworkClientPreservesSyncFramesAndCoalescesDeltasWhenConsumerFallsBehind() async throws {
        let accessUnits = [
            NaruHelperVideoAccessUnit(
                sequence: 0,
                kind: .parameterSet,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x67])
            ),
            NaruHelperVideoAccessUnit(
                sequence: 1,
                kind: .keyframe,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
            )
        ] + (2..<20).map { sequence in
            NaruHelperVideoAccessUnit(
                sequence: sequence,
                kind: .delta,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, UInt8(sequence)])
            )
        }
        let server = try makeServer(source: AsyncOnlyAccessUnitSource(
            accessUnits: accessUnits,
            perAccessUnitDelay: .nanoseconds(0)
        ))
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 3
        )
        var iterator = client.streamEvents().makeAsyncIterator()

        guard case .startResponse = try await iterator.next() else {
            XCTFail("Expected the start response before access units.")
            return
        }

        try await Task.sleep(for: .milliseconds(700))

        var accessUnitsReceived: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>] = []
        while let event = try await iterator.next() {
            if case .accessUnit(let accessUnit) = event {
                accessUnitsReceived.append(accessUnit)
            }
        }

        XCTAssertEqual(
            accessUnitsReceived.prefix(2).map { $0.envelope.body.kind },
            [.parameterSet, .keyframe]
        )
        XCTAssertEqual(accessUnitsReceived.prefix(2).map { $0.envelope.body.sequence }, [0, 1])
        XCTAssertEqual(accessUnitsReceived.last?.envelope.body.kind, .delta)
        XCTAssertEqual(accessUnitsReceived.last?.envelope.body.sequence, 19)
        XCTAssertLessThan(
            accessUnitsReceived.count,
            accessUnits.count,
            "Slow consumers should receive the latest visual delta instead of a stale full backlog."
        )
    }

    func testNetworkClientCoalescesRepeatedSyncFramesWhenConsumerFallsBehind() async throws {
        let accessUnits = (0..<24).map { sequence in
            NaruHelperVideoAccessUnit(
                sequence: sequence,
                kind: sequence.isMultiple(of: 2) ? .parameterSet : .keyframe,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, UInt8(0x40 + sequence)])
            )
        }
        let server = try makeServer(source: AsyncOnlyAccessUnitSource(
            accessUnits: accessUnits,
            perAccessUnitDelay: .nanoseconds(0)
        ))
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 3
        )
        var iterator = client.streamEvents().makeAsyncIterator()

        guard case .startResponse = try await iterator.next() else {
            XCTFail("Expected the start response before access units.")
            return
        }

        try await Task.sleep(for: .milliseconds(900))

        var accessUnitsReceived: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>] = []
        while let event = try await iterator.next() {
            if case .accessUnit(let accessUnit) = event {
                accessUnitsReceived.append(accessUnit)
            }
        }

        XCTAssertLessThanOrEqual(
            accessUnitsReceived.count,
            2,
            "Slow consumers should not retain an unbounded sync-frame backlog."
        )
        XCTAssertEqual(accessUnitsReceived.map { $0.envelope.body.sequence }, [22, 23])
        XCTAssertEqual(accessUnitsReceived.map { $0.envelope.body.kind }, [.parameterSet, .keyframe])
    }

    func testNetworkClientCanReturnPartialStartResultOnIdleTimeoutForBenchmarks() async throws {
        let accessUnits = [
            NaruHelperVideoAccessUnit(
                sequence: 0,
                kind: .parameterSet,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x67])
            ),
            NaruHelperVideoAccessUnit(
                sequence: 1,
                kind: .keyframe,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
            )
        ]
        let server = try makeServer(source: HangingAccessUnitSource(accessUnits: accessUnits))
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let strictClient = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 0.2
        )
        do {
            _ = try await strictClient.startStream(maxServerFrames: 6)
            XCTFail("Expected strict startStream to time out.")
        } catch {
            XCTAssertEqual(error as? HelperVideoStreamNetworkClientError, .timedOut)
        }

        let partialClient = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 0.2
        )
        let partial = try await partialClient.startStream(
            maxServerFrames: 6,
            allowsPartialResultOnTimeout: true
        )

        XCTAssertEqual(partial.startResponse.body.result, .accepted)
        XCTAssertEqual(partial.accessUnits.map { $0.envelope.body.sequence }, [0, 1])
        XCTAssertNil(partial.stall)
    }

    func testNetworkClientReceivesSafeStallWhenHelperHasNoAccessUnits() async throws {
        let server = try makeServer(accessUnits: [])
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 3
        )
        let result = try await client.startStream(maxServerFrames: 2)

        XCTAssertEqual(result.startResponse.body.result, .accepted)
        XCTAssertTrue(result.accessUnits.isEmpty)
        XCTAssertEqual(result.stall?.body.reason, .noAccessUnit)
        XCTAssertEqual(result.stall?.body.health.state, .stalled)
        XCTAssertEqual(result.stall?.body.health.shouldUseVNCVisualFallback, true)
        XCTAssertNil(result.stall?.authProof)
    }

    func testNetworkClientReceivesSafeStallWhenScreenCaptureTimesOutBeforeFrames() async throws {
        let server = try makeServer(source: FailingAccessUnitSource(
            error: NaruHelperVideoScreenCaptureKitAccessUnitSourceError.captureTimedOut
        ))
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 3
        )
        let result = try await client.startStream(maxServerFrames: 2)

        XCTAssertEqual(result.startResponse.body.result, .accepted)
        XCTAssertTrue(result.accessUnits.isEmpty)
        XCTAssertEqual(result.stall?.body.reason, .screenCaptureTimedOut)
        XCTAssertEqual(result.stall?.body.health.state, .stalled)
        XCTAssertEqual(result.stall?.body.health.shouldUseVNCVisualFallback, true)
        XCTAssertNil(result.stall?.authProof)
    }

    func testNetworkEventStreamReceivesBackpressureStallAfterAccessUnit() async throws {
        let accessUnit = NaruHelperVideoAccessUnit(
            sequence: 0,
            kind: .keyframe,
            binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
        )
        let server = try makeServer(
            source: BackpressuredAccessUnitSource(accessUnitsBeforeFailure: [accessUnit])
        )
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 3
        )
        var events: [HelperVideoStreamNetworkEvent] = []
        for try await event in client.streamEvents() {
            events.append(event)
        }

        XCTAssertEqual(events.count, 3)
        guard case .startResponse(let response) = events[0],
              case .accessUnit(let received) = events[1],
              case .stall(let stall) = events[2]
        else {
            XCTFail("Expected start, access unit, then transport-backpressure stall.")
            return
        }
        XCTAssertEqual(response.body.result, .accepted)
        XCTAssertEqual(received.envelope.body.sequence, accessUnit.sequence)
        XCTAssertEqual(received.envelope.body.kind, accessUnit.kind)
        XCTAssertEqual(stall.body.reason, .transportBackpressure)
        XCTAssertEqual(stall.body.health.state, .stalled)
        XCTAssertTrue(stall.body.health.shouldUseVNCVisualFallback)
    }

    func testAuthenticatedKeyframeRequestMidStreamLatchesOpenedStreamSignal() async throws {
        let source = SignalGatedAccessUnitSource()
        let server = try makeServer(source: source)
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: 3
        )
        let events = client.streamEvents()
        var iterator = events.makeAsyncIterator()

        guard case .startResponse(let response) = try await iterator.next() else {
            XCTFail("Expected start response before access units.")
            return
        }
        XCTAssertEqual(response.body.result, .accepted)
        XCTAssertTrue(response.body.streamDescriptor.supportsKeyframeRequest)

        guard case .accessUnit(let first) = try await iterator.next() else {
            XCTFail("Expected the first access unit before the keyframe request.")
            return
        }
        XCTAssertEqual(first.envelope.body.kind, .keyframe)

        let requestKeyframe = try XCTUnwrap(events.requestKeyframe)
        requestKeyframe(.decoderRecovery)

        guard case .accessUnit(let recovered) = try await iterator.next() else {
            XCTFail("Expected a forced keyframe after the authenticated request.")
            return
        }
        XCTAssertEqual(recovered.envelope.body.kind, .keyframe)
        XCTAssertEqual(recovered.envelope.body.sequence, 1)
    }

    func testWrongPairingSecretReceivesRejectedStartWithoutAccessUnits() async throws {
        let server = try makeServer(accessUnits: [
            NaruHelperVideoAccessUnit(
                sequence: 0,
                kind: .keyframe,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
            )
        ])
        server.start()
        defer { server.cancel() }
        let port = try await waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: "wrong-secret",
            transportProtection: .authenticatedPrivateProfile,
            timeout: 3
        )
        let result = try await client.startStream(maxServerFrames: 2)

        XCTAssertEqual(result.startResponse.body.result, .rejected)
        XCTAssertEqual(result.startResponse.body.safeFailureCode, .authFailed)
        XCTAssertTrue(result.accessUnits.isEmpty)
        XCTAssertNil(result.stall)
    }

    private func makeServer(
        accessUnits: [NaruHelperVideoAccessUnit]
    ) throws -> NaruHelperVideoStreamNetworkServer {
        try makeServer(source: NaruHelperVideoStaticAccessUnitSource(accessUnits: accessUnits))
    }

    private func makeServer(
        source: any NaruHelperVideoAccessUnitSource
    ) throws -> NaruHelperVideoStreamNetworkServer {
        try NaruHelperVideoStreamNetworkServer(
            pipeline: makePipeline(source: source),
            transportProtection: .authenticatedPrivateProfile
        )
    }

    private func makePipeline(
        source: any NaruHelperVideoAccessUnitSource
    ) -> NaruHelperVideoStreamFramePipeline {
        let requestHandler = NaruHelperVideoTransportRequestHandler(
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
        )
        return NaruHelperVideoStreamFramePipeline(
            requestHandler: requestHandler,
            accessUnitSource: source
        )
    }

    private func waitForPort(
        _ server: NaruHelperVideoStreamNetworkServer
    ) async throws -> UInt16 {
        for _ in 0..<50 {
            if let port = server.port, port > 0 {
                return port
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try XCTUnwrap(server.port)
    }
}

private struct AsyncOnlyAccessUnitSource: NaruHelperVideoAccessUnitSource {
    var accessUnits: [NaruHelperVideoAccessUnit]
    var perAccessUnitDelay: Duration = .milliseconds(10)

    func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        throw AsyncOnlyAccessUnitSourceError.finiteBatchPathUsed
    }

    func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        AsyncThrowingStream { continuation in
            let accessUnits = accessUnits
            let perAccessUnitDelay = perAccessUnitDelay
            Task {
                for accessUnit in accessUnits {
                    continuation.yield(accessUnit)
                    try? await Task.sleep(for: perAccessUnitDelay)
                }
                continuation.finish()
            }
        }
    }
}

private enum AsyncOnlyAccessUnitSourceError: Error {
    case finiteBatchPathUsed
}

private struct FailingAccessUnitSource: NaruHelperVideoAccessUnitSource {
    var error: NaruHelperVideoScreenCaptureKitAccessUnitSourceError

    func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        throw error
    }

    func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        throw error
    }
}

private struct BackpressuredAccessUnitSource: NaruHelperVideoAccessUnitSource {
    var accessUnitsBeforeFailure: [NaruHelperVideoAccessUnit]

    func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        accessUnitsBeforeFailure
    }

    func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        let accessUnitsBeforeFailure = accessUnitsBeforeFailure
        return AsyncThrowingStream { continuation in
            for accessUnit in accessUnitsBeforeFailure {
                continuation.yield(accessUnit)
            }
            continuation.finish(
                throwing: NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                    .encodedAccessUnitBackpressureExceeded
            )
        }
    }
}

private struct SignalGatedAccessUnitSource: NaruHelperVideoAccessUnitSource {
    var waitNanoseconds: UInt64 = 2_000_000_000

    func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        throw AsyncOnlyAccessUnitSourceError.finiteBatchPathUsed
    }

    func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody,
        keyframeSignal: NaruHelperVideoKeyframeRequestSignal
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        let waitNanoseconds = waitNanoseconds
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(
                    NaruHelperVideoAccessUnit(
                        sequence: 0,
                        kind: .keyframe,
                        binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
                    )
                )
                let stepNanoseconds: UInt64 = 20_000_000
                let steps = max(waitNanoseconds / stepNanoseconds, 1)
                for _ in 0..<steps {
                    if keyframeSignal.consumePending() {
                        continuation.yield(
                            NaruHelperVideoAccessUnit(
                                sequence: 1,
                                kind: .keyframe,
                                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
                            )
                        )
                        continuation.finish()
                        return
                    }
                    try? await Task.sleep(nanoseconds: stepNanoseconds)
                }
                continuation.yield(
                    NaruHelperVideoAccessUnit(
                        sequence: 1,
                        kind: .delta,
                        binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x61])
                    )
                )
                continuation.finish()
            }
        }
    }
}

private struct HangingAccessUnitSource: NaruHelperVideoAccessUnitSource {
    var accessUnits: [NaruHelperVideoAccessUnit]

    func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        throw AsyncOnlyAccessUnitSourceError.finiteBatchPathUsed
    }

    func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        AsyncThrowingStream { continuation in
            let accessUnits = accessUnits
            Task {
                for accessUnit in accessUnits {
                    continuation.yield(accessUnit)
                }
            }
        }
    }
}
#endif
