import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeGatePresetTests: XCTestCase {
    func testRawValuesAreStableForCliContract() {
        XCTAssertEqual(BenchmarkStreamShapeGatePreset.none.rawValue, "none")
        XCTAssertEqual(BenchmarkStreamShapeGatePreset.sustainedV2Core.rawValue, "sustained-v2-core")
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2RequestResponse.rawValue,
            "sustained-v2-request-response"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2ZrleIsolation.rawValue,
            "sustained-v2-zrle-isolation"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2ZrleZeroDelay.rawValue,
            "sustained-v2-zrle-zero-delay"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2ZrlePacingSweep.rawValue,
            "sustained-v2-zrle-pacing-sweep"
        )
        XCTAssertEqual(BenchmarkStreamShapeGatePreset.sustainedV2PixelFormat.rawValue, "sustained-v2-pixel-format")
    }

    func testUsageDescriptionListsSupportedPresets() {
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.usageDescription,
            "none|sustained-v2-core|sustained-v2-request-response|"
                + "sustained-v2-zrle-isolation|sustained-v2-zrle-zero-delay|"
                + "sustained-v2-zrle-pacing-sweep|sustained-v2-pixel-format"
        )
    }
}
