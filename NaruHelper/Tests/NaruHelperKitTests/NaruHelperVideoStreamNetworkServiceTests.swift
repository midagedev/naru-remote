import XCTest
import NaruHelperKit
import NaruRemoteCore

#if canImport(Network)
final class NaruHelperVideoStreamNetworkServiceTests: XCTestCase {
    private let pairingSecret = "test-pairing-secret"
    private let profileFingerprint = "sha256:test-profile"

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
        let pipeline = NaruHelperVideoStreamFramePipeline(
            requestHandler: requestHandler,
            accessUnitSource: source
        )
        return try NaruHelperVideoStreamNetworkServer(pipeline: pipeline)
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
                    try? await Task.sleep(for: .milliseconds(10))
                }
                continuation.finish()
            }
        }
    }
}

private enum AsyncOnlyAccessUnitSourceError: Error {
    case finiteBatchPathUsed
}
#endif
