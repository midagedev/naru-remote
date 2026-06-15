import Foundation
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(AVFoundation) && canImport(CoreMedia)
@preconcurrency import CoreMedia

/// Opt-in benchmark for the app-side helper-video H.264 sample-buffer factory.
///
/// This isolates the work that happens after an access unit has already arrived
/// and been wire-decoded: Annex-B parsing, AVCC payload creation, CMBlockBuffer
/// copy, and ready CMSampleBuffer creation. It intentionally avoids
/// AVSampleBufferDisplayLayer so renderer scheduling does not hide parser cost.
final class HelperVideoSampleBufferFactoryBenchmarkTests: XCTestCase {
    func testDeltaAccessUnitSampleBufferFactoryBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let parameterSet = Self.decodedAccessUnit(
            sequence: 0,
            kind: .parameterSet,
            binaryPayload: Self.annexB([Self.sps, Self.pps])
        )
        let deltaPayload = Self.annexB([
            Self.largeDeltaNALUnit(payloadByteCount: configuration.payloadByteCount)
        ])
        let deltaFrames = (0..<configuration.sampleCount).map { sample in
            Self.decodedAccessUnit(
                sequence: sample + 1,
                kind: .delta,
                binaryPayload: deltaPayload
            )
        }
        let options = XCTMeasureOptions()
        options.iterationCount = configuration.iterations

        measure(
            metrics: [
                XCTClockMetric(),
                XCTCPUMetric(),
                XCTMemoryMetric()
            ],
            options: options
        ) {
            autoreleasepool {
                let factory = HelperVideoH264SampleBufferFactory(timescale: 15)
                do {
                    try factory.makeSampleBuffer(from: parameterSet)
                    var displayableCount = 0
                    for frame in deltaFrames {
                        if try factory.makeSampleBuffer(from: frame) != nil {
                            displayableCount += 1
                        }
                    }
                    XCTAssertEqual(displayableCount, configuration.sampleCount)
                } catch {
                    XCTFail("Helper-video sample-buffer factory benchmark failed: \(error)")
                }
            }
        }
    }

    private func requireBenchmarkConfiguration() throws -> BenchmarkConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NARU_RUN_SIM_BENCHMARKS"] == "1" else {
            throw XCTSkip(
                "Set NARU_RUN_SIM_BENCHMARKS=1 to run helper-video sample-buffer benchmarks."
            )
        }

        return BenchmarkConfiguration(
            iterations: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_ITERATIONS",
                in: environment,
                defaultValue: 5,
                range: 1...100
            ),
            payloadByteCount: Self.integerEnvironmentValue(
                "NARU_HELPER_VIDEO_SAMPLE_BUFFER_BENCHMARK_PAYLOAD_BYTES",
                in: environment,
                defaultValue: 262_144,
                range: 1...1_048_576
            ),
            sampleCount: Self.integerEnvironmentValue(
                "NARU_HELPER_VIDEO_SAMPLE_BUFFER_BENCHMARK_SAMPLES",
                in: environment,
                defaultValue: 500,
                range: 1...5_000
            )
        )
    }

    private static func integerEnvironmentValue(
        _ name: String,
        in environment: [String: String],
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard let rawValue = environment[name],
              let value = Int(rawValue)
        else {
            return defaultValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func decodedAccessUnit(
        sequence: Int,
        kind: HelperVideoAccessUnitKind,
        binaryPayload: Data
    ) -> HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>> {
        HelperVideoDecodedFrame(
            envelope: HelperVideoWireEnvelope(
                messageType: .videoAccessUnit,
                profileFingerprint: "sha256:sample-buffer-benchmark",
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

    private static func largeDeltaNALUnit(payloadByteCount: Int) -> Data {
        let clampedCount = max(payloadByteCount, 1)
        var payload = Data()
        payload.reserveCapacity(clampedCount)
        payload.append(0x41)
        guard clampedCount > 1 else {
            return payload
        }
        for index in 1..<clampedCount {
            payload.append(UInt8(truncatingIfNeeded: index &* 31))
        }
        return payload
    }

    private static let sps = Data([
        0x67, 0x42, 0xC0, 0x1E, 0xDA, 0x02, 0x80, 0xB7,
        0xFE, 0x5C, 0x05, 0xA8, 0x30, 0x30, 0x32, 0x00,
        0x00, 0x03, 0x00, 0x02, 0x00, 0x00, 0x03, 0x00,
        0x65, 0x1E, 0x30, 0x60, 0x54
    ])
    private static let pps = Data([0x68, 0xCE, 0x06, 0xE2])

    private struct BenchmarkConfiguration {
        var iterations: Int
        var payloadByteCount: Int
        var sampleCount: Int
    }
}
#endif
