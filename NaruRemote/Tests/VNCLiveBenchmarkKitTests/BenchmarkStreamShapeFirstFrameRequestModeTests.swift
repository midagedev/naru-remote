import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeFirstFrameRequestModeTests: XCTestCase {
    func testRawValuesAreStableForReports() {
        XCTAssertEqual(BenchmarkStreamShapeFirstFrameRequestMode.full.rawValue, "full")
        XCTAssertEqual(
            BenchmarkStreamShapeFirstFrameRequestMode.matchRequestRegion.rawValue,
            "match-request-region"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeFirstFrameRequestMode.usageDescription,
            "full|match-request-region"
        )
    }

    func testFullInitialRequestModeKeepsFullFrameRequest() {
        XCTAssertNil(
            BenchmarkStreamShapeFirstFrameRequestMode.full.initialRegion(
                matching: .viewportPhonePortrait,
                framebufferWidth: 1920,
                framebufferHeight: 1080
            )
        )
    }

    func testMatchRequestRegionUsesFixedRequestRegionShape() {
        let region = BenchmarkStreamShapeFirstFrameRequestMode.matchRequestRegion.initialRegion(
            matching: .viewportPhonePortrait,
            framebufferWidth: 1920,
            framebufferHeight: 1080
        )

        XCTAssertEqual(
            region,
            BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.region(width: 1920, height: 1080)
        )
    }
}
