import CoreGraphics
import XCTest
@testable import NaruRemoteApp

@MainActor
final class SessionViewportViewGeometryTests: XCTestCase {
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
