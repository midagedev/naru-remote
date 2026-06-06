import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeFirstFrameRequestModeTests: XCTestCase {
    func testRawValuesAreStableForReports() {
        XCTAssertEqual(BenchmarkStreamShapeFirstFrameRequestMode.full.rawValue, "full")
        XCTAssertEqual(
            BenchmarkStreamShapeFirstFrameRequestMode.matchRequestRegion.rawValue,
            "match-request-region"
        )
        XCTAssertEqual(BenchmarkStreamShapeFirstFrameRequestMode.visibleCore.rawValue, "visible-core")
        XCTAssertEqual(BenchmarkStreamShapeFirstFrameRequestMode.visibleFocus.rawValue, "visible-focus")
        XCTAssertEqual(BenchmarkStreamShapeFirstFrameRequestMode.visibleGlance.rawValue, "visible-glance")
        XCTAssertEqual(
            BenchmarkStreamShapeFirstFrameRequestMode.usageDescription,
            "full|match-request-region|visible-core|visible-focus|visible-glance"
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

    func testVisibleCoreInitialRequestUsesSmallerFixedVisibleCore() throws {
        let matchedRegion = try XCTUnwrap(
            BenchmarkStreamShapeFirstFrameRequestMode.matchRequestRegion.initialRegion(
                matching: .viewportPhonePortrait,
                framebufferWidth: 1920,
                framebufferHeight: 1080
            )
        )
        let coreRegion = try XCTUnwrap(
            BenchmarkStreamShapeFirstFrameRequestMode.visibleCore.initialRegion(
                matching: .viewportPhonePortrait,
                framebufferWidth: 1920,
                framebufferHeight: 1080
            )
        )

        XCTAssertEqual(coreRegion.y, 0)
        XCTAssertEqual(coreRegion.height, 1080)
        XCTAssertGreaterThan(coreRegion.x, matchedRegion.x)
        XCTAssertLessThan(coreRegion.width, matchedRegion.width)
    }

    func testFirstFrameRequestAreaPermilleReflectsMode() {
        let matchedArea = BenchmarkStreamShapeFirstFrameRequestMode.matchRequestRegion.requestAreaPermille(
            matching: .viewportPhonePortrait,
            framebufferWidth: 1920,
            framebufferHeight: 1080
        )
        let coreArea = BenchmarkStreamShapeFirstFrameRequestMode.visibleCore.requestAreaPermille(
            matching: .viewportPhonePortrait,
            framebufferWidth: 1920,
            framebufferHeight: 1080
        )
        let focusArea = BenchmarkStreamShapeFirstFrameRequestMode.visibleFocus.requestAreaPermille(
            matching: .viewportPhonePortrait,
            framebufferWidth: 1920,
            framebufferHeight: 1080
        )
        let glanceArea = BenchmarkStreamShapeFirstFrameRequestMode.visibleGlance.requestAreaPermille(
            matching: .viewportPhonePortrait,
            framebufferWidth: 1920,
            framebufferHeight: 1080
        )

        XCTAssertEqual(
            BenchmarkStreamShapeFirstFrameRequestMode.full.requestAreaPermille(
                matching: .viewportPhonePortrait,
                framebufferWidth: 1920,
                framebufferHeight: 1080
            ),
            1_000
        )
        XCTAssertEqual(
            matchedArea,
            BenchmarkStreamShapeRequestRegion.viewportPhonePortrait.requestAreaPermille(width: 1920, height: 1080)
        )
        XCTAssertGreaterThan(coreArea, 0)
        XCTAssertLessThan(coreArea, matchedArea)
        XCTAssertGreaterThan(focusArea, 0)
        XCTAssertLessThan(focusArea, coreArea)
        XCTAssertGreaterThan(glanceArea, 0)
        XCTAssertLessThan(glanceArea, focusArea)
    }

    func testVisibleFocusInitialRequestUsesSmallerCentralFocusArea() throws {
        let coreRegion = try XCTUnwrap(
            BenchmarkStreamShapeFirstFrameRequestMode.visibleCore.initialRegion(
                matching: .viewportPhonePortrait,
                framebufferWidth: 1920,
                framebufferHeight: 1080
            )
        )
        let focusRegion = try XCTUnwrap(
            BenchmarkStreamShapeFirstFrameRequestMode.visibleFocus.initialRegion(
                matching: .viewportPhonePortrait,
                framebufferWidth: 1920,
                framebufferHeight: 1080
            )
        )

        XCTAssertGreaterThan(focusRegion.x, coreRegion.x)
        XCTAssertGreaterThan(focusRegion.y, coreRegion.y)
        XCTAssertLessThan(focusRegion.width, coreRegion.width)
        XCTAssertLessThan(focusRegion.height, coreRegion.height)
    }

    func testVisibleGlanceInitialRequestUsesSmallerCentralGlanceArea() throws {
        let focusRegion = try XCTUnwrap(
            BenchmarkStreamShapeFirstFrameRequestMode.visibleFocus.initialRegion(
                matching: .viewportPhonePortrait,
                framebufferWidth: 1920,
                framebufferHeight: 1080
            )
        )
        let glanceRegion = try XCTUnwrap(
            BenchmarkStreamShapeFirstFrameRequestMode.visibleGlance.initialRegion(
                matching: .viewportPhonePortrait,
                framebufferWidth: 1920,
                framebufferHeight: 1080
            )
        )

        XCTAssertGreaterThan(glanceRegion.x, focusRegion.x)
        XCTAssertGreaterThan(glanceRegion.y, focusRegion.y)
        XCTAssertLessThan(glanceRegion.width, focusRegion.width)
        XCTAssertLessThan(glanceRegion.height, focusRegion.height)
    }

    func testVisibleGlanceInitialRequestUsesScaleOverride() throws {
        let defaultRegion = try XCTUnwrap(
            BenchmarkStreamShapeFirstFrameRequestMode.visibleGlance.initialRegion(
                matching: .viewportPhonePortrait,
                framebufferWidth: 1920,
                framebufferHeight: 1080
            )
        )
        let smallerRegion = try XCTUnwrap(
            BenchmarkStreamShapeFirstFrameRequestMode.visibleGlance.initialRegion(
                matching: .viewportPhonePortrait,
                framebufferWidth: 1920,
                framebufferHeight: 1080,
                visibleGlanceScale: 0.35
            )
        )
        let defaultArea = BenchmarkStreamShapeFirstFrameRequestMode.visibleGlance.requestAreaPermille(
            matching: .viewportPhonePortrait,
            framebufferWidth: 1920,
            framebufferHeight: 1080
        )
        let smallerArea = BenchmarkStreamShapeFirstFrameRequestMode.visibleGlance.requestAreaPermille(
            matching: .viewportPhonePortrait,
            framebufferWidth: 1920,
            framebufferHeight: 1080,
            visibleGlanceScale: 0.35
        )

        XCTAssertGreaterThan(smallerRegion.x, defaultRegion.x)
        XCTAssertGreaterThan(smallerRegion.y, defaultRegion.y)
        XCTAssertLessThan(smallerRegion.width, defaultRegion.width)
        XCTAssertLessThan(smallerRegion.height, defaultRegion.height)
        XCTAssertLessThan(smallerArea, defaultArea)
    }
}
