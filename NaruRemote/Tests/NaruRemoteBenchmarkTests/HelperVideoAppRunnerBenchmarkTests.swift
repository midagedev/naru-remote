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
        let requestBody = HelperVideoStartStreamRequestBody(maxFrameRateBucket: .upTo15)
        let source = NaruHelperVideoToolboxSyntheticAccessUnitSource(
            frameCount: configuration.displayableFrameCount,
            width: configuration.toolboxWidth,
            height: configuration.toolboxHeight
        )
        let helperAccessUnits: [NaruHelperVideoAccessUnit]
        do {
            helperAccessUnits = try source.accessUnits(for: requestBody)
        } catch {
            throw XCTSkip("Toolbox synthetic helper-video source unavailable on this host.")
        }

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
