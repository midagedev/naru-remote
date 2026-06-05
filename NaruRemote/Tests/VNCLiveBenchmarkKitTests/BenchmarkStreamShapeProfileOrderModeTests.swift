import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeProfileOrderModeTests: XCTestCase {
    func testUsageDescriptionListsStableModes() {
        XCTAssertEqual(
            BenchmarkStreamShapeProfileOrderMode.usageDescription,
            "fixed|rotate"
        )
    }

    func testRawValuesAreStableForReports() {
        XCTAssertEqual(BenchmarkStreamShapeProfileOrderMode.fixed.rawValue, "fixed")
        XCTAssertEqual(BenchmarkStreamShapeProfileOrderMode.rotate.rawValue, "rotate")
    }
}
