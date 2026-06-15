import Foundation
import XCTest
@testable import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(CoreVideo)
import CoreVideo

/// Opt-in benchmark for the PiP Watch sample-buffer pixel write path.
final class PiPWatchSampleBufferFactoryBenchmarkTests: XCTestCase {
    func testFullFramePixelBufferFactoryBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let framebuffer = Self.makeFramebuffer(width: configuration.width, height: configuration.height)
        let factory = PiPWatchSampleBufferFactory()
        let options = measureOptions(iterations: configuration.iterations)
        var lastPixelBuffer: CVPixelBuffer?

        measure(
            metrics: benchmarkMetrics,
            options: options
        ) {
            autoreleasepool {
                for _ in 0..<configuration.sampleCount {
                    lastPixelBuffer = try? factory.makePixelBuffer(from: framebuffer)
                    XCTAssertNotNil(lastPixelBuffer)
                }
            }
        }

        let pixelBuffer = try XCTUnwrap(lastPixelBuffer)
        XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), configuration.width)
        XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), configuration.height)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixelBuffer), kCVPixelFormatType_32BGRA)
    }

    func testZoomedViewportPixelBufferFactoryBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let framebuffer = Self.makeFramebuffer(width: configuration.width, height: configuration.height)
        let viewport = PiPWatchViewport(centerX: 0.5, centerY: 0.5, zoomScale: 2)
        let factory = PiPWatchSampleBufferFactory()
        let options = measureOptions(iterations: configuration.iterations)
        var lastPixelBuffer: CVPixelBuffer?

        measure(
            metrics: benchmarkMetrics,
            options: options
        ) {
            autoreleasepool {
                for _ in 0..<configuration.sampleCount {
                    lastPixelBuffer = try? factory.makePixelBuffer(
                        from: framebuffer,
                        viewport: viewport
                    )
                    XCTAssertNotNil(lastPixelBuffer)
                }
            }
        }

        let pixelBuffer = try XCTUnwrap(lastPixelBuffer)
        XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), configuration.width)
        XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), configuration.height)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixelBuffer), kCVPixelFormatType_32BGRA)
    }

    func testLegacyFullFramePixelBufferFactoryBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let framebuffer = Self.makeFramebuffer(width: configuration.width, height: configuration.height)
        let options = measureOptions(iterations: configuration.iterations)
        var lastPixelBuffer: CVPixelBuffer?

        measure(
            metrics: benchmarkMetrics,
            options: options
        ) {
            autoreleasepool {
                for _ in 0..<configuration.sampleCount {
                    lastPixelBuffer = try? Self.makeLegacyPixelBuffer(from: framebuffer)
                    XCTAssertNotNil(lastPixelBuffer)
                }
            }
        }

        let pixelBuffer = try XCTUnwrap(lastPixelBuffer)
        XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), configuration.width)
        XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), configuration.height)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixelBuffer), kCVPixelFormatType_32BGRA)
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
            throw XCTSkip("Set NARU_RUN_SIM_BENCHMARKS=1 to run PiP sample-buffer benchmarks.")
        }

        return BenchmarkConfiguration(
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
                defaultValue: 5,
                range: 1...100
            ),
            sampleCount: Self.integerEnvironmentValue(
                "NARU_PIP_SAMPLE_BUFFER_BENCHMARK_SAMPLES",
                in: environment,
                defaultValue: 20,
                range: 1...1_000
            )
        )
    }

    private static func makeFramebuffer(width: Int, height: Int) -> RFBRawFramebuffer {
        var pixels: [RFBColor] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(
                    RFBColor(
                        red: UInt8((x + y) & 0xff),
                        green: UInt8((x * 3) & 0xff),
                        blue: UInt8((y * 5) & 0xff),
                        alpha: 255
                    )
                )
            }
        }
        return RFBRawFramebuffer(width: width, height: height, pixelsForTesting: pixels)
    }

    private static func makeLegacyPixelBuffer(from framebuffer: RFBRawFramebuffer) throws -> CVPixelBuffer {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            framebuffer.width,
            framebuffer.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw PiPWatchSampleBufferRendererError.pixelBufferCreationFailed
        }

        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard lockStatus == kCVReturnSuccess else {
            throw PiPWatchSampleBufferRendererError.pixelBufferLockFailed(lockStatus)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw PiPWatchSampleBufferRendererError.pixelBufferBaseAddressUnavailable
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let destination = baseAddress.assumingMemoryBound(to: UInt8.self)
        let sourceColumns = (0..<framebuffer.width).map { x in x }
        let sourceRows = (0..<framebuffer.height).map { y in y }

        for y in 0..<framebuffer.height {
            let sourceY = sourceRows[y]
            let sourceRowBase = sourceY * framebuffer.width
            for x in 0..<framebuffer.width {
                let color = framebuffer.pixels[sourceRowBase + sourceColumns[x]]

                let offset = y * bytesPerRow + x * 4
                destination[offset] = color.blue
                destination[offset + 1] = color.green
                destination[offset + 2] = color.red
                destination[offset + 3] = color.alpha
            }
        }

        return pixelBuffer
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

private struct BenchmarkConfiguration {
    let width: Int
    let height: Int
    let iterations: Int
    let sampleCount: Int
}

private extension RFBRawFramebuffer {
    init(width: Int, height: Int, pixelsForTesting pixels: [RFBColor]) {
        self.init(width: width, height: height, pixels: pixels)
    }
}
#endif
