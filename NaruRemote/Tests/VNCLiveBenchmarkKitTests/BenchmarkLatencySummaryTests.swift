import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkLatencySummaryTests: XCTestCase {
    func testEmptySamplesReturnNil() {
        XCTAssertNil(BenchmarkLatencySummary([]))
    }

    func testSingleSamplePopulatesEveryStatistic() throws {
        let summary = try XCTUnwrap(BenchmarkLatencySummary([42]))

        XCTAssertEqual(summary.sampleCount, 1)
        XCTAssertEqual(summary.averageMilliseconds, 42)
        XCTAssertEqual(summary.minMilliseconds, 42)
        XCTAssertEqual(summary.p50Milliseconds, 42)
        XCTAssertEqual(summary.p95Milliseconds, 42)
        XCTAssertEqual(summary.maxMilliseconds, 42)
    }

    func testNearestRankPercentilesUseObservedSamples() throws {
        let summary = try XCTUnwrap(BenchmarkLatencySummary([40, 10, 30, 20]))

        XCTAssertEqual(summary.sampleCount, 4)
        XCTAssertEqual(summary.averageMilliseconds, 25)
        XCTAssertEqual(summary.minMilliseconds, 10)
        XCTAssertEqual(summary.p50Milliseconds, 20)
        XCTAssertEqual(summary.p95Milliseconds, 40)
        XCTAssertEqual(summary.maxMilliseconds, 40)
        XCTAssertEqual(summary.averageValue, 25)
        XCTAssertEqual(summary.minValue, 10)
        XCTAssertEqual(summary.p50Value, 20)
        XCTAssertEqual(summary.p95Value, 40)
        XCTAssertEqual(summary.maxValue, 40)
    }

    func testNinetyFifthPercentileHighlightsTailLatency() throws {
        let summary = try XCTUnwrap(BenchmarkLatencySummary([8, 9, 10, 11, 12, 13, 300]))

        XCTAssertEqual(summary.p50Milliseconds, 11)
        XCTAssertEqual(summary.p95Milliseconds, 300)
    }
}
