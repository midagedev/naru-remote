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
            accessUnitSource: NaruHelperVideoStaticAccessUnitSource(accessUnits: accessUnits)
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
#endif
