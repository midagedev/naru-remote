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

    func testMetalInputSurfaceSuppressesSwiftUITrackpadOverlay() {
        XCTAssertFalse(
            SessionViewportView.usesSwiftUITrackpadInputOverlay(
                isPiPWatching: false,
                pointerControlMode: .trackpad,
                metalFramebufferInputSupported: true
            )
        )
        XCTAssertTrue(
            SessionViewportView.usesSwiftUITrackpadInputOverlay(
                isPiPWatching: false,
                pointerControlMode: .trackpad,
                metalFramebufferInputSupported: false
            )
        )
        XCTAssertFalse(
            SessionViewportView.usesSwiftUITrackpadInputOverlay(
                isPiPWatching: true,
                pointerControlMode: .trackpad,
                metalFramebufferInputSupported: false
            )
        )
        XCTAssertFalse(
            SessionViewportView.usesSwiftUITrackpadInputOverlay(
                isPiPWatching: false,
                pointerControlMode: .directTouch,
                metalFramebufferInputSupported: false
            )
        )
    }

    func testHelperVideoPrimaryUsesHotInputOverlayWhenMetalIsAvailable() {
        XCTAssertFalse(
            SessionViewportView.usesSwiftUITrackpadInputOverlay(
                isPiPWatching: false,
                usesHelperVideoPrimaryPreview: true,
                pointerControlMode: .trackpad,
                metalFramebufferInputSupported: true
            )
        )
        XCTAssertFalse(
            SessionViewportView.usesSwiftUIDirectTouchInputOverlay(
                isPiPWatching: false,
                usesHelperVideoPrimaryPreview: true,
                pointerControlMode: .directTouch,
                metalFramebufferInputSupported: true
            )
        )
        XCTAssertTrue(
            SessionViewportView.usesMetalHotInputOverlay(
                isPiPWatching: false,
                usesHelperVideoPrimaryPreview: true,
                metalFramebufferInputSupported: true
            )
        )
        XCTAssertTrue(
            SessionViewportView.usesSwiftUITrackpadInputOverlay(
                isPiPWatching: false,
                usesHelperVideoPrimaryPreview: true,
                pointerControlMode: .trackpad,
                metalFramebufferInputSupported: false
            )
        )
        XCTAssertFalse(
            SessionViewportView.usesMetalHotInputOverlay(
                isPiPWatching: false,
                usesHelperVideoPrimaryPreview: true,
                metalFramebufferInputSupported: false
            )
        )
        XCTAssertTrue(
            SessionViewportView.usesMetalHotTrackpadCursor(
                isPiPWatching: false,
                usesHelperVideoPrimaryPreview: true,
                pointerControlMode: .trackpad,
                metalFramebufferInputSupported: true
            )
        )
    }

    func testTrackpadHotDragKeepsImmediateCursorOverPublishedSnapshot() {
        XCTAssertFalse(
            TrackpadCursorSnapshotPolicy.shouldAdoptPublishedCursor(
                pointerControlMode: .trackpad,
                didChangePointerControlMode: false,
                isTrackpadDragActive: true
            )
        )
    }

    func testTrackpadCursorSnapshotAppliesOnModeChangeAndAfterDrag() {
        XCTAssertTrue(
            TrackpadCursorSnapshotPolicy.shouldAdoptPublishedCursor(
                pointerControlMode: .trackpad,
                didChangePointerControlMode: true,
                isTrackpadDragActive: true
            )
        )
        XCTAssertTrue(
            TrackpadCursorSnapshotPolicy.shouldAdoptPublishedCursor(
                pointerControlMode: .trackpad,
                didChangePointerControlMode: false,
                isTrackpadDragActive: false
            )
        )
    }

    func testImmersiveControlsDoNotAutoHideDuringViewportInteraction() {
        XCTAssertFalse(
            SessionViewportView.allowsImmersiveControlAutoHide(
                showsControlBar: true,
                isViewportInteractionActive: true
            )
        )
    }

    func testImmersiveControlsCollapseWhenViewportInteractionBegins() {
        XCTAssertTrue(
            SessionViewportView.collapsesImmersiveControlsOnViewportInteraction(
                showsControlBar: true,
                isViewportInteractionActive: true
            )
        )
        XCTAssertFalse(
            SessionViewportView.collapsesImmersiveControlsOnViewportInteraction(
                showsControlBar: false,
                isViewportInteractionActive: true
            )
        )
        XCTAssertFalse(
            SessionViewportView.collapsesImmersiveControlsOnViewportInteraction(
                showsControlBar: true,
                isViewportInteractionActive: false
            )
        )
    }

    func testImmersiveControlsAutoHideOnlyWhenVisibleAndIdle() {
        XCTAssertTrue(
            SessionViewportView.allowsImmersiveControlAutoHide(
                showsControlBar: true,
                isViewportInteractionActive: false
            )
        )
        XCTAssertFalse(
            SessionViewportView.allowsImmersiveControlAutoHide(
                showsControlBar: false,
                isViewportInteractionActive: false
            )
        )
    }

    func testTrackpadDragAtFitScaleDoesNotOwnViewportInteraction() {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 200, height: 100),
            viewSize: CGSize(width: 200, height: 100),
            zoomScale: 1,
            panOffset: .zero
        )

        XCTAssertFalse(SessionViewportView.trackpadDragOwnsViewportInteraction(transform: transform))
    }

    func testTrackpadDragOwnsViewportInteractionOnlyWhenPannable() {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 200, height: 100),
            viewSize: CGSize(width: 200, height: 100),
            zoomScale: 2,
            panOffset: .zero
        )

        XCTAssertTrue(SessionViewportView.trackpadDragOwnsViewportInteraction(transform: transform))
    }

    func testViewportStatePublishPolicyUsesDisplayLinkForViewAwareTraffic() {
        XCTAssertEqual(
            SessionViewportView.viewportStatePublishPolicy(for: .deferUntilSettled),
            .liveDisplayLink
        )
        XCTAssertEqual(
            SessionViewportView.viewportStatePublishPolicy(for: .liveRemoteFrames),
            .liveDisplayLink
        )
    }

    func testCursorOverlayFallsBackToSyntheticCursorWithoutServerShape() {
        XCTAssertEqual(
            SessionViewportView.cursorOverlayKind(serverCursor: nil),
            .syntheticFallback
        )
        XCTAssertEqual(
            SessionViewportView.cursorOverlayKind(
                serverCursor: RFBServerCursor(
                    width: 0,
                    height: 1,
                    hotSpotX: 0,
                    hotSpotY: 0,
                    pixels: []
                )
            ),
            .syntheticFallback
        )
        XCTAssertEqual(
            SessionViewportView.cursorOverlayKind(
                serverCursor: RFBServerCursor(
                    width: 1,
                    height: 0,
                    hotSpotX: 0,
                    hotSpotY: 0,
                    pixels: []
                )
            ),
            .syntheticFallback
        )
    }

    func testCursorOverlayUsesServerShapeWhenAvailable() {
        let cursor = RFBServerCursor(
            width: 1,
            height: 1,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: [RFBColor(red: 255, green: 255, blue: 255)]
        )

        XCTAssertEqual(
            SessionViewportView.cursorOverlayKind(serverCursor: cursor),
            .serverShape
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

    func testZoomToggleResetsToImmersiveBaseline() {
        let baseline: CGFloat = 2.0
        let reset = SessionViewportView.zoomToggleTransform(
            framebufferSize: CGSize(width: 1600, height: 900),
            viewSize: CGSize(width: 400, height: 700),
            zoomScale: 3.1,
            panOffset: CGSize(width: -120, height: 24),
            anchor: CGPoint(x: 180, y: 320),
            baselineZoomScale: baseline
        )

        XCTAssertEqual(reset.zoomScale, baseline, accuracy: 1e-6)
        XCTAssertEqual(reset.panOffset, .zero)
    }

    func testZoomToggleZoomsAboveImmersiveBaseline() {
        let baseline: CGFloat = 2.0
        let zoomed = SessionViewportView.zoomToggleTransform(
            framebufferSize: CGSize(width: 1600, height: 900),
            viewSize: CGSize(width: 400, height: 700),
            zoomScale: baseline,
            panOffset: .zero,
            anchor: CGPoint(x: 260, y: 320),
            baselineZoomScale: baseline
        )

        XCTAssertEqual(zoomed.zoomScale, 2.7, accuracy: 1e-6)
    }

    func testAspectFillZoomScaleExpandsWidescreenIntoPortraitViewport() {
        let scale = SessionViewportView.aspectFillZoomScale(
            aspectRatio: 16.0 / 9.0,
            containerSize: CGSize(width: 400, height: 800)
        )

        XCTAssertEqual(scale, 32.0 / 9.0, accuracy: 1e-6)
    }

    func testAspectFillZoomScaleStaysOneWhenAspectAlreadyMatches() {
        let scale = SessionViewportView.aspectFillZoomScale(
            aspectRatio: 16.0 / 9.0,
            containerSize: CGSize(width: 1600, height: 900)
        )

        XCTAssertEqual(scale, 1, accuracy: 1e-6)
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
