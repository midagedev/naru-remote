import CoreGraphics
import XCTest
@testable import NaruRemoteCore

final class ViewportTransformTests: XCTestCase {
    private let fb = CGSize(width: 1920, height: 1080)
    private let portrait = CGSize(width: 390, height: 844)
    /// A 16:9 view so a wide framebuffer fills it exactly at fit — any
    /// zoom > 1 overflows both axes, letting us assert anchor-fixing in
    /// both dimensions.
    private let sixteenByNine = CGSize(width: 320, height: 180)

    func testFitScaleFitsWidthForWideFramebufferInPortrait() {
        let transform = ViewportTransform(framebufferSize: fb, viewSize: portrait)
        XCTAssertEqual(transform.fitScale, 390.0 / 1920.0, accuracy: 1e-6)
        XCTAssertEqual(transform.contentSize.width, 390, accuracy: 1e-3)
        XCTAssertEqual(transform.contentSize.height, 1080 * (390.0 / 1920.0), accuracy: 1e-3)
    }

    func testViewToFramebufferRoundTrip() {
        let transform = ViewportTransform(framebufferSize: fb, viewSize: portrait)
        let fbPoint = CGPoint(x: 800, y: 450)
        let viewPoint = transform.viewPoint(fromFramebufferPoint: fbPoint)
        let back = transform.framebufferPoint(fromViewPoint: viewPoint)
        XCTAssertNotNil(back)
        XCTAssertEqual(back?.x ?? -1, 800, accuracy: 1e-3)
        XCTAssertEqual(back?.y ?? -1, 450, accuracy: 1e-3)
    }

    func testLetterboxBandMapsToNil() {
        let transform = ViewportTransform(framebufferSize: fb, viewSize: portrait)
        // Content is centered vertically (~219pt tall in an 844pt view),
        // so a point near the top edge is in the letterbox band.
        XCTAssertNil(transform.framebufferPoint(fromViewPoint: CGPoint(x: 195, y: 5)))
    }

    func testPanIsClampedToZeroWhenNotZoomed() {
        let transform = ViewportTransform(
            framebufferSize: fb,
            viewSize: portrait,
            zoomScale: 1,
            panOffset: CGSize(width: 500, height: 500)
        )
        XCTAssertEqual(transform.panOffset.width, 0, accuracy: 1e-6)
        XCTAssertEqual(transform.panOffset.height, 0, accuracy: 1e-6)
    }

