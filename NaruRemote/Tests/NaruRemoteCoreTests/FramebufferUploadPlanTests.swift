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

    /// Contract changed 2026-08-21 (spec 024). This case used to assert that
    /// exceeding the region cap falls back to a full upload; live measurement
    /// showed that is what re-uploaded the whole framebuffer for frames whose
    /// damage was under 1% of it (rectangle count peaked at 112 while damage
    /// averaged 0.5%). Exceeding the cap now merges, and only a genuinely large
    /// merged area falls back — `testMergedDamageSpanningTheScreenStillFallsBackToFullUpload`
    /// keeps that escape hatch pinned.
    func testTooManyDirtyRectsAreMergedInsteadOfForcingAFullUpload() {
        let rects = (0...FramebufferUploadPlan.maximumPartialUploadRegionCount).map { index in
            RFBFrameDamageRect(x: index, y: 0, width: 1, height: 1)
        }
        let plan = FramebufferUploadPlan.plan(
            framebufferWidth: 100,
            framebufferHeight: 100,
            dirtyRectangles: rects,
            requiresTextureRecreation: false
        )

        XCTAssertEqual(plan.strategy, .partial)
        XCTAssertLessThanOrEqual(
            plan.uploadRegionCount,
            FramebufferUploadPlan.maximumPartialUploadRegionCount
        )
        XCTAssertGreaterThan(plan.uploadRegionCount, 0)
    }

    func testMergedRegionsCoverEveryOriginalDirtyRectangle() {
        // Two tight clusters far apart — the shape that must not lose a pixel
        // when it is merged down to the cap.
        var rects: [RFBFrameDamageRect] = []
        for index in 0..<40 {
            rects.append(RFBFrameDamageRect(x: index * 2, y: 4, width: 2, height: 2))
            rects.append(RFBFrameDamageRect(x: 400 + index * 2, y: 900, width: 2, height: 2))
        }

        let regions = FramebufferUploadPlan.uploadRegions(
            rects,
            textureWidth: 1512,
            textureHeight: 982
        )

        XCTAssertLessThanOrEqual(
            regions.count,
            FramebufferUploadPlan.maximumPartialUploadRegionCount
        )
        for rect in rects {
            let covered = regions.contains { region in
                region.x <= rect.x
                    && region.y <= rect.y
                    && region.x + region.width >= rect.x + rect.width
                    && region.y + region.height >= rect.y + rect.height
            }
            XCTAssertTrue(covered, "A merged region set must cover every original rectangle")
        }
    }

    func testMergingStaysCheapForFarApartDamageInsteadOfSpanningTheScreen() {
        // 80 small rectangles on two distant rows. Merging must join same-row
        // neighbours (nearly free) rather than bridging the rows (which would
        // sweep the whole screen into the upload).
        var rects: [RFBFrameDamageRect] = []
        for index in 0..<40 {
            rects.append(RFBFrameDamageRect(x: index * 4, y: 0, width: 2, height: 2))
            rects.append(RFBFrameDamageRect(x: index * 4, y: 970, width: 2, height: 2))
        }

        let regions = FramebufferUploadPlan.uploadRegions(
            rects,
            textureWidth: 1512,
            textureHeight: 982
        )
        let mergedFraction = FramebufferUploadPlan.dirtyAreaFraction(
            regions,
            textureWidth: 1512,
            textureHeight: 982
        )

        XCTAssertLessThan(
            mergedFraction,
            0.05,
            "Least-added-area merging must not bridge distant damage into a screen-sized region"
        )
    }

    func testMergedDamageSpanningTheScreenStillFallsBackToFullUpload() {
        // 100 wide bands covering most of the framebuffer: this really is a
        // repaint, and the area guard must still choose one full upload.
        let rects = (0..<100).map { index in
            RFBFrameDamageRect(x: 0, y: index * 9, width: 1512, height: 9)
        }
        let plan = FramebufferUploadPlan.plan(
            framebufferWidth: 1512,
            framebufferHeight: 982,
            dirtyRectangles: rects,
            requiresTextureRecreation: false
        )

        XCTAssertEqual(plan.strategy, .full)
        XCTAssertEqual(plan.uploadRegionCount, 1)
    }

    /// Complexity gate, not a speed contest. The merge runs on every content
    /// frame, so an accidental return to all-pairs greedy (cubic in the
    /// rectangle count) would cost tens of millions of comparisons per frame at
    /// this input ceiling — worse than the full upload it exists to avoid. The
    /// budget is deliberately loose: the raster-neighbour merge does this in
    /// well under a millisecond, while a cubic version needs seconds.
    func testWorstCaseMergeStaysWithinAPerFrameBudget() {
        let rects = (0..<FramebufferUploadPlan.maximumCoalescingInputCount).map { index in
            RFBFrameDamageRect(x: (index * 7) % 1400, y: (index * 13) % 900, width: 6, height: 6)
        }

        let startedAt = ContinuousClock.now
        let regions = FramebufferUploadPlan.uploadRegions(
            rects,
            textureWidth: 1512,
            textureHeight: 982
        )
        let elapsed = ContinuousClock.now - startedAt

        XCTAssertLessThanOrEqual(
            regions.count,
            FramebufferUploadPlan.maximumPartialUploadRegionCount
        )
        XCTAssertLessThan(
            elapsed,
            .milliseconds(200),
            "The per-frame merge must not be superquadratic in the rectangle count"
        )
    }

    func testAbsurdRectangleCountSkipsMergingAndFallsBackToFullUpload() {
        let rects = (0...FramebufferUploadPlan.maximumCoalescingInputCount).map { index in
            RFBFrameDamageRect(x: index % 1500, y: index / 1500, width: 1, height: 1)
        }
        let plan = FramebufferUploadPlan.plan(
            framebufferWidth: 1512,
            framebufferHeight: 982,
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
