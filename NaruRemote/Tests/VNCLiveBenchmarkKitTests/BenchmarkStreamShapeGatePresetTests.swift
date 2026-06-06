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
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2ZrleRegionSweep.rawValue,
            "sustained-v2-zrle-region-sweep"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2ZrleViewportRegion.rawValue,
            "sustained-v2-zrle-viewport-region"
        )
        XCTAssertEqual(BenchmarkStreamShapeGatePreset.sustainedV2PixelFormat.rawValue, "sustained-v2-pixel-format")
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2ConstrainedCellularBootstrap.rawValue,
            "sustained-v2-constrained-cellular-bootstrap"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2ConstrainedCellularVisibleStartup.rawValue,
            "sustained-v2-constrained-cellular-visible-startup"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2ConstrainedCellularVisibleCoreStartup.rawValue,
            "sustained-v2-constrained-cellular-visible-core-startup"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2ConstrainedCellularVisibleFocusStartup.rawValue,
            "sustained-v2-constrained-cellular-visible-focus-startup"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.sustainedV2ConstrainedCellularAppLowTraffic.rawValue,
            "sustained-v2-constrained-cellular-app-low-traffic"
        )
    }

    func testUsageDescriptionListsSupportedPresets() {
        XCTAssertEqual(
            BenchmarkStreamShapeGatePreset.usageDescription,
            "none|sustained-v2-core|sustained-v2-request-response|"
                + "sustained-v2-zrle-isolation|sustained-v2-zrle-zero-delay|"
                + "sustained-v2-zrle-pacing-sweep|sustained-v2-zrle-region-sweep|"
                + "sustained-v2-zrle-viewport-region|sustained-v2-pixel-format|"
                + "sustained-v2-constrained-cellular-bootstrap|"
                + "sustained-v2-constrained-cellular-visible-startup|"
                + "sustained-v2-constrained-cellular-visible-core-startup|"
                + "sustained-v2-constrained-cellular-visible-focus-startup|"
                + "sustained-v2-constrained-cellular-app-low-traffic"
        )
    }
}
