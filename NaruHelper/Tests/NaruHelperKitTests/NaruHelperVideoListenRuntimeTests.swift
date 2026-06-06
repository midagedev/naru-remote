import XCTest
import NaruHelperKit
import NaruRemoteCore

#if canImport(Network)
final class NaruHelperVideoListenRuntimeTests: XCTestCase {
    private let pairingSecret = "test-video-listen-secret"
    private let profileFingerprint = "sha256:test-video-listen-profile"

    func testConfigurationParsesRequiredTokenAndProfileFingerprintWithSafeDefaults() throws {
        let configuration = try NaruHelperVideoListenConfiguration.parse(arguments: [
            "NaruHelper",
            "--video-listen",
            "--token",
            pairingSecret,
            "--profile-fingerprint",
            profileFingerprint
        ])

        XCTAssertEqual(configuration.pairingSecret, pairingSecret)
        XCTAssertEqual(configuration.profileFingerprint, profileFingerprint)
        XCTAssertEqual(configuration.port, UInt16(naruHelperVideoStreamDefaultPort))
        XCTAssertEqual(configuration.sourceMode, .screenCaptureKit)
        XCTAssertEqual(configuration.frameCount, 2)
    }

    func testConfigurationParsesCustomPortSourceAndFrameCount() throws {
        let configuration = try NaruHelperVideoListenConfiguration.parse(arguments: [
            "NaruHelper",
            "--video-listen",
            "--token",
            pairingSecret,
            "--profile-fingerprint",
            profileFingerprint,
            "--port",
            "5999",
            "--video-source",
            "synthetic-encoded",
            "--video-frame-count",
            "3"
        ])

        XCTAssertEqual(configuration.port, 5999)
        XCTAssertEqual(configuration.sourceMode, .syntheticEncoded)
        XCTAssertEqual(configuration.frameCount, 3)
    }

    func testConfigurationParsesSensitiveValuesFromEnvironmentIndirection() throws {
        let configuration = try NaruHelperVideoListenConfiguration.parse(
            arguments: [
                "NaruHelper",
                "--video-listen",
                "--token-env",
                "NARU_HELPER_VIDEO_TOKEN",
                "--profile-fingerprint-env",
                "NARU_HELPER_VIDEO_PROFILE_FINGERPRINT"
            ],
            environment: [
                "NARU_HELPER_VIDEO_TOKEN": pairingSecret,
                "NARU_HELPER_VIDEO_PROFILE_FINGERPRINT": profileFingerprint
            ]
        )

        XCTAssertEqual(configuration.pairingSecret, pairingSecret)
        XCTAssertEqual(configuration.profileFingerprint, profileFingerprint)
        XCTAssertEqual(configuration.port, UInt16(naruHelperVideoStreamDefaultPort))
    }

