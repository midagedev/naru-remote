import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkFirstFrameProfileSelectionTests: XCTestCase {
    func testAllSelectsEveryProfileLabelInOrder() {
        XCTAssertEqual(
            BenchmarkFirstFrameProfileSelection.all.selectedLabels(
                allProfileLabels: ["local-low-latency", "tight-first", "zrle-first"],
                streamShapeProfileLabels: ["local-low-latency"]
            ),
            ["local-low-latency", "tight-first", "zrle-first"]
        )
    }

    func testLocalLowLatencySelectsOnlyLocalLabel() {
        XCTAssertEqual(
            BenchmarkFirstFrameProfileSelection.localLowLatency.selectedLabels(
                allProfileLabels: ["tight-first", "local-low-latency", "zrle-first"],
                streamShapeProfileLabels: ["tight-first"]
            ),
            ["local-low-latency"]
        )
    }

    func testStreamShapeProfilesFollowsStreamShapeSelection() {
        XCTAssertEqual(
            BenchmarkFirstFrameProfileSelection.streamShapeProfiles.selectedLabels(
                allProfileLabels: ["local-low-latency", "tight-first", "zrle-first"],
                streamShapeProfileLabels: ["zrle-first", "tight-first", "zrle-first"]
            ),
            ["zrle-first", "tight-first"]
        )
    }

    func testNoneSkipsFirstFrameProfileSweep() {
        XCTAssertEqual(
            BenchmarkFirstFrameProfileSelection.none.selectedLabels(
                allProfileLabels: ["local-low-latency", "tight-first"],
                streamShapeProfileLabels: ["local-low-latency"]
            ),
            []
        )
    }
}