    func testPannableIsFalseWhenFitContentStaysInsideViewport() {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1000, height: 500),
            viewSize: CGSize(width: 1000, height: 500)
        )

        XCTAssertFalse(transform.isPannable)
    }

    func testPannableIsTrueWhenZoomedContentExceedsViewport() {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1000, height: 500),
            viewSize: CGSize(width: 1000, height: 500),
            zoomScale: 2
        )

        XCTAssertTrue(transform.isPannable)
    }

    func testPannableIsTrueForCropFillScaleInPortrait() {
        let fit = ViewportTransform(framebufferSize: fb, viewSize: portrait)
        let fillZoom = portrait.height / fit.contentSize.height
        let transform = ViewportTransform(
            framebufferSize: fb,
            viewSize: portrait,
            zoomScale: fillZoom
        )

        XCTAssertTrue(transform.isPannable)
        XCTAssertGreaterThan(transform.contentSize.width, portrait.width)
    }

    func testPanClampedToContentBoundsWhenZoomed() {
        let base = ViewportTransform(framebufferSize: fb, viewSize: portrait)
        let zoomed = base.zoomed(to: 2, about: CGPoint(x: 195, y: 422))
        let panned = zoomed.panned(by: CGSize(width: 10_000, height: 0))
        let maxX = (zoomed.contentSize.width - portrait.width) / 2
        XCTAssertEqual(panned.panOffset.width, maxX, accuracy: 1e-3)
    }

    // MARK: - Vertical breathing band (spec 023 FR-003..FR-005)

    func testZoomedVerticalPanReachesPastFlushByTheBreathingBand() {
        let square = CGSize(width: 1000, height: 500)
        let transform = ViewportTransform(
            framebufferSize: square,
            viewSize: square,
            zoomScale: 2,
            panOffset: CGSize(width: 0, height: 10_000)
        )
        let flushMaxY = (transform.contentSize.height - square.height) / 2
        let band = ViewportTransform.verticalPanBand(viewSize: square)

        XCTAssertEqual(band, 80, accuracy: 1e-6) // 500 * 0.16, under the 96 cap
        XCTAssertEqual(transform.verticalPanBand, band, accuracy: 1e-6)
        XCTAssertEqual(transform.panOffset.height, flushMaxY + band, accuracy: 1e-3)
    }

    func testVerticalBandIsSymmetricSoTheTopRowClearsChromeToo() {
        let square = CGSize(width: 1000, height: 500)
        let transform = ViewportTransform(
            framebufferSize: square,
            viewSize: square,
            zoomScale: 2,
            panOffset: CGSize(width: 0, height: -10_000)
        )
        let flushMaxY = (transform.contentSize.height - square.height) / 2

        XCTAssertEqual(
            transform.panOffset.height,
            -(flushMaxY + ViewportTransform.verticalPanBand(viewSize: square)),
            accuracy: 1e-3
        )
    }

    func testHorizontalPanStaysFlushWhileTheVerticalBandApplies() {
        let square = CGSize(width: 1000, height: 500)
        let transform = ViewportTransform(
            framebufferSize: square,
            viewSize: square,
            zoomScale: 2,
            panOffset: CGSize(width: 10_000, height: 10_000)
        )

        XCTAssertEqual(
            transform.panOffset.width,
            (transform.contentSize.width - square.width) / 2,
            accuracy: 1e-3
        )
        XCTAssertGreaterThan(transform.verticalPanBand, 0)
    }

    func testNoVerticalBandWhileTheContentStillFitsVertically() {
        // A wide desktop in portrait is letterboxed: at fit — and at any zoom
        // that keeps the content shorter than the view — the bands already are
        // the breathing room, so pan must stay locked at zero (FR-004).
        let fit = ViewportTransform(framebufferSize: fb, viewSize: portrait)
        let unstretched = ViewportTransform(
            framebufferSize: fb,
            viewSize: portrait,
            zoomScale: 2,
            panOffset: CGSize(width: 0, height: 10_000)
        )

        XCTAssertEqual(fit.verticalPanBand, 0, accuracy: 1e-9)
        XCTAssertLessThan(unstretched.contentSize.height, portrait.height)
        XCTAssertEqual(unstretched.verticalPanBand, 0, accuracy: 1e-9)
        XCTAssertEqual(unstretched.panOffset.height, 0, accuracy: 1e-9)
    }

    func testVerticalBandIsCappedForTallViewports() {
        let tall = CGSize(width: 400, height: 1200)
        XCTAssertEqual(ViewportTransform.verticalPanBand(viewSize: tall), 96, accuracy: 1e-9)
    }

    func testAutoPanRevealReachesIntoTheVerticalBand() {
        // The bottom row of the remote screen must be liftable off the view's
        // bottom edge — this is the whole point of the band, and trackpad mode
        // can only get there through `panToReveal`.
        let square = CGSize(width: 1000, height: 500)
        let zoomed = ViewportTransform(
            framebufferSize: square,
            viewSize: square,
            zoomScale: 2,
            panOffset: CGSize(width: 0, height: 10_000)
        )
        let flushMaxY = (zoomed.contentSize.height - square.height) / 2
        let bottomRow = CGPoint(x: 500, y: 499)

        // Bottom edge flush with the view's bottom: content is pushed up, so
        // the pan is negative. Revealing the bottom row must push further.
        let flushAtBottom = ViewportTransform(
            framebufferSize: square,
            viewSize: square,
            zoomScale: 2,
            panOffset: CGSize(width: 0, height: -flushMaxY)
        )
        XCTAssertEqual(flushAtBottom.panOffset.height, -flushMaxY, accuracy: 1e-6)

        let revealed = flushAtBottom.panToReveal(framebufferPoint: bottomRow, margin: 88)

        XCTAssertLessThan(revealed.panOffset.height, -flushMaxY)
        XCTAssertGreaterThanOrEqual(
            revealed.panOffset.height,
            -(flushMaxY + ViewportTransform.verticalPanBand(viewSize: square)) - 1e-3
        )
    }

    func testZoomAboutAnchorKeepsAnchorPixelFixed() {
        let transform = ViewportTransform(framebufferSize: fb, viewSize: sixteenByNine)
        let anchor = CGPoint(x: 200, y: 100)
        let before = transform.framebufferPoint(fromViewPoint: anchor)
        let zoomed = transform.zoomed(to: 2.5, about: anchor)
        let after = zoomed.framebufferPoint(fromViewPoint: anchor)
        XCTAssertNotNil(before)
        XCTAssertNotNil(after)
        XCTAssertEqual(before?.x ?? -1, after?.x ?? -2, accuracy: 0.5)
        XCTAssertEqual(before?.y ?? -1, after?.y ?? -2, accuracy: 0.5)
    }

    func testPinchCentroidTranslationPansWithFingers() {
        let base = ViewportTransform(framebufferSize: fb, viewSize: sixteenByNine)
            .zoomed(to: 2, about: CGPoint(x: 160, y: 90))

        let moved = base.pinched(
            to: 2,
            about: CGPoint(x: 180, y: 90),
            anchorDelta: CGSize(width: 20, height: 0)
        )

        XCTAssertEqual(
            moved.panOffset.width,
            base.panOffset.width + 20,
            accuracy: 1e-6
        )
        XCTAssertEqual(moved.panOffset.height, base.panOffset.height, accuracy: 1e-6)
    }

    func testPinchCentroidTranslationAppliesWhenStartingAtFitScale() {
        let base = ViewportTransform(framebufferSize: fb, viewSize: sixteenByNine)
        let previousAnchor = CGPoint(x: 150, y: 80)
        let anchor = CGPoint(x: 170, y: 80)
        let fingerPixel = base.framebufferPoint(fromViewPoint: previousAnchor)

        let moved = base.pinched(
            to: 2,
            about: anchor,
            anchorDelta: CGSize(width: 20, height: 0)
        )
        let viewPoint = moved.viewPoint(fromFramebufferPoint: fingerPixel ?? .zero)

        XCTAssertEqual(viewPoint.x, anchor.x, accuracy: 0.5)
        XCTAssertEqual(viewPoint.y, anchor.y, accuracy: 0.5)
    }

    func testPinchAtCropFillMinimumKeepsPannableOffset() {
        let fit = ViewportTransform(framebufferSize: fb, viewSize: portrait)
        let fillZoom = portrait.height / fit.contentSize.height
        let baseline = ViewportTransform(
            framebufferSize: fb,
            viewSize: portrait,
            zoomScale: fillZoom,
            panOffset: CGSize(width: -120, height: 0)
        )

        let moved = baseline.pinched(
            to: fillZoom * 0.8,
            about: CGPoint(x: portrait.width / 2, y: portrait.height / 2),
            anchorDelta: CGSize(width: -24, height: 0),
            minimumZoomScale: fillZoom
        )

        XCTAssertEqual(moved.zoomScale, fillZoom, accuracy: 1e-6)
        XCTAssertLessThan(
            moved.panOffset.width,
            baseline.panOffset.width,
            "Crop-fill baseline is still pannable; pinching at the floor must not snap pan to zero."
        )
    }

    func testZoomClampedToMax() {
        let transform = ViewportTransform(framebufferSize: fb, viewSize: portrait, maxZoomScale: 4)
        let zoomed = transform.zoomed(to: 99, about: CGPoint(x: 195, y: 422))
        XCTAssertEqual(zoomed.zoomScale, 4, accuracy: 1e-6)
    }

    func testResetClearsZoomAndPan() {
        let transform = ViewportTransform(framebufferSize: fb, viewSize: portrait)
            .zoomed(to: 3, about: CGPoint(x: 100, y: 400))
            .reset()
        XCTAssertEqual(transform.zoomScale, 1, accuracy: 1e-6)
        XCTAssertEqual(transform.panOffset.width, 0, accuracy: 1e-6)
        XCTAssertEqual(transform.panOffset.height, 0, accuracy: 1e-6)
    }

    func testPanToRevealBringsOffscreenCursorInWhenZoomed() {
        // Zoom so content overflows, push pan to one extreme, then ask
        // to reveal a framebuffer point that is now off the right edge.
        let zoomed = ViewportTransform(framebufferSize: fb, viewSize: sixteenByNine)
            .zoomed(to: 3, about: CGPoint(x: 160, y: 90))
        let farRightPixel = CGPoint(x: fb.width - 1, y: fb.height / 2)
        // Before revealing, the pixel is off the right edge of the view.
        let beforeViewPoint = zoomed.viewPoint(fromFramebufferPoint: farRightPixel)
        XCTAssertGreaterThan(beforeViewPoint.x, sixteenByNine.width)
        // After revealing, it is on-screen (clamping caps it at the edge
        // for a far-edge pixel — the goal is visibility, not inset).
        let revealed = zoomed.panToReveal(framebufferPoint: farRightPixel, margin: 24)
        let viewPoint = revealed.viewPoint(fromFramebufferPoint: farRightPixel)
        XCTAssertLessThanOrEqual(viewPoint.x, sixteenByNine.width + 0.5)
        XCTAssertGreaterThanOrEqual(viewPoint.x, -0.5)
    }

    func testPanToRevealIsNoOpWhenNotZoomed() {
        let transform = ViewportTransform(framebufferSize: fb, viewSize: portrait)
        let revealed = transform.panToReveal(framebufferPoint: CGPoint(x: 0, y: 0), margin: 24)
        XCTAssertEqual(transform, revealed)
    }
}
