import CoreGraphics
import XCTest
@testable import NaruRemoteCore

final class ViewportInputHotPathDriverTests: XCTestCase {
    func testSyncRespectsCropFillMinimumZoomWithoutSnappingPan() {
        let framebuffer = CGSize(width: 1920, height: 1080)
        let view = CGSize(width: 390, height: 844)
        let fit = ViewportTransform(framebufferSize: framebuffer, viewSize: view)
        let fillZoom = view.height / fit.contentSize.height

        var driver = ViewportInputHotPathDriver(
            framebufferSize: framebuffer,
            viewSize: view,
            zoomScale: fillZoom,
            panOffset: CGSize(width: -90, height: 0),
            minimumZoomScale: fillZoom
        )

        let update = driver.sync(
            zoomScale: fillZoom * 0.7,
            panOffset: CGSize(width: -120, height: 0)
        )

        XCTAssertTrue(update.didChange)
        XCTAssertEqual(driver.transform.zoomScale, fillZoom, accuracy: 1e-6)
        XCTAssertLessThan(
            driver.transform.panOffset.width,
            0,
            "Crop-fill is still pannable, so syncing below the floor must keep a meaningful pan instead of snapping to fit."
        )
    }

    func testTrackpadOutcomeAdoptionKeepsTransformClamped() {
        var driver = ViewportInputHotPathDriver(
            framebufferSize: CGSize(width: 1920, height: 1080),
            viewSize: CGSize(width: 390, height: 240),
            zoomScale: 2.2
        )
        let resolver = PointerGestureResolver(mode: .trackpad)
        var cursor = TrackpadCursor(position: CGPoint(x: 960, y: 540), isVisible: true)

        for _ in 0..<40 {
            let outcome = resolver.resolve(
                .dragChanged(viewPoint: CGPoint(x: 195, y: 120), translation: CGSize(width: 8, height: 0)),
                transform: driver.transform,
                cursor: cursor
            )
            cursor = outcome.cursor
            _ = driver.adopt(outcome.transform)
        }

        XCTAssertLessThanOrEqual(driver.transform.zoomScale, 4)
        XCTAssertTrue(driver.transform.isPannable)
        XCTAssertNotEqual(cursor.position, CGPoint(x: 960, y: 540))
        XCTAssertEqual(
            driver.transform.panOffset,
            ViewportTransform(
                framebufferSize: driver.transform.framebufferSize,
                viewSize: driver.transform.viewSize,
                zoomScale: driver.transform.zoomScale,
                panOffset: driver.transform.panOffset
            ).panOffset
        )
    }
}
