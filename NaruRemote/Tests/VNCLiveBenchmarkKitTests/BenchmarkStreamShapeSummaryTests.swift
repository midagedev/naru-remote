import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeSummaryTests: XCTestCase {
    func testDisabledWhenRequestedSamplesIsZero() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 0,
            samples: [],
            elapsedMilliseconds: nil,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )

        XCTAssertEqual(summary.status, .disabled)
        XCTAssertEqual(summary.receivedSamples, 0)
        XCTAssertNil(summary.deliveredFramesPerSecond)
    }

    func testContentAndEmptySamplesProduceMixedSummary() throws {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 3,
            samples: [
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 30,
                    dirtyRectangleCount: 2,
                    dirtyAreaPermille: 120,
                    changedPixelsPermille: 90
                ),
                BenchmarkStreamShapeSample(
                    kind: .emptyUpdate,
                    durationMilliseconds: 50,
                    dirtyRectangleCount: 0,
                    dirtyAreaPermille: 0,
                    changedPixelsPermille: 0
                )
            ],
            elapsedMilliseconds: 100,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )

        XCTAssertEqual(summary.status, .mixedUpdates)
        XCTAssertEqual(summary.receivedSamples, 2)
        XCTAssertEqual(summary.emptyUpdateSamples, 1)
        XCTAssertEqual(summary.contentUpdateSamples, 1)
        XCTAssertEqual(summary.deliveredFramesPerSecond, 20)
        XCTAssertEqual(try XCTUnwrap(summary.updateLatency).averageMilliseconds, 40)
        XCTAssertEqual(try XCTUnwrap(summary.dirtyRectangleCount).maxMilliseconds, 2)
        XCTAssertEqual(try XCTUnwrap(summary.dirtyAreaPermille).maxMilliseconds, 120)
        XCTAssertEqual(try XCTUnwrap(summary.changedPixelsPermille).maxMilliseconds, 90)
    }

    func testTimeoutWithoutSamplesReportsNoUpdateBeforeTimeout() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 4,
            samples: [],
            elapsedMilliseconds: 750,
            firstTimeoutMilliseconds: 750,
            failureLabel: nil
        )

        XCTAssertEqual(summary.status, .noUpdateBeforeTimeout)
        XCTAssertEqual(summary.timedOutSamples, 1)
        XCTAssertEqual(summary.deliveredFramesPerSecond, 0)
        XCTAssertEqual(summary.firstTimeoutMilliseconds, 750)
    }

    func testFailureOverridesObservedSamples() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 2,
            samples: [
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 10,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 20,
                    changedPixelsPermille: 20
                )
            ],
            elapsedMilliseconds: 20,
            firstTimeoutMilliseconds: nil,
            failureLabel: "connection-failed"
        )

        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.failureLabel, "connection-failed")
    }

    func testSamplesClampNegativeAndOversizedValues() {
        let sample = BenchmarkStreamShapeSample(
            kind: .contentUpdate,
            durationMilliseconds: -1,
            dirtyRectangleCount: -2,
            dirtyAreaPermille: 1_500,
            changedPixelsPermille: -100
        )

        XCTAssertEqual(sample.durationMilliseconds, 0)
        XCTAssertEqual(sample.dirtyRectangleCount, 0)
        XCTAssertEqual(sample.dirtyAreaPermille, 1_000)
        XCTAssertEqual(sample.changedPixelsPermille, 0)
    }
}
