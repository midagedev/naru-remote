import XCTest
@testable import NaruRemoteApp

/// Opt-in benchmark for the MainActor transient input/viewport lease used to
/// keep frame delivery input-aware while users type, tap direct keys, or drag
/// the trackpad cursor.
@MainActor
final class TransientFrameDeliveryInteractionBenchmarkTests: XCTestCase {
    func testRepeatedTransientInteractionMarksBenchmark() throws {
        let configuration = try requireBenchmarkConfiguration()
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
                let model = NaruRemoteAppModel()
                for _ in 0..<configuration.sampleCount {
                    model.markTransientFrameDeliveryInteractionActivityForTesting()
                }
                XCTAssertEqual(
                    model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
                    .milliseconds(50)
                )
                model.disconnect()
                XCTAssertEqual(
                    model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
                    .milliseconds(16)
                )
            }
        }
    }

    private func requireBenchmarkConfiguration() throws -> BenchmarkConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NARU_RUN_SIM_BENCHMARKS"] == "1" else {
            throw XCTSkip(
                "Set NARU_RUN_SIM_BENCHMARKS=1 to run transient interaction benchmarks."
            )
        }

        return BenchmarkConfiguration(
            iterations: Self.integerEnvironmentValue(
                "NARU_SIM_BENCHMARK_ITERATIONS",
                in: environment,
                defaultValue: 5,
                range: 1...100
            ),
            sampleCount: Self.integerEnvironmentValue(
                "NARU_TRANSIENT_INTERACTION_BENCHMARK_SAMPLES",
                in: environment,
                defaultValue: 5_000,
                range: 1...50_000
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
