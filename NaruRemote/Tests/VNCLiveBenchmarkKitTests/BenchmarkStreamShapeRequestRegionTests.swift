import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeRequestRegionTests: XCTestCase {
    func testRawValuesAreStableForReports() {
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.full.rawValue, "full")
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.centerHalf.rawValue, "center-half")
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.centerThird.rawValue, "center-third")
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.rawValue,
            "viewport-phone-portrait"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.viewportPhonePortraitHeartbeat.rawValue,
            "viewport-phone-portrait-heartbeat"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.usageDescription,
            "full|center-half|center-third|viewport-phone-portrait|viewport-phone-portrait-heartbeat"
        )
    }

    func testRequestRegionSweepUsesFixedCandidateLabels() {
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.requestRegionSweep,
            [.full, .centerHalf, .centerThird]
        )
    }

    func testViewportRequestRegionSweepUsesFixedCandidateLabels() {
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.viewportRequestRegionSweep,
            [.full, .viewportPhonePortrait, .viewportPhonePortraitHeartbeat]
        )
    }

    func testOnlyViewportRegionsAllowTimeoutFullFallback() {
        XCTAssertFalse(BenchmarkStreamShapeRequestRegion.full.allowsRegionTimeoutFullFallback)
        XCTAssertFalse(BenchmarkStreamShapeRequestRegion.centerHalf.allowsRegionTimeoutFullFallback)
        XCTAssertFalse(BenchmarkStreamShapeRequestRegion.centerThird.allowsRegionTimeoutFullFallback)
        XCTAssertTrue(BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.allowsRegionTimeoutFullFallback)
        XCTAssertTrue(BenchmarkStreamShapeRequestRegion.viewportPhonePortraitHeartbeat.allowsRegionTimeoutFullFallback)
    }

    func testFullRegionMapsToNilRequestRegion() {
        XCTAssertNil(BenchmarkStreamShapeRequestRegion.full.region(width: 1920, height: 1080))
    }

    func testRequestAreaPermilleUsesSafeFramebufferRelativeRatios() {
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.full.requestAreaPermille(width: 1920, height: 1080), 1_000)
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.centerHalf.requestAreaPermille(width: 1920, height: 1080), 250)
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.centerThird.requestAreaPermille(width: 1920, height: 1080), 111)
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.centerHalf.requestAreaPermille(width: 0, height: 1080), 1_000)
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

    func testViewportPhonePortraitBuildsVisibleRegionShape() throws {
        let region = try XCTUnwrap(
            BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.region(
                width: 1920,
                height: 1080
            )
        )

        XCTAssertEqual(region.y, 0)
        XCTAssertEqual(region.height, 1080)
        XCTAssertGreaterThan(region.x, 0)
        XCTAssertLessThan(Int(region.width), 1920)
    }

    func testViewportRequestAreaPermilleReflectsPhonePortraitCropFill() {
        let viewportArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.requestAreaPermille(
            width: 1920,
            height: 1080
        )
        let heartbeatArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortraitHeartbeat.requestAreaPermille(
            width: 1920,
            height: 1080
        )

        XCTAssertGreaterThan(viewportArea, 0)
        XCTAssertLessThan(viewportArea, 1_000)
        XCTAssertGreaterThan(heartbeatArea, viewportArea)
        XCTAssertLessThan(heartbeatArea, 1_000)
    }

    func testFirstFrameVisibleCoreAreaIsSmallerThanMarginExpandedViewport() {
        let expandedArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.requestAreaPermille(
            width: 1920,
            height: 1080
        )
        let coreArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleCoreAreaPermille(
            width: 1920,
            height: 1080
        )

        XCTAssertGreaterThan(coreArea, 0)
        XCTAssertLessThan(coreArea, expandedArea)
    }

    func testFirstFrameVisibleFocusAreaIsSmallerThanCore() {
        let coreArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleCoreAreaPermille(
            width: 1920,
            height: 1080
        )
        let focusArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleFocusAreaPermille(
            width: 1920,
            height: 1080
        )

        XCTAssertGreaterThan(focusArea, 0)
        XCTAssertLessThan(focusArea, coreArea)
    }

    func testFirstFrameVisibleGlanceAreaIsSmallerThanFocus() {
        let focusArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleFocusAreaPermille(
            width: 1920,
            height: 1080
        )
        let glanceArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleGlanceAreaPermille(
            width: 1920,
            height: 1080
        )

        XCTAssertGreaterThan(glanceArea, 0)
        XCTAssertLessThan(glanceArea, focusArea)
    }

    func testFirstFrameVisibleGlanceScalePermilleClampsSafeRange() {
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.firstFrameVisibleGlanceScalePermille(
                BenchmarkStreamShapeRequestRegion.defaultFirstFrameVisibleGlanceScale
            ),
            450
        )
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.firstFrameVisibleGlanceScalePermille(0.35), 350)
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.firstFrameVisibleGlanceScalePermille(0.01), 100)
        XCTAssertEqual(BenchmarkStreamShapeRequestRegion.firstFrameVisibleGlanceScalePermille(1.50), 1_000)
    }

    func testFirstFrameVisibleGlanceAreaUsesBenchmarkScaleOverride() {
        let defaultArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleGlanceAreaPermille(
            width: 1920,
            height: 1080
        )
        let smallerArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleGlanceAreaPermille(
            width: 1920,
            height: 1080,
            scale: 0.35
        )
        let coreArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleCoreAreaPermille(
            width: 1920,
            height: 1080
        )
        let fullScaleArea = BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleGlanceAreaPermille(
            width: 1920,
            height: 1080,
            scale: 1.0
        )

        XCTAssertLessThan(smallerArea, defaultArea)
        XCTAssertEqual(fullScaleArea, coreArea)
    }

    func testFirstFrameVisibleCoreIgnoresHeartbeatEscalation() {
        XCTAssertNotNil(
            BenchmarkStreamShapeRequestRegion.viewportPhonePortraitHeartbeat.firstFrameVisibleCoreRegion(
                width: 1920,
                height: 1080
            )
        )
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.viewportPhonePortraitHeartbeat.firstFrameVisibleCoreAreaPermille(
                width: 1920,
                height: 1080
            ),
            BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleCoreAreaPermille(
                width: 1920,
                height: 1080
            )
        )
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.viewportPhonePortraitHeartbeat.firstFrameVisibleFocusAreaPermille(
                width: 1920,
                height: 1080
            ),
            BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleFocusAreaPermille(
                width: 1920,
                height: 1080
            )
        )
        XCTAssertEqual(
            BenchmarkStreamShapeRequestRegion.viewportPhonePortraitHeartbeat.firstFrameVisibleGlanceAreaPermille(
                width: 1920,
                height: 1080
            ),
            BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.firstFrameVisibleGlanceAreaPermille(
                width: 1920,
                height: 1080
            )
        )
    }

    func testViewportPhonePortraitHeartbeatUsesFullRequestPeriodically() throws {
        XCTAssertNotNil(
            BenchmarkStreamShapeRequestRegion.viewportPhonePortraitHeartbeat.region(
                width: 1920,
                height: 1080,
                incrementalRequestIndex: 1
            )
        )
        XCTAssertNil(
            BenchmarkStreamShapeRequestRegion.viewportPhonePortraitHeartbeat.region(
                width: 1920,
                height: 1080,
                incrementalRequestIndex: 5
            )
        )
    }

    func testViewportPhonePortraitFallsBackToFullAfterRegionTimeout() {
        XCTAssertNil(
            BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.region(
                width: 1920,
                height: 1080,
                incrementalRequestIndex: 2,
                regionTimeoutStreak: 1
            )
        )
    }
}
