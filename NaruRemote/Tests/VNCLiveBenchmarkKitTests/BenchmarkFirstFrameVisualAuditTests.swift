import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkFirstFrameVisualAuditTests: XCTestCase {
    func testDefaultScaleReportsCentralContextCoverage() {
        let audit = BenchmarkFirstFrameVisualAudit(scale: 0.45)

        XCTAssertEqual(audit.model, "synthetic-terminal-grid")
        XCTAssertEqual(audit.scalePermille, 450)
        XCTAssertEqual(audit.visibleCoreAxisCoveragePermille, 450)
        XCTAssertEqual(audit.visibleCoreAreaCoveragePermille, 203)
        XCTAssertEqual(audit.omittedVisibleCoreAreaPermille, 797)
        XCTAssertEqual(audit.riskLabel, .centralContext)
        XCTAssertFalse(audit.visualCheckRequired)
    }

    func testSmallScaleRequiresVisualCheckBeforeDefaultPromotion() {
        let audit = BenchmarkFirstFrameVisualAudit(scale: 0.25)

        XCTAssertEqual(audit.scalePermille, 250)
        XCTAssertEqual(audit.visibleCoreAxisCoveragePermille, 250)
        XCTAssertEqual(audit.visibleCoreAreaCoveragePermille, 63)
        XCTAssertEqual(audit.riskLabel, .glanceOnly)
        XCTAssertTrue(audit.visualCheckRequired)
    }

    func testScaleClampsBeforeVisualAuditClassification() {
        let minimum = BenchmarkFirstFrameVisualAudit(scale: 0.01)
        let maximum = BenchmarkFirstFrameVisualAudit(scale: 2.0)

        XCTAssertEqual(minimum.scalePermille, 100)
        XCTAssertEqual(minimum.visibleCoreAreaCoveragePermille, 10)
        XCTAssertEqual(minimum.riskLabel, .glanceOnly)
        XCTAssertEqual(maximum.scalePermille, 1_000)
        XCTAssertEqual(maximum.visibleCoreAreaCoveragePermille, 1_000)
        XCTAssertEqual(maximum.riskLabel, .broadContext)
    }

    func testIntermediateRiskLabelsAreStable() {
        XCTAssertEqual(BenchmarkFirstFrameVisualAudit(scale: 0.35).riskLabel, .minimalContext)
        XCTAssertEqual(BenchmarkFirstFrameVisualAudit(scale: 0.70).riskLabel, .broadContext)
    }

    func testJSONUsesFixedLabelsAndPermilleOnly() throws {
        let data = try JSONEncoder().encode(BenchmarkFirstFrameVisualAudit(scale: 0.25))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("synthetic-terminal-grid"))
        XCTAssertTrue(json.contains("glance-only"))
        XCTAssertTrue(json.contains("\"scalePermille\":250"))
        XCTAssertFalse(json.contains("\"width\""))
        XCTAssertFalse(json.contains("\"height\""))
        XCTAssertFalse(json.contains("\"x\""))
        XCTAssertFalse(json.contains("\"y\""))
    }
}
