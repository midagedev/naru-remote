import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeRequestRegionTests: XCTestCase {
    func testRawValuesAreStableForReports() {
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.full.rawValue, "full")
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.centerHalf.rawValue, "center-half")
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.centerThird.rawValue, "center-third")
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.usageDescription,
            "full|center-half|center-third"
        )
    }

    func testRequestRegionSweepUsesFixedCandidateLabels() {
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.requestRegionSweep,
            [.full, .centerHalf, .centerThird]
        )
    }

    func testFullRegionMapsToNilRequestRegion() {
        XCTAssertNil(BenchmarkStreamShapeRequestRegion.full.region(width: 1920, height: 1080))
    }

    func testCenterHalfBuildsCenteredFramebufferRegion() throws {
        let region = try XCTUnwrap(BenchmarkStreamShapeRequestRegion.centerHalf.region(width: 1920, height: 1080))

        XCTAssertEqual(region.x, 480)
        XCTAssertEqual(region.y, 270)
        XCTAssertEqual(region.width, 960)
        XCTAssertEqual(region.height, 540)
    }

    func testCenterThirdBuildsCenteredFramebufferRegion() throws {
        let region = try XCTUnwrap(BenchmarkStreamShapeRequestRegion.centerThird.region(width: 1920, height: 1080))

        XCTAssertEqual(region.x, 640)
        XCTAssertEqual(region.y, 360)
        XCTAssertEqual(region.width, 640)
        XCTAssertEqual(region.height, 360)
    }

    func testTinyFramebufferKeepsNonZeroRegion() throws {
        let region = try XCTUnwrap(BenchmarkStreamShapeRequestRegion.centerThird.region(width: 1, height: 1))

        XCTAssertEqual(region.x, 0)
        XCTAssertEqual(region.y, 0)
        XCTAssertEqual(region.width, 1)
        XCTAssertEqual(region.height, 1)
    }
}
