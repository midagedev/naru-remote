import Foundation
import XCTest
@testable import NaruRemoteCore

/// Opt-in simulator benchmark for the VNC CopyRect path used by terminal-like
/// scrolling updates. It stresses a large overlapping scroll where the decoder
/// must preserve memmove semantics while reporting changed pixels.
final class RFBCopyRectBenchmarkTests: XCTestCase {
    func testOverlappingScrollCopyRectBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let serverInit = RFBServerInit(
            width: configuration.width,
            height: configuration.height,
            pixelFormat: .fullColor32LittleEndian,
            name: "CopyRect Benchmark"
        )
        let previousFramebuffer = Self.framebuffer(
            width: configuration.width,
            height: configuration.height
        )
        let updateData = Self.copyRectUpdateData(
            width: configuration.width,
            height: configuration.height
        )
        let options = measureOptions(iterations: configuration.iterations)
        var lastChangedPixelCount = 0

        measure(
            metrics: benchmarkMetrics,
            options: options
        ) {
            autoreleasepool {
                let result = try! RFBRawFramebufferDecoder.apply(
                    updateData: updateData,
                    serverInit: serverInit,
                    previousFramebuffer: previousFramebuffer
                )
                lastChangedPixelCount = result.changedPixelCount
            }
        }

        XCTAssertEqual(lastChangedPixelCount, configuration.expectedChangedPixelCount)
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

    private func requireBenchmarkConfiguration() throws -> CopyRectBenchmarkConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NARU_RUN_SIM_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set NARU_RUN_SIM_BENCHMARKS=1 to run CopyRect benchmarks.")
        }

        return CopyRectBenchmarkConfiguration(
            width: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_WIDTH",
                in: environment,
                defaultValue: 1920,
                range: 2...8192
            ),
            height: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_HEIGHT",
                in: environment,
                defaultValue: 1080,
                range: 2...8192
            ),
            iterations: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_ITERATIONS",
                in: environment,
                defaultValue: 5,
                range: 1...100
            )
        )
    }

    private static func framebuffer(width: Int, height: Int) -> RFBRawFramebuffer {
        var pixels = [RFBColor]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(
                    RFBColor(
                        red: UInt8(x & 0xff),
                        green: UInt8(y & 0xff),
                        blue: UInt8((x + y) & 0xff)
                    )
                )
            }
        }
        return RFBRawFramebuffer(width: width, height: height, pixels: pixels)
    }

    private static func copyRectUpdateData(width: Int, height: Int) -> Data {
        var data = Data()
        data.reserveCapacity(4 + 12 + 4)
        appendUInt8(0, to: &data)
        appendUInt8(0, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(UInt16(width), to: &data)
        appendUInt16(UInt16(height - 1), to: &data)
        appendInt32(RFBEncoding.copyRect, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(1, to: &data)
        return data
    }

    private static func appendUInt8(_ value: UInt8, to data: inout Data) {
        data.append(value)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0x00ff))
        data.append(UInt8(value & 0x00ff))
    }

    private static func appendInt32(_ value: Int32, to data: inout Data) {
        let rawValue = UInt32(bitPattern: value)
        data.append(UInt8((rawValue >> 24) & 0x000000ff))
        data.append(UInt8((rawValue >> 16) & 0x000000ff))
        data.append(UInt8((rawValue >> 8) & 0x000000ff))
        data.append(UInt8(rawValue & 0x000000ff))
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

private struct CopyRectBenchmarkConfiguration {
    let width: Int
    let height: Int
    let iterations: Int

    var expectedChangedPixelCount: Int {
        width * (height - 1)
    }
}
