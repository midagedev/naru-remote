import Foundation
import XCTest
@testable import NaruRemoteCore

/// Opt-in benchmark for the small RFB client messages emitted by the direct
/// key and trackpad input lanes.
final class RFBClientMessageEncoderBenchmarkTests: XCTestCase {
    func testKeyAndPointerMessageEncodingBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let options = measureOptions(iterations: configuration.iterations)
        let keysyms = Self.keysyms
        let pointerSamples = Self.pointerSamples
        var encodedByteCount = 0
        var encodedChecksum = 0

        measure(metrics: benchmarkMetrics, options: options) {
            autoreleasepool {
                var totalByteCount = 0
                var totalChecksum = 0
                for index in 0..<configuration.sampleCount {
                    let keysym = keysyms[index % keysyms.count]
                    let pointer = pointerSamples[index % pointerSamples.count]
                    let keyDown = RFBClientMessageEncoder.keyEvent(keysym: keysym, isDown: true)
                    let keyUp = RFBClientMessageEncoder.keyEvent(keysym: keysym, isDown: false)
                    let pointerMove = RFBClientMessageEncoder.encodePointerEvent(
                        buttonMask: pointer.buttonMask,
                        x: pointer.x,
                        y: pointer.y
                    )
                    totalByteCount += keyDown.count + keyUp.count + pointerMove.count
                    totalChecksum &+= Self.checksum(keyDown)
                    totalChecksum &+= Self.checksum(keyUp)
                    totalChecksum &+= Self.checksum(pointerMove)
                }
                encodedByteCount = totalByteCount
                encodedChecksum = totalChecksum
            }
        }

        XCTAssertEqual(encodedByteCount, configuration.sampleCount * 22)
        XCTAssertGreaterThan(encodedChecksum, 0)
    }

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

    private func requireBenchmarkConfiguration() throws -> BenchmarkConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NARU_RUN_SIM_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set NARU_RUN_SIM_BENCHMARKS=1 to run RFB client message encoder benchmarks.")
        }

        return BenchmarkConfiguration(
            iterations: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_ITERATIONS",
                in: environment,
                defaultValue: 10,
                range: 1...100
            ),
            sampleCount: Self.integerEnvironmentValue(
                "NARU_RFB_CLIENT_MESSAGE_BENCHMARK_SAMPLES",
                in: environment,
                defaultValue: 250_000,
                range: 1...2_000_000
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

    @inline(never)
    private static func checksum(_ data: Data) -> Int {
        data.reduce(0) { partialResult, byte in
            partialResult &+ Int(byte)
        }
    }

    private static let keysyms: [UInt32] = [
        0x0061,
        0x0062,
        0x0063,
        0xff09,
        0xff0d,
        0xff1b,
        0xff51,
        0xff52,
        0xff53,
        0xff54,
        0xffe1,
        0xffe3,
        0xffe7,
        0xffe9
    ]

    private static let pointerSamples: [PointerSample] = [
        PointerSample(buttonMask: 0x00, x: 0, y: 0),
        PointerSample(buttonMask: 0x00, x: 640, y: 360),
        PointerSample(buttonMask: 0x01, x: 960, y: 540),
        PointerSample(buttonMask: 0x00, x: 1_280, y: 720),
        PointerSample(buttonMask: 0x08, x: 1_919, y: 1_079),
        PointerSample(buttonMask: 0x10, x: 320, y: 900)
    ]

    private struct BenchmarkConfiguration {
        var iterations: Int
        var sampleCount: Int
    }

    private struct PointerSample {
        var buttonMask: UInt8
        var x: UInt16
        var y: UInt16
    }
}
