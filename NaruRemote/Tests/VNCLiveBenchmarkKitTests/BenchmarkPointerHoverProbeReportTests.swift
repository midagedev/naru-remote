import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkPointerHoverProbeReportTests: XCTestCase {
    func testObservedReportIncludesTimestampLatencySummaryOnly() throws {
        let report = BenchmarkPointerHoverProbeReport(
            status: .observedHover,
            networkConditionProfile: .constrainedCellular,
            connectStatus: .passed,
            firstFrameStatus: .passed,
            sendStatus: .passed,
            observationStatus: .observed,
            timestampLatency: BenchmarkLatencySummary([84, 120, 143]),
            failureLabel: nil
        )

        XCTAssertEqual(report.timestampLatencySampleCount, 3)
        XCTAssertEqual(report.timestampLatency?.p95Milliseconds, 143)

        let data = try JSONEncoder().encode(report)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"pointer-hover-observed-probe\""))
        XCTAssertTrue(json.contains("\"observed-hover\""))
        XCTAssertTrue(json.contains("\"constrained-cellular\""))
        XCTAssertTrue(json.contains("\"timestampLatency\""))
        XCTAssertFalse(json.contains("\"x\""))
        XCTAssertFalse(json.contains("\"y\""))
        XCTAssertFalse(json.contains("\"framebufferWidth\""))
        XCTAssertFalse(json.contains("\"framebufferHeight\""))
        XCTAssertFalse(json.contains("\"pixels\""))
        XCTAssertFalse(json.contains("sidecarPath"))
    }

    func testFailedReportKeepsStageAndObservationLabels() throws {
        let report = BenchmarkPointerHoverProbeReport(
            status: .failed,
            connectStatus: .passed,
            firstFrameStatus: .passed,
            sendStatus: .passed,
            observationStatus: .timedOut,
            failureLabel: "pointer-hover-observation-timed-out"
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(BenchmarkPointerHoverProbeReport.self, from: data)

        XCTAssertEqual(decoded.status, .failed)
        XCTAssertEqual(decoded.observationStatus, .timedOut)
        XCTAssertEqual(decoded.timestampLatencySampleCount, 0)
        XCTAssertEqual(decoded.failureLabel, "pointer-hover-observation-timed-out")
    }
}