    func testConfigurationRejectsUnsafeMissingOrInvalidArguments() {
        XCTAssertThrowsError(
            try NaruHelperVideoListenConfiguration.parse(arguments: [
                "NaruHelper",
                "--video-listen",
                "--token",
                "--profile-fingerprint",
                profileFingerprint
            ])
        ) { error in
            XCTAssertEqual(error as? NaruHelperVideoListenConfigurationError, .missingToken)
        }

        XCTAssertThrowsError(
            try NaruHelperVideoListenConfiguration.parse(
                arguments: [
                    "NaruHelper",
                    "--video-listen",
                    "--token-env",
                    "MISSING_TOKEN_ENV",
                    "--profile-fingerprint",
                    profileFingerprint
                ],
                environment: [:]
            )
        ) { error in
            XCTAssertEqual(error as? NaruHelperVideoListenConfigurationError, .missingToken)
        }

        XCTAssertThrowsError(
            try NaruHelperVideoListenConfiguration.parse(arguments: [
                "NaruHelper",
                "--video-listen",
                "--profile-fingerprint",
                profileFingerprint
            ])
        ) { error in
            XCTAssertEqual(error as? NaruHelperVideoListenConfigurationError, .missingToken)
        }

        XCTAssertThrowsError(
            try NaruHelperVideoListenConfiguration.parse(arguments: [
                "NaruHelper",
                "--video-listen",
                "--token",
                pairingSecret
            ])
        ) { error in
            XCTAssertEqual(
                error as? NaruHelperVideoListenConfigurationError,
                .missingProfileFingerprint
            )
        }

        XCTAssertThrowsError(
            try NaruHelperVideoListenConfiguration.parse(
                arguments: [
                    "NaruHelper",
                    "--video-listen",
                    "--token",
                    pairingSecret,
                    "--profile-fingerprint-env",
                    "MISSING_PROFILE_ENV"
                ],
                environment: [:]
            )
        ) { error in
            XCTAssertEqual(
                error as? NaruHelperVideoListenConfigurationError,
                .missingProfileFingerprint
            )
        }

        XCTAssertThrowsError(
            try NaruHelperVideoListenConfiguration.parse(arguments: [
                "NaruHelper",
                "--video-listen",
                "--token",
                pairingSecret,
                "--profile-fingerprint",
                "--port",
                "5999"
            ])
        ) { error in
            XCTAssertEqual(
                error as? NaruHelperVideoListenConfigurationError,
                .missingProfileFingerprint
            )
        }

        XCTAssertThrowsError(
            try NaruHelperVideoListenConfiguration.parse(arguments: [
                "NaruHelper",
                "--video-listen",
                "--token",
                pairingSecret,
                "--profile-fingerprint",
                profileFingerprint,
                "--port",
                "0"
            ])
        ) { error in
            XCTAssertEqual(error as? NaruHelperVideoListenConfigurationError, .invalidPort)
        }

        XCTAssertThrowsError(
            try NaruHelperVideoListenConfiguration.parse(arguments: [
                "NaruHelper",
                "--video-listen",
                "--token",
                pairingSecret,
                "--profile-fingerprint",
                profileFingerprint,
                "--port",
                "--video-source",
                "synthetic-encoded"
            ])
        ) { error in
            XCTAssertEqual(error as? NaruHelperVideoListenConfigurationError, .invalidPort)
        }

        XCTAssertThrowsError(
            try NaruHelperVideoListenConfiguration.parse(arguments: [
                "NaruHelper",
                "--video-listen",
                "--token",
                pairingSecret,
                "--profile-fingerprint",
                profileFingerprint,
                "--video-source",
                "raw"
            ])
        ) { error in
            XCTAssertEqual(error as? NaruHelperVideoListenConfigurationError, .invalidSourceMode)
        }

        XCTAssertThrowsError(
            try NaruHelperVideoListenConfiguration.parse(arguments: [
                "NaruHelper",
                "--video-listen",
                "--token",
                pairingSecret,
                "--profile-fingerprint",
                profileFingerprint,
                "--video-frame-count",
                "-1"
            ])
        ) { error in
            XCTAssertEqual(error as? NaruHelperVideoListenConfigurationError, .invalidFrameCount)
        }
    }

    func testRuntimeServerReceivesAuthenticatedStartAndSendsAccessUnits() async throws {
        let parameterSetPayload = Data([0x00, 0x00, 0x00, 0x01, 0x67])
        let keyframePayload = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
        let configuration = NaruHelperVideoListenConfiguration(
            pairingSecret: pairingSecret,
            profileFingerprint: profileFingerprint,
            port: 0,
            sourceMode: .syntheticEncoded,
            frameCount: 2
        )
        let server = try NaruHelperVideoListenRuntime(
            configuration: configuration
        ).makeServer(
            accessUnitSource: NaruHelperVideoStaticAccessUnitSource(accessUnits: [
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
            timeout: 3
        )
        let result = try await client.startStream(maxServerFrames: 3)

        XCTAssertEqual(result.startResponse.body.result, .accepted)
        XCTAssertEqual(result.startResponse.body.streamDescriptor.codec, .h264)
        XCTAssertNil(result.startResponse.authProof)
        XCTAssertNil(result.stall)
        XCTAssertEqual(result.accessUnits.count, 2)
        XCTAssertEqual(result.accessUnits[0].envelope.body.kind, .parameterSet)
        XCTAssertEqual(result.accessUnits[0].binaryPayload, parameterSetPayload)
        XCTAssertEqual(result.accessUnits[1].envelope.body.kind, .keyframe)
        XCTAssertEqual(result.accessUnits[1].binaryPayload, keyframePayload)
    }

    func testRuntimeRejectsScreenCaptureKitStartWhenPermissionIsMissing() async throws {
        let configuration = NaruHelperVideoListenConfiguration(
            pairingSecret: pairingSecret,
            profileFingerprint: profileFingerprint,
            port: 0,
            sourceMode: .screenCaptureKit,
            frameCount: 2
        )
        let server = try NaruHelperVideoListenRuntime(
            configuration: configuration,
            screenRecordingPermissionProvider: { .missing }
        ).makeServer(
            accessUnitSource: NaruHelperVideoStaticAccessUnitSource(accessUnits: [
                NaruHelperVideoAccessUnit(
                    sequence: 0,
                    kind: .keyframe,
                    binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
                )
            ])
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
            timeout: 3
        )
        let result = try await client.startStream(maxServerFrames: 1)

        XCTAssertEqual(result.startResponse.body.result, .rejected)
        XCTAssertEqual(result.startResponse.body.safeFailureCode, .permissionMissing)
        XCTAssertTrue(result.accessUnits.isEmpty)
        XCTAssertNil(result.stall)
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
