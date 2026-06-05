import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeGatePresetTests: XCTestCase {
    func testRawValuesAreStableForCliContract() {
        XCTAssertEqual(BenchmarkStreamShapeGatePreset.none.rawValue, "none")
        XCTAssertEqual(BenchmarkStreamShapeGatePreset.sustainedV2Core.rawValue, "sustained-v2-core")
        XCTAssertEqual(BenchmarkStreamShapeGatePreset.sustainedV2PixelFormat.rawValue, "sustained-v2-pixel-format")
    }

    func testUsageDescriptionListsSupportedPresets() {
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.usageDescription,
            "none|sustained-v2-core|sustained-v2-pixel-format"
        )
    }
}
