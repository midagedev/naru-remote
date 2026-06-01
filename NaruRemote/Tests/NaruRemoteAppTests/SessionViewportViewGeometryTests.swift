import CoreGraphics
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class SessionViewportViewGeometryTests: XCTestCase {
    func testPiPWatchingDisablesTrackpadInputOverlayAndCursor() {
        XCTAssertTrue(
            SessionViewportView.allowsTrackpadInputOverlay(
                isPiPWatching: false,
                pointerControlMode: .trackpad
            )
        )
        XCTAssertFalse(
            SessionViewportView.allowsTrackpadInputOverlay(
                isPiPWatching: true,
                pointerControlMode: .trackpad
            )
        )
        XCTAssertFalse(
            SessionViewportView.showsTrackpadCursor(
                isPiPWatching: true,
                pointerControlMode: .trackpad,
                cursor: TrackpadCursor(position: CGPoint(x: 40, y: 30), isVisible: true)
            )
        )
    }

    func testZoomToggleAnchorsToTappedFramebufferPoint() {
        let framebufferSize = CGSize(width: 1600, height: 900)
        let viewSize = CGSize(width: 400, height: 400)
        let anchor = CGPoint(x: 300, y: 250)
        let fit = ViewportTransform(framebufferSize: framebufferSize, viewSize: viewSize)
        let before = fit.framebufferPoint(fromViewPoint: anchor)

        let zoomed = SessionViewportView.zoomToggleTransform(
            framebufferSize: framebufferSize,
            viewSize: viewSize,
            zoomScale: 1,
            panOffset: .zero,
            anchor: anchor
        )
        let after = zoomed.framebufferPoint(fromViewPoint: anchor)

        XCTAssertEqual(zoomed.zoomScale, 2.5, accuracy: 1e-6)
        XCTAssertEqual(before?.x ?? -1, after?.x ?? -2, accuracy: 0.5)
        XCTAssertEqual(before?.y ?? -1, after?.y ?? -2, accuracy: 0.5)
    }

    func testZoomToggleResetsWhenAlreadyZoomed() {
        let reset = SessionViewportView.zoomToggleTransform(
            framebufferSize: CGSize(width: 100, height: 100),
            viewSize: CGSize(width: 100, height: 100),
            zoomScale: 2,
            panOffset: CGSize(width: -30, height: 20),
            anchor: CGPoint(x: 40, y: 40)
        )

        XCTAssertEqual(reset.zoomScale, 1, accuracy: 1e-6)
        XCTAssertEqual(reset.panOffset, .zero)
    }

    func testCursorViewPointIncludesZoomAndPan() {
        let point = SessionViewportView.cursorViewPoint(
            framebufferPosition: CGPoint(x: 75, y: 50),
            framebufferWidth: 100,
            framebufferHeight: 100,
            containerSize: CGSize(width: 100, height: 100),
            zoomScale: 2,
            panOffset: CGSize(width: -50, height: 0)
        )

        XCTAssertEqual(point.x, 50, accuracy: 1e-6)
        XCTAssertEqual(point.y, 50, accuracy: 1e-6)
    }

    func testCursorViewPointFallsBackToCenterForDegenerateGeometry() {
        let point = SessionViewportView.cursorViewPoint(
            framebufferPosition: CGPoint(x: 75, y: 50),
            framebufferWidth: 0,
            framebufferHeight: 100,
            containerSize: CGSize(width: 120, height: 80),
            zoomScale: 2,
            panOffset: CGSize(width: -50, height: 0)
        )

        XCTAssertEqual(point.x, 60, accuracy: 1e-6)
        XCTAssertEqual(point.y, 40, accuracy: 1e-6)
    }
}
