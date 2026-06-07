import XCTest
import NaruRemoteCore
@testable import NaruHelperKit

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
        XCTAssertEqual(configuration.frameCount, 0)
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
        XCTAssertEqual(configuration.frameCount, 0)
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

    func testConfigurationParsesContinuousFrameCount() throws {
        let zeroFrameCount = try NaruHelperVideoListenConfiguration.parse(arguments: [
            "NaruHelper",
            "--video-listen",
            "--token",
            pairingSecret,
            "--profile-fingerprint",
            profileFingerprint,
            "--video-frame-count",
            "0"
        ])
        let namedFrameCount = try NaruHelperVideoListenConfiguration.parse(arguments: [
            "NaruHelper",
            "--video-listen",
            "--token",
            pairingSecret,
            "--profile-fingerprint",
            profileFingerprint,
            "--video-frame-count",
            "continuous"
        ])

        XCTAssertEqual(zeroFrameCount.frameCount, 0)
        XCTAssertEqual(namedFrameCount.frameCount, 0)
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

    #if os(macOS) && canImport(VideoToolbox)
    func testRuntimeServerSendsSustainedSyntheticEncodedStream() async throws {
        let frameCount = 6
        let configuration = NaruHelperVideoListenConfiguration(
            pairingSecret: pairingSecret,
            profileFingerprint: profileFingerprint,
            port: 0,
            sourceMode: .syntheticEncoded,
            frameCount: frameCount
        )
        let server = try NaruHelperVideoListenRuntime(configuration: configuration).makeServer()
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
        let result = try await client.startStream(maxServerFrames: frameCount + 2)

        XCTAssertEqual(result.startResponse.body.result, .accepted)
        XCTAssertNil(result.stall)
        XCTAssertGreaterThanOrEqual(result.accessUnits.count, 4)
        XCTAssertEqual(
            result.accessUnits.map { $0.envelope.body.sequence },
            Array(0..<result.accessUnits.count)
        )
        XCTAssertEqual(result.accessUnits[0].envelope.body.kind, .parameterSet)
        XCTAssertGreaterThanOrEqual(
            result.accessUnits.dropFirst().filter { $0.envelope.body.kind == .keyframe }.count,
            1
        )
        XCTAssertGreaterThanOrEqual(
            result.accessUnits.dropFirst().filter { $0.envelope.body.kind == .delta }.count,
            2
        )
    }

    func testExternalHelperProcessSendsSustainedSyntheticEncodedStream() async throws {
        let frameCount = 6
        let helperPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/NaruHelper")
            .path
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: helperPath),
            "NaruHelper executable is not available at \(helperPath)"
        )

        let port = UInt16.random(in: 49_152...65_000)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = [
            "--video-listen",
            "--token-env",
            "NARU_HELPER_VIDEO_TEST_TOKEN",
            "--profile-fingerprint-env",
            "NARU_HELPER_VIDEO_TEST_PROFILE_FINGERPRINT",
            "--port",
            "\(port)",
            "--video-source",
            "synthetic-encoded",
            "--video-frame-count",
            "\(frameCount)"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["NARU_HELPER_VIDEO_TEST_TOKEN"] = pairingSecret
        environment["NARU_HELPER_VIDEO_TEST_PROFILE_FINGERPRINT"] = profileFingerprint
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(process.isRunning, Self.stderrString(from: stderrPipe))

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            timeout: 3
        )
        do {
            var startAccepted = false
            var accessUnits:
                [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>] = []
            for try await event in client.streamEvents() {
                switch event {
                case .startResponse(let response):
                    startAccepted = response.body.result == .accepted
                case .accessUnit(let accessUnit):
                    accessUnits.append(accessUnit)
                    if accessUnits.count >= 4 {
                        break
                    }
                case .stall:
                    XCTFail("External helper stream stalled.")
                    return
                }
            }

            XCTAssertTrue(startAccepted)
            XCTAssertGreaterThanOrEqual(accessUnits.count, 4)
            XCTAssertEqual(
                accessUnits.map { $0.envelope.body.sequence },
                Array(0..<accessUnits.count)
            )
            XCTAssertEqual(accessUnits[0].envelope.body.kind, .parameterSet)
        } catch {
            process.terminate()
            process.waitUntilExit()
            XCTFail("External helper stream failed with \(error): \(Self.stderrString(from: stderrPipe))")
        }
    }
    #endif

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

    #if os(macOS) && canImport(CoreMedia) && canImport(ScreenCaptureKit)
    func testScreenCaptureKitTimeoutBudgetScalesWithSustainedFrameLimit() {
        let smokeTimeout = HelperVideoFrameRateBucket.upTo30
            .screenCaptureFrameCollectionTimeout(frameLimit: 2)
        let sustainedTimeout = HelperVideoFrameRateBucket.upTo30
            .screenCaptureFrameCollectionTimeout(frameLimit: 120)
        let providerTimeout = HelperVideoFrameRateBucket.upTo30
            .screenCaptureProviderTimeout(frameLimit: 120)

        XCTAssertEqual(smokeTimeout, 3)
        XCTAssertGreaterThan(sustainedTimeout, smokeTimeout)
        XCTAssertGreaterThan(providerTimeout, sustainedTimeout)
        XCTAssertLessThanOrEqual(providerTimeout, 12)
    }
    #endif

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

    private static func stderrString(from pipe: Pipe) -> String {
        String(data: pipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
    }
}
#endif
