import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeStimulusModeTests: XCTestCase {
    func testUsageDescriptionListsSafeFixedModes() {
        XCTAssertEqual(
            BenchmarkStreamShapeStimulusMode.usageDescription,
            "off|external-command"
        )
    }

    func testExternalCommandRawValueIsStableForReports() {
        XCTAssertEqual(
            BenchmarkStreamShapeStimulusMode.externalCommand.rawValue,
            "external-command"
        )
    }
}
