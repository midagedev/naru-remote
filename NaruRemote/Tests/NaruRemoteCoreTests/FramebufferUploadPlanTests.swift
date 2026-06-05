import XCTest
@testable import NaruRemoteCore

final class FramebufferUploadPlanTests: XCTestCase {
    func testFirstOrRecreatedTextureUsesFullUpload() {
        let plan = FramebufferUploadPlan.plan(
            framebufferWidth: 100,
            framebufferHeight: 100,
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 10, height: 10)],
            requiresTextureRecreation: true
        )

        XCTAssertEqual(plan.strategy, .full)
        XCTAssertEqual(plan.uploadRegionCount, 1)
    }

    func testSmallValidDirtyRectsUsePartialUploads() {
        let plan = FramebufferUploadPlan.plan(
            framebufferWidth: 100,
            framebufferHeight: 100,
            dirtyRectangles: [
                RFBFrameDamageRect(x: 0, y: 0, width: 10, height: 10),
                RFBFrameDamageRect(x: 40, y: 40, width: 5, height: 5)
            ],
            requiresTextureRecreation: false
        )

        XCTAssertEqual(plan.strategy, .partial)
        XCTAssertEqual(plan.uploadRegionCount, 2)
    }

    func testLargeDirtyAreaFallsBackToFullUpload() {
        let plan = FramebufferUploadPlan.plan(
            framebufferWidth: 100,
            framebufferHeight: 100,
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 100, height: 70)],
            requiresTextureRecreation: false
        )

        XCTAssertEqual(plan.strategy, .full)
        XCTAssertEqual(plan.uploadRegionCount, 1)
    }

    func testSparseLargeDirtyAreaCanStillUsePartialUpload() {
        let plan = FramebufferUploadPlan.plan(
            framebufferWidth: 100,
            framebufferHeight: 100,
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 100, height: 70)],
            requiresTextureRecreation: false,
            changedPixelCount: 500
        )

        XCTAssertEqual(plan.strategy, .partial)
        XCTAssertEqual(plan.uploadRegionCount, 1)
    }

    func testSparseExceptionDoesNotCoverAlmostFullDirtyArea() {
        let plan = FramebufferUploadPlan.plan(
            framebufferWidth: 100,
            framebufferHeight: 100,
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 100, height: 90)],
            requiresTextureRecreation: false,
            changedPixelCount: 500
        )

        XCTAssertEqual(plan.strategy, .full)
        XCTAssertEqual(plan.uploadRegionCount, 1)
    }

    func testTooManyDirtyRectsFallBackToFullUpload() {
        let rects = (0...FramebufferUploadPlan.maximumPartialUploadRegionCount).map { index in
            RFBFrameDamageRect(x: index, y: 0, width: 1, height: 1)
        }
        let plan = FramebufferUploadPlan.plan(
            framebufferWidth: 100,
            framebufferHeight: 100,
            dirtyRectangles: rects,
            requiresTextureRecreation: false
        )

        XCTAssertEqual(plan.strategy, .full)
        XCTAssertEqual(plan.uploadRegionCount, 1)
    }

    func testNoUploadModeStaysNone() {
        let plan = FramebufferUploadPlan.plan(
            framebufferWidth: 100,
            framebufferHeight: 100,
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
            requiresTextureRecreation: false,
            shouldUpload: false
        )

        XCTAssertEqual(plan.strategy, .none)
        XCTAssertEqual(plan.uploadRegionCount, 0)
    }
}
