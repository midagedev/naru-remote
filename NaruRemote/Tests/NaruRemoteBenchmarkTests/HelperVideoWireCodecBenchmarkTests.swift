import Foundation
import XCTest
import NaruRemoteCore

/// Opt-in helper-video wire codec benchmarks for the client receive path.
///
/// These tests compare the historical full-frame access-unit decode with the
/// streaming split-frame decode used by `HelperVideoStreamNetworkClient`.
/// They skip unless `NARU_RUN_SIM_BENCHMARKS=1` is present.
final class HelperVideoWireCodecBenchmarkTests: XCTestCase {
    func testFullFrameAccessUnitDecodeBenchmark() throws {
        let fixture = try Self.fixture()
        let options = Self.measureOptions(iterations: fixture.iterations)

        measure(metrics: Self.benchmarkMetrics, options: options) {
            for _ in 0..<fixture.sampleCount {
                let decoded = try! HelperVideoWireCodec.decodeFrame(
                    HelperVideoWireEnvelope<HelperVideoAccessUnitBody>.self,
                    from: fixture.fullFrame,
                    expectsBinaryPayload: true
                )
                XCTAssertEqual(decoded.binaryPayload?.count, fixture.payloadByteCount)
            }
        }
    }

    func testSplitAccessUnitDecodeBenchmark() throws {
        let fixture = try Self.fixture()
        let options = Self.measureOptions(iterations: fixture.iterations)

        measure(metrics: Self.benchmarkMetrics, options: options) {
            for _ in 0..<fixture.sampleCount {
                let decoded = try! HelperVideoWireCodec.decodeFrame(
                    HelperVideoWireEnvelope<HelperVideoAccessUnitBody>.self,
                    fromJSONFrame: fixture.jsonFrame,
                    binaryHeader: fixture.binaryHeader,
                    binaryPayload: fixture.binaryPayload
                )
                XCTAssertEqual(decoded.binaryPayload?.count, fixture.payloadByteCount)
            }
        }
    }

    private static var benchmarkMetrics: [XCTMetric] {
        [
            XCTClockMetric(),
            XCTCPUMetric(),
            XCTMemoryMetric()
        ]
    }

    private static func measureOptions(iterations: Int) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    private static func fixture() throws -> HelperVideoWireCodecBenchmarkFixture {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NARU_RUN_SIM_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set NARU_RUN_SIM_BENCHMARKS=1 to run helper-video wire codec benchmarks.")
        }

        let payloadByteCount = integerEnvironmentValue(
            "NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_PAYLOAD_BYTES",
            in: environment,
            defaultValue: 256 * 1024,
            range: 1...(8 * 1024 * 1024)
        )
        let sampleCount = integerEnvironmentValue(
            "NARU_HELPER_VIDEO_WIRE_CODEC_BENCHMARK_SAMPLES",
            in: environment,
            defaultValue: 200,
            range: 1...10_000
        )
        let iterations = integerEnvironmentValue(
            "NARU_SIM_BENCHMARK_ITERATIONS",
            in: environment,
            defaultValue: 10,
            range: 1...100
        )
        let payload = Data((0..<payloadByteCount).map { UInt8(truncatingIfNeeded: $0) })
        let envelope = HelperVideoWireEnvelope(
            messageType: .videoAccessUnit,
            profileFingerprint: "sha256:benchmark-profile",
            body: HelperVideoAccessUnitBody(sequence: 1, kind: .keyframe)
        )
        let frame = try HelperVideoWireCodec.frameAccessUnit(envelope, binaryPayload: payload)
        let jsonLength = try HelperVideoWireCodec.jsonPayloadLength(
            from: Data(frame.prefix(HelperVideoWireCodec.headerByteCount))
        )
        let jsonEnd = HelperVideoWireCodec.headerByteCount + jsonLength
        let binaryHeaderEnd = jsonEnd + HelperVideoWireCodec.headerByteCount

        return HelperVideoWireCodecBenchmarkFixture(
            iterations: iterations,
            sampleCount: sampleCount,
            payloadByteCount: payloadByteCount,
            fullFrame: frame,
            jsonFrame: frame.subdata(in: 0..<jsonEnd),
            binaryHeader: frame.subdata(in: jsonEnd..<binaryHeaderEnd),
            binaryPayload: frame.subdata(in: binaryHeaderEnd..<frame.count)
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
}

private struct HelperVideoWireCodecBenchmarkFixture {
    let iterations: Int
    let sampleCount: Int
    let payloadByteCount: Int
    let fullFrame: Data
    let jsonFrame: Data
    let binaryHeader: Data
    let binaryPayload: Data
}
