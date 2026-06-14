import CoreGraphics
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(UIKit)
import UIKit

@MainActor
final class MetalFramebufferHotCursorOverlayBenchmarkTests: XCTestCase {
    func testFallbackHotCursorOverlayUpdateBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
        let host = MetalFramebufferHostingView(
            coordinator: MetalFramebufferView.Coordinator(device: nil)
        )
        host.frame = CGRect(origin: .zero, size: CGSize(width: 390, height: 240))

        let options = XCTMeasureOptions()
        options.iterationCount = configuration.iterations

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            autoreleasepool {
                for sample in 0..<configuration.sampleCount {
                    let x = CGFloat(24 + (sample % 320))
                    let y = CGFloat(32 + ((sample * 7) % 160))
                    host.syncInputState(
                        pointerControlMode: .trackpad,
                        trackpadCursor: TrackpadCursor(
                            position: CGPoint(x: x * 4, y: y * 4),
                            isVisible: true
                        ),
                        serverCursor: nil,
                        framebufferSize: CGSize(width: 1_920, height: 1_080)
                    )
                }
            }
        }
    }

    private func requireBenchmarkConfiguration() throws -> BenchmarkConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NARU_RUN_SIM_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set NARU_RUN_SIM_BENCHMARKS=1 to run hot cursor overlay benchmarks.")
        }

        return BenchmarkConfiguration(
            iterations: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_ITERATIONS",
                in: environment,
                defaultValue: 5,
                range: 1...100
            ),
            sampleCount: Self.integerEnvironmentValue(
                "NARU_HELPER_VIDEO_INPUT_BENCHMARK_SAMPLES",
                in: environment,
                defaultValue: 1_000,
                range: 1...10_000
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

    private struct BenchmarkConfiguration {
        var iterations: Int
        var sampleCount: Int
    }
}
#endif
