import Foundation
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(Metal) && canImport(MetalKit)
import Metal
import MetalKit

/// Opt-in simulator benchmarks for the hottest local part of the live
/// VNC path: full-size framebuffer allocation and Metal texture upload.
///
/// These tests intentionally skip unless `NARU_RUN_SIM_BENCHMARKS=1`
/// is present so normal CI/test loops stay deterministic. Run them
/// through xcodebuild on an iPhone simulator when investigating heat or
/// FPS regressions.
@MainActor
final class SyntheticFramePipelineBenchmarkTests: XCTestCase {
    func testFullFramebufferAllocationAndUploadBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let renderer = try makeRenderer()
        let options = measureOptions(iterations: configuration.iterations)

        measure(
            metrics: benchmarkMetrics,
            options: options
        ) {
            autoreleasepool {
                let framebuffer = RFBRawFramebuffer(
                    width: configuration.width,
                    height: configuration.height,
                    fill: configuration.nextFrameColor
                )
                renderer.enqueue(framebuffer)
                XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
            }
        }
    }

    func testSteadyStateFullUploadBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let renderer = try makeRenderer()
        let framebuffer = RFBRawFramebuffer(
            width: configuration.width,
            height: configuration.height,
            fill: configuration.nextFrameColor
        )
        renderer.enqueue(framebuffer)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        let options = measureOptions(iterations: configuration.iterations)
        measure(
            metrics: benchmarkMetrics,
            options: options
        ) {
            renderer.enqueue(framebuffer)
            XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
            XCTAssertEqual(renderer.lastUploadRegionCount, 1)
        }
    }

    func testSmallDirtyRectUploadBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let renderer = try makeRenderer()
        let baseline = RFBRawFramebuffer(
            width: configuration.width,
            height: configuration.height,
            fill: configuration.baselineColor
        )
        let next = RFBRawFramebuffer(
            width: configuration.width,
            height: configuration.height,
            fill: configuration.nextFrameColor
        )
        renderer.enqueue(baseline)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        let options = measureOptions(iterations: configuration.iterations)
        measure(
            metrics: benchmarkMetrics,
            options: options
        ) {
            renderer.enqueue(next, dirtyRectangles: [configuration.smallDirtyRect])
            XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
            XCTAssertEqual(renderer.lastUploadRegionCount, 1)
        }
    }

    func testSameFramebufferUploadGateSkipBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        var uploadGate = FramebufferUploadGate()
        let framebuffer = RFBRawFramebuffer(
            width: configuration.width,
            height: configuration.height,
            fill: configuration.nextFrameColor
        )

        XCTAssertTrue(uploadGate.shouldEnqueue(framebuffer: framebuffer))

        let options = measureOptions(iterations: configuration.iterations)
        measure(
            metrics: benchmarkMetrics,
            options: options
        ) {
            XCTAssertFalse(uploadGate.shouldEnqueue(framebuffer: framebuffer))
        }
    }

    private var benchmarkMetrics: [XCTMetric] {
        [
            XCTClockMetric(),
            XCTCPUMetric(),
            XCTMemoryMetric()
        ]
    }

    private func makeRenderer() throws -> MetalFramebufferRenderer {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable on this simulator/host.")
        }
        return try XCTUnwrap(MetalFramebufferRenderer(device: device))
    }

    private func measureOptions(iterations: Int) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    private func requireBenchmarkConfiguration() throws -> SyntheticBenchmarkConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NARU_RUN_SIM_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set NARU_RUN_SIM_BENCHMARKS=1 to run synthetic frame pipeline benchmarks.")
        }

        return SyntheticBenchmarkConfiguration(
            width: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_WIDTH",
                in: environment,
                defaultValue: 1920,
                range: 1...8192
            ),
            height: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_HEIGHT",
                in: environment,
                defaultValue: 1080,
                range: 1...8192
            ),
            iterations: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_ITERATIONS",
                in: environment,
                defaultValue: 10,
                range: 1...100
            )
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

private struct SyntheticBenchmarkConfiguration {
    let width: Int
    let height: Int
    let iterations: Int

    var baselineColor: RFBColor {
        RFBColor(red: 10, green: 20, blue: 30, alpha: 255)
    }

    var nextFrameColor: RFBColor {
        RFBColor(red: 80, green: 120, blue: 160, alpha: 255)
    }

    var smallDirtyRect: RFBFrameDamageRect {
        RFBFrameDamageRect(
            x: 0,
            y: 0,
            width: min(width, 320),
            height: min(height, 180)
        )
    }
}
#endif
