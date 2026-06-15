import XCTest
import NaruRemoteCore

/// Opt-in benchmark for helper-video's primary input/viewport path.
///
/// The previous attempt constructed the rendererless UIKit host directly in an
/// iOS unit test. That made the simulator runner prone to hanging during view
/// teardown, which is exactly the opposite of a useful regression harness.
/// This benchmark stresses the same pure viewport math and trackpad resolver
/// without creating `UIView`, `MTKView`, display-link, or decoder objects.
final class HelperVideoViewportInputHotPathBenchmarkTests: XCTestCase {
    func testPureInputHotPathPublishesImmediateTransforms() {
        var driver = Self.makeDriver()
        let zoomUpdate = driver.sync(
            zoomScale: 2,
            panOffset: CGSize(width: -24, height: 12)
        )

        XCTAssertTrue(zoomUpdate.didChange)
        XCTAssertEqual(driver.transform.zoomScale, 2, accuracy: 0.0001)
        XCTAssertEqual(driver.transform.panOffset.width, -24, accuracy: 0.0001)
        XCTAssertEqual(driver.transform.panOffset.height, 12, accuracy: 0.0001)

        let panUpdate = driver.applyPan(translation: CGSize(width: 18, height: -6))
        XCTAssertTrue(panUpdate.panDidChange)
        XCTAssertEqual(driver.transform.panOffset.width, -6, accuracy: 0.0001)
        XCTAssertEqual(driver.transform.panOffset.height, 6, accuracy: 0.0001)

        let pinchUpdate = driver.applyPinch(
            scaleMultiplier: 1.1,
            anchor: Self.viewCenter,
            anchorDelta: CGSize(width: 12, height: -4)
        )
        XCTAssertTrue(pinchUpdate.zoomDidChange)
        XCTAssertEqual(driver.transform.zoomScale, 2.2, accuracy: 0.0001)

        let resolver = PointerGestureResolver(mode: .trackpad)
        let cursor = TrackpadCursor(position: Self.framebufferCenter, isVisible: true)
        let outcome = resolver.resolve(
            .dragChanged(viewPoint: Self.viewCenter, translation: CGSize(width: 8, height: 0)),
            transform: driver.transform,
            cursor: cursor
        )
        let trackpadUpdate = driver.adopt(outcome.transform)

        XCTAssertEqual(outcome.commandCount, 1)
        XCTAssertTrue(trackpadUpdate.didChange)
        XCTAssertNotEqual(outcome.cursor.position, cursor.position)
    }

    func testPureViewportInputHotPathThroughputBenchmark() throws {
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
                let result = Self.runSyntheticInputBurst(sampleCount: configuration.sampleCount)
                XCTAssertEqual(result.sampleCount, configuration.sampleCount)
                XCTAssertEqual(result.publishedTransformCount, configuration.sampleCount)
                XCTAssertGreaterThan(result.panChangeCount, 0)
                XCTAssertGreaterThan(result.zoomChangeCount, 0)
                XCTAssertGreaterThan(result.trackpadCommandCount, 0)
                XCTAssertTrue(result.lastTransform.zoomScale.isFinite)
                XCTAssertTrue(result.lastTransform.panOffset.width.isFinite)
                XCTAssertTrue(result.lastTransform.panOffset.height.isFinite)
            }
        }
    }

    private static func runSyntheticInputBurst(sampleCount: Int) -> SyntheticInputBurstResult {
        var driver = makeDriver()
        _ = driver.sync(zoomScale: 2.1, panOffset: .zero)

        let resolver = PointerGestureResolver(mode: .trackpad)
        var cursor = TrackpadCursor(position: framebufferCenter, isVisible: true)
        var panChangeCount = 0
        var zoomChangeCount = 0
        var trackpadCommandCount = 0

        for sample in 0..<sampleCount {
            let update: ViewportInputHotPathUpdate
            switch sample % 3 {
            case 0:
                let direction: CGFloat = ((sample / 24) % 2 == 0) ? 1 : -1
                update = driver.applyPan(
                    translation: CGSize(width: direction * 3, height: direction * 1.5)
                )
            case 1:
                let expands = ((sample / 18) % 2 == 0)
                let multiplier: CGFloat = expands ? 1.003 : 0.997
                let anchorShift: CGFloat = expands ? 1.5 : -1.5
                update = driver.applyPinch(
                    scaleMultiplier: multiplier,
                    anchor: CGPoint(x: viewCenter.x + anchorShift, y: viewCenter.y),
                    anchorDelta: CGSize(width: anchorShift, height: 0)
                )
            default:
                let direction: CGFloat = ((sample / 30) % 2 == 0) ? 1 : -1
                let outcome = resolver.resolve(
                    .dragChanged(
                        viewPoint: viewCenter,
                        translation: CGSize(width: direction * 6, height: 0)
                    ),
                    transform: driver.transform,
                    cursor: cursor
                )
                cursor = outcome.cursor
                trackpadCommandCount += outcome.commandCount
                update = driver.adopt(outcome.transform)
            }

            if update.panDidChange {
                panChangeCount += 1
            }
            if update.zoomDidChange {
                zoomChangeCount += 1
            }
        }

        return SyntheticInputBurstResult(
            sampleCount: sampleCount,
            publishedTransformCount: sampleCount,
            panChangeCount: panChangeCount,
            zoomChangeCount: zoomChangeCount,
            trackpadCommandCount: trackpadCommandCount,
            lastTransform: driver.transform
        )
    }

    private static func makeDriver() -> ViewportInputHotPathDriver {
        ViewportInputHotPathDriver(
            framebufferSize: framebufferSize,
            viewSize: viewSize,
            zoomScale: 1,
            panOffset: .zero,
            minimumZoomScale: 1,
            maxZoomScale: 4
        )
    }

    private func requireBenchmarkConfiguration() throws -> BenchmarkConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NARU_RUN_SIM_BENCHMARKS"] == "1" else {
            throw XCTSkip(
                "Set NARU_RUN_SIM_BENCHMARKS=1 to run helper-video viewport input benchmarks."
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
                "NARU_HELPER_VIDEO_INPUT_BENCHMARK_SAMPLES",
                in: environment,
                defaultValue: 240,
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

    private static let viewSize = CGSize(width: 390, height: 240)
    private static let framebufferSize = CGSize(width: 1_920, height: 1_080)
    private static let viewCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
    private static let framebufferCenter = CGPoint(
        x: framebufferSize.width / 2,
        y: framebufferSize.height / 2
    )

    private struct BenchmarkConfiguration {
        var iterations: Int
        var sampleCount: Int
    }

    private struct SyntheticInputBurstResult {
        var sampleCount: Int
        var publishedTransformCount: Int
        var panChangeCount: Int
        var zoomChangeCount: Int
        var trackpadCommandCount: Int
        var lastTransform: ViewportTransform
    }
}
