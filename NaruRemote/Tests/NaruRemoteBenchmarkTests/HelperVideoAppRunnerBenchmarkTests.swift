import Foundation
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if os(macOS)
import NaruHelperKit
#endif

#if canImport(AVFoundation) && canImport(CoreMedia)

/// Opt-in app-side benchmarks for helper-video access units after the helper
/// stream has produced a finite H.264 batch.
///
/// These tests skip unless `NARU_RUN_SIM_BENCHMARKS=1` is present. They keep
/// normal CI deterministic while giving local simulator / host runs a stable
/// way to measure runner state updates plus H.264 sample-buffer creation.
@MainActor
final class HelperVideoAppRunnerBenchmarkTests: XCTestCase {
    func testStaticH264AccessUnitsThroughAppRunnerBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let profile = try Self.profile()
        let session = RemoteSession(profileID: profile.id, state: .active)
        let result = Self.startResult(
            accessUnits: Self.staticAccessUnits(
                displayableFrameCount: configuration.displayableFrameCount
            )
        )

        measure(
            metrics: benchmarkMetrics,
            options: measureOptions(iterations: configuration.iterations)
        ) {
            autoreleasepool {
                let model = Self.model(profile: profile, session: session)
                let renderer = SampleBufferFactoryAccessUnitRenderer()
                let runner = HelperVideoStreamSessionRunner(
                    startStream: { _, _ in result },
                    renderer: renderer
                )

                let outcome = runner.handleStartResult(
                    result,
                    sessionID: session.id,
                    profileID: profile.id,
                    model: model
                )

                XCTAssertTrue(outcome.startAccepted)
                XCTAssertTrue(outcome.selectedVisualTransport)
                XCTAssertNil(outcome.fallbackFailureCode)
                XCTAssertEqual(outcome.displayableFrameCount, configuration.displayableFrameCount)
                XCTAssertEqual(model.snapshot.visualTransportMode, .helperVideo)
                XCTAssertEqual(model.snapshot.helperVideoStreamHealth.state, .healthy)
            }
        }
    }

    #if os(macOS)
    func testToolboxSyntheticH264AccessUnitsThroughAppRunnerBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let profile = try Self.profile()
        let session = RemoteSession(profileID: profile.id, state: .active)
        let result = try Self.toolboxSyntheticStartResult(configuration: configuration)

        measure(
            metrics: benchmarkMetrics,
            options: measureOptions(iterations: configuration.iterations)
        ) {
            autoreleasepool {
                let model = Self.model(profile: profile, session: session)
                let renderer = SampleBufferFactoryAccessUnitRenderer()
                let runner = HelperVideoStreamSessionRunner(
                    startStream: { _, _ in result },
                    renderer: renderer
                )

                let outcome = runner.handleStartResult(
                    result,
                    sessionID: session.id,
                    profileID: profile.id,
                    model: model
                )

                XCTAssertTrue(outcome.startAccepted)
                XCTAssertTrue(outcome.selectedVisualTransport)
                XCTAssertNil(outcome.fallbackFailureCode)
                XCTAssertGreaterThanOrEqual(outcome.displayableFrameCount, 1)
                XCTAssertEqual(model.snapshot.visualTransportMode, .helperVideo)
                XCTAssertEqual(model.snapshot.helperVideoStreamHealth.state, .healthy)
            }
        }
    }

    #if canImport(Network)
    func testNetworkBackedHelperVideoBootstrapThroughAppModelSmoke() async throws {
        let configuration = try requireBenchmarkConfiguration()
        let pairingSecret = "benchmark-helper-video-secret"
        let helperAccessUnits = try Self.toolboxSyntheticHelperAccessUnits(configuration: configuration)
        let server = try Self.makeHelperVideoNetworkServer(
            accessUnits: helperAccessUnits,
            pairingSecret: pairingSecret
        )
        server.start()
        defer { server.cancel() }
        let port = try await Self.waitForPort(server)

        for iteration in 0..<configuration.iterations {
            try await Self.runNetworkBackedHelperVideoBootstrapOnce(
                iteration: iteration,
                port: port,
                pairingSecret: pairingSecret
            )
        }
    }
    #endif
    #endif

    private var benchmarkMetrics: [XCTMetric] {
        [
            XCTClockMetric(),
            XCTCPUMetric(),
            XCTMemoryMetric()
        ]
    }

    private func measureOptions(iterations: Int) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    private func requireBenchmarkConfiguration() throws -> HelperVideoAppRunnerBenchmarkConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NARU_RUN_SIM_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set NARU_RUN_SIM_BENCHMARKS=1 to run helper-video app-runner benchmarks.")
        }

        let width = Self.integerEnvironmentValue(
            "NARU_HELPER_VIDEO_APP_BENCHMARK_WIDTH",
            in: environment,
            defaultValue: 96,
            range: 16...2048
        )
        let height = Self.integerEnvironmentValue(
            "NARU_HELPER_VIDEO_APP_BENCHMARK_HEIGHT",
            in: environment,
            defaultValue: 96,
            range: 16...2048
        )

        return HelperVideoAppRunnerBenchmarkConfiguration(
            iterations: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_ITERATIONS",
                in: environment,
                defaultValue: 10,
                range: 1...100
            ),
            displayableFrameCount: Self.integerEnvironmentValue(
                "NARU_HELPER_VIDEO_APP_BENCHMARK_FRAMES",
                in: environment,
                defaultValue: 4,
                range: 1...120
            ),
            toolboxWidth: Int32(width),
            toolboxHeight: Int32(height)
        )
    }

    private static func integerEnvironmentValue(
        _ name: String,
        in environment: [String: String],
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard let value = environment[name],
              let integer = Int(value),
              range.contains(integer)
        else {
            return defaultValue
        }
        return integer
    }

    private static func profile() throws -> ConnectionProfile {
        try ConnectionProfile(displayName: "Bench", host: "bench.tailnet.test")
    }

    private static func model(
        profile: ConnectionProfile,
        session: RemoteSession
    ) -> NaruRemoteAppModel {
        NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                helperVideoProfileState: [
                    profile.id: HelperVideoProfileState(
                        isEnabled: true,
                        pairingFingerprint: profileFingerprint,
                        availability: .available,
                        lastCheckedBucket: .recent
                    )
                ]
            )
        )
    }

    private static func startResult(
        accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>],
        descriptor: HelperVideoStreamDescriptor = HelperVideoStreamDescriptor(
            codecProfile: .baseline,
            frameRateBucket: .upTo15
        )
    ) -> HelperVideoStreamNetworkStartResult {
        let requestID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        return HelperVideoStreamNetworkStartResult(
            requestID: requestID,
            startResponse: HelperVideoWireEnvelope(
                requestID: requestID,
                messageType: .startStream,
                profileFingerprint: profileFingerprint,
                body: HelperVideoStartStreamResponseBody(
                    result: .accepted,
                    streamDescriptor: descriptor
                )
            ),
            accessUnits: accessUnits
        )
    }

    private static func staticAccessUnits(
        displayableFrameCount: Int
    ) -> [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>] {
        let clampedFrameCount = max(displayableFrameCount, 1)
        var accessUnits = [
            decodedAccessUnit(
                sequence: 0,
                kind: .parameterSet,
                binaryPayload: annexB([sps, pps])
            ),
            decodedAccessUnit(
                sequence: 1,
                kind: .keyframe,
                binaryPayload: annexB([idr])
            )
        ]

        guard clampedFrameCount > 1 else {
            return accessUnits
        }

        accessUnits.append(contentsOf: (2...(clampedFrameCount)).map { sequence in
            decodedAccessUnit(
                sequence: sequence,
                kind: .delta,
                binaryPayload: annexB([delta])
            )
        })
        return accessUnits
    }

    #if os(macOS)
    private static func toolboxSyntheticStartResult(
        configuration: HelperVideoAppRunnerBenchmarkConfiguration
    ) throws -> HelperVideoStreamNetworkStartResult {
        let helperAccessUnits = try toolboxSyntheticHelperAccessUnits(configuration: configuration)
        return startResult(
            accessUnits: helperAccessUnits.map { accessUnit in
                decodedAccessUnit(
                    sequence: accessUnit.sequence,
                    kind: accessUnit.kind,
                    binaryPayload: accessUnit.binaryPayload
                )
            },
            descriptor: HelperVideoStreamDescriptor(
                codecProfile: .high,
                frameRateBucket: .upTo15
            )
        )
    }

    private static func toolboxSyntheticHelperAccessUnits(
        configuration: HelperVideoAppRunnerBenchmarkConfiguration
    ) throws -> [NaruHelperVideoAccessUnit] {
        let requestBody = HelperVideoStartStreamRequestBody(maxFrameRateBucket: .upTo15)
        let source = NaruHelperVideoToolboxSyntheticAccessUnitSource(
            frameCount: configuration.displayableFrameCount,
            width: configuration.toolboxWidth,
            height: configuration.toolboxHeight
        )
        do {
            return try source.accessUnits(for: requestBody)
        } catch {
            throw XCTSkip("Toolbox synthetic helper-video source unavailable on this host.")
        }
    }

    #if canImport(Network)
    private static func makeHelperVideoNetworkServer(
        accessUnits: [NaruHelperVideoAccessUnit],
        pairingSecret: String
    ) throws -> NaruHelperVideoStreamNetworkServer {
        let requestHandler = NaruHelperVideoTransportRequestHandler(
            expectedPairingSecret: pairingSecret,
            expectedProfileFingerprint: profileFingerprint,
            capabilityProvider: {
                HelperVideoCapabilityResponseBody(
                    availability: .available,
                    screenRecordingPermission: .granted,
                    codecSupport: .h264,
                    latencyModes: [.lowLatency]
                )
            }
        )
        let pipeline = NaruHelperVideoStreamFramePipeline(
            requestHandler: requestHandler,
            accessUnitSource: NaruHelperVideoStaticAccessUnitSource(accessUnits: accessUnits)
        )
        return try NaruHelperVideoStreamNetworkServer(pipeline: pipeline)
    }

    private static func waitForPort(
        _ server: NaruHelperVideoStreamNetworkServer
    ) async throws -> UInt16 {
        for _ in 0..<100 {
            if let port = server.port, port > 0 {
                return port
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try XCTUnwrap(server.port)
    }

    private static func runNetworkBackedHelperVideoBootstrapOnce(
        iteration: Int,
        port: UInt16,
        pairingSecret: String
    ) async throws {
        let helperVideoSecretRef = "helper-video-token:network-benchmark-\(iteration)"
        let profile = try ConnectionProfile(
            displayName: "Network Bootstrap Bench",
            host: "127.0.0.1",
            hostKind: .privateAddress,
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoSecretRef,
                pairingFingerprint: profileFingerprint
            )
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 14, green: 28, blue: 42)
        )
        let connector = BenchmarkStreamingConnector(
            width: 2,
            height: 1,
            name: "Network Bootstrap Bench",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                helperVideoProfileState: [
                    profile.id: HelperVideoProfileState(
                        isEnabled: true,
                        pairingFingerprint: profileFingerprint,
                        availability: .available,
                        lastCheckedBucket: .recent
                    )
                ]
            ),
            credentialStore: InMemoryConnectionCredentialStore(
                passwords: [helperVideoSecretRef: pairingSecret]
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            helperVideoStartStream: { _, pairingSecret, pairingFingerprint, requestBody, maxServerFrames in
                let client = HelperVideoStreamNetworkClient(
                    host: "127.0.0.1",
                    port: port,
                    profileFingerprint: pairingFingerprint,
                    pairingSecret: pairingSecret,
                    timeout: 3
                )
                return try await client.startStream(requestBody, maxServerFrames: maxServerFrames)
            },
            helperVideoRendererFactory: {
                SampleBufferFactoryAccessUnitRenderer()
            }
        )

        await model.connectSelectedProfile()
        try await waitForHelperVideoBootstrap(
            model,
            profileID: profile.id,
            latestFramebuffer: framebuffer
        )
        model.sendTapAt(viewPoint: CGPoint(x: 1, y: 0.5), viewSize: CGSize(width: 2, height: 1))
        try await waitForPointerEvents(connector, count: 2)
    }

    private static func waitForHelperVideoBootstrap(
        _ model: NaruRemoteAppModel,
        profileID: ConnectionProfile.ID,
        latestFramebuffer: RFBRawFramebuffer
    ) async throws {
        for _ in 0..<250 {
            let snapshot = model.snapshot
            if snapshot.visualTransportMode == .helperVideo,
               snapshot.helperVideoStreamHealth.state == .healthy,
               snapshot.latestFramebuffer == latestFramebuffer,
               snapshot.helperVideoProfileState[profileID]?.availability == .available,
               snapshot.session?.state == .active {
                XCTAssertEqual(snapshot.helperVideoProfileState[profileID]?.lastFailureCode, nil)
                XCTAssertEqual(snapshot.helperVideoStreamDescriptor?.codec, .h264)
                XCTAssertNotEqual(snapshot.helperVideoStreamDescriptor?.codecProfile, .unknown)
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        let snapshot = model.snapshot
        XCTFail(
            "Timed out waiting for helper-video bootstrap: mode=\(snapshot.visualTransportMode), health=\(snapshot.helperVideoStreamHealth.state), availability=\(String(describing: snapshot.helperVideoProfileState[profileID]?.availability)), failure=\(String(describing: snapshot.helperVideoProfileState[profileID]?.lastFailureCode))"
        )
    }

    private static func waitForPointerEvents(
        _ connector: BenchmarkStreamingConnector,
        count: Int
    ) async throws {
        for _ in 0..<100 {
            if connector.recordedPointerEventMasks.count >= count {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(connector.recordedPointerEventMasks.count, count)
    }
    #endif
    #endif

    private static func decodedAccessUnit(
        sequence: Int,
        kind: HelperVideoAccessUnitKind,
        binaryPayload: Data
    ) -> HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>> {
        HelperVideoDecodedFrame(
            envelope: HelperVideoWireEnvelope(
                messageType: .videoAccessUnit,
                profileFingerprint: profileFingerprint,
                body: HelperVideoAccessUnitBody(sequence: sequence, kind: kind)
            ),
            binaryPayload: binaryPayload
        )
    }

    private static func annexB(_ units: [Data]) -> Data {
        units.enumerated().reduce(into: Data()) { payload, item in
            payload.append(item.offset.isMultiple(of: 2)
                ? Data([0x00, 0x00, 0x00, 0x01])
                : Data([0x00, 0x00, 0x01]))
            payload.append(item.element)
        }
    }

    private static let profileFingerprint = "sha256:helper-video-benchmark"
    private static let sps = Data([
        0x67, 0x42, 0xC0, 0x1E, 0xDA, 0x02, 0x80, 0xB7,
        0xFE, 0x5C, 0x05, 0xA8, 0x30, 0x30, 0x32, 0x00,
        0x00, 0x03, 0x00, 0x02, 0x00, 0x00, 0x03, 0x00,
        0x65, 0x1E, 0x30, 0x60, 0x54
    ])
    private static let pps = Data([0x68, 0xCE, 0x06, 0xE2])
    private static let idr = Data([0x65, 0x88, 0x84, 0x21])
    private static let delta = Data([0x41, 0x9A, 0x22])
}

private struct HelperVideoAppRunnerBenchmarkConfiguration {
    let iterations: Int
    let displayableFrameCount: Int
    let toolboxWidth: Int32
    let toolboxHeight: Int32
}

#if os(macOS) && canImport(Network)
// @unchecked Sendable is limited to this benchmark fake: mutable test state is
// guarded by `lock`, while protocol methods may be called from the app model's
// detached helper-video bootstrap and MainActor pointer path.
private final class BenchmarkStreamingConnector: @unchecked Sendable, RFBStreamingClient, RFBRegionFramebufferUpdating, RFBFramebufferUpdateReceiving, RFBTransportControlClient, RFBContinuousUpdateCapabilityReporting {
    private struct Recording {
        var frameUpdates: [RFBFramebufferUpdateResult]
        var recordedPointerEvents: [(mask: UInt8, x: UInt16, y: UInt16)] = []
    }

    private let lock = NSLock()
    private var recording: Recording
    private let width: Int
    private let height: Int
    private let name: String

    init(width: Int, height: Int, name: String, framebuffer: RFBRawFramebuffer) {
        self.width = width
        self.height = height
        self.name = name
        self.recording = Recording(frameUpdates: [.fullFrame(framebuffer: framebuffer)])
    }

    var state: RFBClientState {
        .receivingFrames
    }

    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
    }

    var canEnableContinuousUpdates: Bool {
        false
    }

    var recordedPointerEventMasks: [UInt8] {
        withLock { $0.recordedPointerEvents.map(\.mask) }
    }

    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectFirstFrame(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectFirstFrame(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: credential, timeout: timeout)
    }

    func connectNoAuthSession(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectSession(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        RFBServerInit(
            width: width,
            height: height,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: name
        )
    }

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        try requestFramebufferUpdate(incremental: incremental, timeout: timeout).framebuffer
    }

    func requestFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBFramebufferUpdateResult {
        try requestFramebufferUpdate(incremental: incremental, timeout: timeout, region: nil)
    }

    func requestFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval,
        region: RFBFramebufferUpdateRegion?
    ) throws -> RFBFramebufferUpdateResult {
        try popFrameUpdate()
    }

    func receiveFramebufferUpdate(timeout: TimeInterval) throws -> RFBFramebufferUpdateResult {
        try popFrameUpdate()
    }

    func setClipboardText(_ text: String) throws {}

    func sendPasteCommand(_ command: PasteCommand) throws {}

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {
        withMutableLock { recording in
            recording.recordedPointerEvents.append((buttonMask, x, y))
        }
    }

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {}

    func renegotiateEncodings(_ preference: RFBEncodingPreference, timeout: TimeInterval) throws {}

    func enableContinuousUpdates(
        _ enabled: Bool,
        region: RFBFramebufferUpdateRegion?,
        timeout: TimeInterval
    ) throws {}

    func sendFence(flags: RFBFenceFlags, payload: Data, timeout: TimeInterval) throws {}

    private func popFrameUpdate() throws -> RFBFramebufferUpdateResult {
        try withMutableLock { recording in
            guard !recording.frameUpdates.isEmpty else {
                throw BenchmarkStreamingConnectorError.noFramebufferUpdate
            }
            return recording.frameUpdates.removeFirst()
        }
    }

    private func withLock<Value>(
        _ body: (Recording) throws -> Value
    ) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try body(recording)
    }

    private func withMutableLock<Value>(
        _ body: (inout Recording) throws -> Value
    ) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try body(&recording)
    }
}

private enum BenchmarkStreamingConnectorError: Error {
    case noFramebufferUpdate
}
#endif

@MainActor
private final class SampleBufferFactoryAccessUnitRenderer: HelperVideoAccessUnitRendering {
    private let factory = HelperVideoH264SampleBufferFactory(timescale: 15)

    @discardableResult
    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) throws -> Bool {
        try factory.makeSampleBuffer(from: decoded) != nil
    }

    func flush() {
        factory.reset()
    }
}
#endif
