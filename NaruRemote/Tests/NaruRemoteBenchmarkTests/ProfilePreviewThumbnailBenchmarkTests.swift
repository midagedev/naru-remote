import Foundation
import XCTest
@testable import NaruRemoteCore
@testable import NaruRemoteApp

/// Opt-in benchmark for the active-session preview cache path used by the
/// connection grid's last-frame thumbnails.
final class ProfilePreviewThumbnailBenchmarkTests: XCTestCase {
    func testProfilePreviewThumbnailGenerationBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let framebuffer = Self.makeFramebuffer(
            width: configuration.framebufferWidth,
            height: configuration.framebufferHeight
        )
        let options = XCTMeasureOptions()
        options.iterationCount = configuration.iterations
        var lastThumbnail: ProfilePreviewThumbnail?

        measure(
            metrics: [
                XCTClockMetric(),
                XCTCPUMetric(),
                XCTMemoryMetric()
            ],
            options: options
        ) {
            autoreleasepool {
                for sample in 0..<configuration.sampleCount {
                    lastThumbnail = ProfilePreviewThumbnail(
                        framebuffer: framebuffer,
                        capturedAt: Date(timeIntervalSince1970: Double(sample))
                    )
                }
            }
        }

        let thumbnail = try XCTUnwrap(lastThumbnail)
        XCTAssertEqual(thumbnail.width, configuration.expectedThumbnailWidth)
        XCTAssertEqual(thumbnail.height, configuration.expectedThumbnailHeight)
        XCTAssertEqual(thumbnail.rgbaData.count, thumbnail.width * thumbnail.height * 4)
    }

    private func requireBenchmarkConfiguration() throws -> BenchmarkConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NARU_RUN_SIM_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set NARU_RUN_SIM_BENCHMARKS=1 to run profile preview benchmarks.")
        }

        return BenchmarkConfiguration(
            iterations: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_ITERATIONS",
                in: environment,
                defaultValue: 5,
                range: 1...100
            ),
            sampleCount: Self.integerEnvironmentValue(
                "NARU_PROFILE_PREVIEW_BENCHMARK_SAMPLES",
                in: environment,
                defaultValue: 200,
                range: 1...2_000
            ),
            framebufferWidth: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_WIDTH",
                in: environment,
                defaultValue: 1920,
                range: 1...8192
            ),
            framebufferHeight: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_HEIGHT",
                in: environment,
                defaultValue: 1080,
                range: 1...8192
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
                        blue: UInt8((y * 5) & 0xff)
                    )
                )
            }
        }
        return RFBRawFramebuffer(width: width, height: height, pixelsForTesting: pixels)
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

    private struct BenchmarkConfiguration {
        var iterations: Int
        var sampleCount: Int
        var framebufferWidth: Int
        var framebufferHeight: Int

        var expectedThumbnailWidth: Int {
            let scale = min(
                1.0,
                Double(ProfilePreviewThumbnail.defaultMaxWidth) / Double(framebufferWidth),
                Double(ProfilePreviewThumbnail.defaultMaxHeight) / Double(framebufferHeight)
            )
            return max(1, Int((Double(framebufferWidth) * scale).rounded()))
        }

        var expectedThumbnailHeight: Int {
            let scale = min(
                1.0,
                Double(ProfilePreviewThumbnail.defaultMaxWidth) / Double(framebufferWidth),
                Double(ProfilePreviewThumbnail.defaultMaxHeight) / Double(framebufferHeight)
            )
            return max(1, Int((Double(framebufferHeight) * scale).rounded()))
        }
    }
}

private extension RFBRawFramebuffer {
    init(width: Int, height: Int, pixelsForTesting pixels: [RFBColor]) {
        self.init(width: width, height: height, pixels: pixels)
    }
}
