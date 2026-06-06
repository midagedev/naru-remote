import CoreGraphics
import XCTest
@testable import NaruRemoteCore

final class PointerGestureResolverTests: XCTestCase {
    private let fb = CGSize(width: 1000, height: 1000)
    // A square view so fit scale is exactly 1.0 and view points map
    // 1:1 to framebuffer pixels at zoom 1 — keeps the arithmetic in
    // the assertions obvious.
    private let view = CGSize(width: 1000, height: 1000)

    private func transform(zoom: CGFloat = 1, pan: CGSize = .zero) -> ViewportTransform {
        ViewportTransform(framebufferSize: fb, viewSize: view, zoomScale: zoom, panOffset: pan)
    }

    // MARK: Direct touch

    func testDirectTapMapsToTouchedPixel() {
        let resolver = PointerGestureResolver(mode: .directTouch)
        let outcome = resolver.resolve(
            .tap(viewPoint: CGPoint(x: 300, y: 400)),
            transform: transform(),
            cursor: TrackpadCursor()
        )
        XCTAssertEqual(outcome.commands, [
            RFBPointerCommand(buttonMask: 0x01, x: 300, y: 400),
            RFBPointerCommand(buttonMask: 0x00, x: 300, y: 400)
        ])
        XCTAssertFalse(outcome.cursor.isVisible)
    }

    func testDirectTapMapsThroughZoomAndPan() {
        // Zoom 2x about the center; the view center still maps to the
        // framebuffer center (500,500).
        let zoomed = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        let resolver = PointerGestureResolver(mode: .directTouch)
        let outcome = resolver.resolve(
            .tap(viewPoint: CGPoint(x: 500, y: 500)),
            transform: zoomed,
            cursor: TrackpadCursor()
        )
        XCTAssertEqual(outcome.commands.first?.x ?? 0, 500, accuracy: 1)
        XCTAssertEqual(outcome.commands.first?.y ?? 0, 500, accuracy: 1)
    }

    func testDirectLongPressIsRightClick() {
        let resolver = PointerGestureResolver(mode: .directTouch)
        let outcome = resolver.resolve(
            .longPress(viewPoint: CGPoint(x: 100, y: 100)),
            transform: transform(),
            cursor: TrackpadCursor()
        )
        XCTAssertEqual(outcome.commands.map(\.buttonMask), [0x04, 0x00])
    }

    func testDirectPanEmitsNoCommandsAndMovesViewport() {
        let resolver = PointerGestureResolver(mode: .directTouch)
        let zoomed = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        let outcome = resolver.resolve(
            .dragChanged(viewPoint: CGPoint(x: 500, y: 500), translation: CGSize(width: -100, height: 0)),
            transform: zoomed,
            cursor: TrackpadCursor()
        )
        XCTAssertTrue(outcome.commands.isEmpty, "Pan must emit no RFB messages (constitution §I)")
        XCTAssertEqual(outcome.transform.panOffset.width, -100, accuracy: 1)
    }

    func testDirectTapInLetterboxBandIsNoOp() {
        // Wide framebuffer in a tall view → top band is letterbox.
        let wide = ViewportTransform(framebufferSize: CGSize(width: 1000, height: 200), viewSize: view)
        let resolver = PointerGestureResolver(mode: .directTouch)
        let outcome = resolver.resolve(
            .tap(viewPoint: CGPoint(x: 500, y: 10)),
            transform: wide,
            cursor: TrackpadCursor()
        )
        XCTAssertTrue(outcome.commands.isEmpty)
    }

    // MARK: Trackpad

    func testTrackpadTapClicksAtCursorNotTouch() {
        let resolver = PointerGestureResolver(mode: .trackpad)
        let cursor = TrackpadCursor(position: CGPoint(x: 250, y: 750), isVisible: true)
        let outcome = resolver.resolve(
            .tap(viewPoint: CGPoint(x: 0, y: 0)),
            transform: transform(),
            cursor: cursor
        )
        XCTAssertEqual(outcome.commands, [
            RFBPointerCommand(buttonMask: 0x01, x: 250, y: 750),
            RFBPointerCommand(buttonMask: 0x00, x: 250, y: 750)
        ])
    }

    func testTrackpadSecondaryTapIsRightClickAtCursor() {
        let resolver = PointerGestureResolver(mode: .trackpad)
        let cursor = TrackpadCursor(position: CGPoint(x: 10, y: 20), isVisible: true)
        let outcome = resolver.resolve(
            .secondaryTap(viewPoint: CGPoint(x: 999, y: 999)),
            transform: transform(),
            cursor: cursor
        )
        XCTAssertEqual(outcome.commands, [
            RFBPointerCommand(buttonMask: 0x04, x: 10, y: 20),
            RFBPointerCommand(buttonMask: 0x00, x: 10, y: 20)
        ])
    }

    func testTrackpadDragMovesRemotePointerWithoutButtonPress() {
        let resolver = PointerGestureResolver(mode: .trackpad)
        let cursor = TrackpadCursor(position: CGPoint(x: 100, y: 100), isVisible: true)
        let outcome = resolver.resolve(
            .dragChanged(viewPoint: .zero, translation: CGSize(width: 40, height: 20)),
            transform: transform(),
            cursor: cursor
        )
        XCTAssertEqual(outcome.commands, [
            RFBPointerCommand(buttonMask: 0x00, x: 140, y: 120)
        ], "Trackpad cursor movement should move the remote pointer without pressing a button")
        // fit scale is 1.0, sensitivity 1 → 1:1 framebuffer travel.
        XCTAssertEqual(outcome.cursor.position.x, 140, accuracy: 1e-6)
        XCTAssertEqual(outcome.cursor.position.y, 120, accuracy: 1e-6)
        XCTAssertTrue(outcome.cursor.isVisible)
    }

    func testTrackpadTapAndAHalfEmitsDownHoldUp() {
        let resolver = PointerGestureResolver(mode: .trackpad)
        let cursor = TrackpadCursor(position: CGPoint(x: 200, y: 200), isVisible: true)

        let began = resolver.resolve(.pressDragBegan, transform: transform(), cursor: cursor)
        XCTAssertEqual(began.commands, [RFBPointerCommand(buttonMask: 0x01, x: 200, y: 200)])

        let changed = resolver.resolve(
            .pressDragChanged(translation: CGSize(width: 50, height: 0)),
            transform: transform(),
            cursor: began.cursor
        )
        XCTAssertEqual(changed.commands.first?.buttonMask, 0x01, "Button stays held through the drag")
        XCTAssertEqual(changed.commands.first?.x ?? 0, 250)

        let ended = resolver.resolve(.pressDragEnded, transform: transform(), cursor: changed.cursor)
        XCTAssertEqual(ended.commands, [RFBPointerCommand(buttonMask: 0x00, x: 250, y: 200)])
    }

    func testTrackpadDragAutoPansWhenZoomed() {
        let resolver = PointerGestureResolver(mode: .trackpad, autoPanMargin: 48)
        let zoomed = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        // Cursor near the right framebuffer edge; a rightward move
        // should auto-pan the viewport (non-empty pan change).
        let cursor = TrackpadCursor(position: CGPoint(x: 980, y: 500), isVisible: true)
        let outcome = resolver.resolve(
            .dragChanged(viewPoint: .zero, translation: CGSize(width: 200, height: 0)),
            transform: zoomed,
            cursor: cursor
        )
        XCTAssertNotEqual(outcome.transform.panOffset, zoomed.panOffset, "Auto-pan should move the viewport")
        let snapped = zoomed.panToReveal(
            framebufferPoint: outcome.cursor.position,
            margin: 96
        )
        XCTAssertGreaterThan(
            outcome.transform.panOffset.width,
            snapped.panOffset.width,
            "Auto-pan should follow smoothly instead of snapping to the full reveal delta"
        )
        XCTAssertEqual(outcome.commands, [
            RFBPointerCommand(buttonMask: 0x00, x: 999, y: 500)
        ])
    }

    func testTrackpadDragUsesViewportRelativeFollowZoneWhenZoomed() {
        let resolver = PointerGestureResolver(mode: .trackpad, autoPanMargin: 48)
        let zoomed = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        let cursor = TrackpadCursor(position: CGPoint(x: 650, y: 500), isVisible: true)

        let outcome = resolver.resolve(
            .dragChanged(viewPoint: .zero, translation: CGSize(width: 200, height: 0)),
            transform: zoomed,
            cursor: cursor
        )

        XCTAssertLessThan(
            outcome.transform.panOffset.width,
            zoomed.panOffset.width,
            "Zoomed trackpad movement should begin panning before the cursor reaches the edge"
        )
        XCTAssertEqual(outcome.commands, [
            RFBPointerCommand(buttonMask: 0x00, x: 782, y: 500)
        ])
    }

    func testTrackpadMotionPansContinuouslyWhenZoomed() {
        let resolver = PointerGestureResolver(mode: .trackpad, autoPanMargin: 48)
        let zoomed = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        let cursor = TrackpadCursor(position: CGPoint(x: 500, y: 500), isVisible: true)

        let outcome = resolver.resolve(
            .dragChanged(viewPoint: .zero, translation: CGSize(width: 250, height: 0)),
            transform: zoomed,
            cursor: cursor
        )

        XCTAssertEqual(
            outcome.transform.panOffset.width,
            -80,
            accuracy: 1e-6,
            "Zoomed trackpad movement should pan with the cursor without dragging the background too aggressively."
        )
        XCTAssertEqual(outcome.commands, [
            RFBPointerCommand(buttonMask: 0x00, x: 665, y: 500)
        ])
    }

    func testZoomedTrackpadCursorKeepsFingerPacedTravelVisible() {
        let resolver = PointerGestureResolver(mode: .trackpad, autoPanMargin: 48)
        let zoomed = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        let cursor = TrackpadCursor(position: CGPoint(x: 500, y: 500), isVisible: true)
        let startCursorViewPoint = zoomed.viewPoint(fromFramebufferPoint: cursor.position)
        let touchTranslation = CGSize(width: 240, height: 0)

        let outcome = resolver.resolve(
            .dragChanged(viewPoint: .zero, translation: touchTranslation),
            transform: zoomed,
            cursor: cursor
        )
        let endCursorViewPoint = outcome.transform.viewPoint(fromFramebufferPoint: outcome.cursor.position)
        let visibleCursorTravel = endCursorViewPoint.x - startCursorViewPoint.x

        XCTAssertEqual(
            visibleCursorTravel,
            touchTranslation.width,
            accuracy: 1,
            "Zoomed trackpad pan coupling should not cancel visible cursor travel."
        )
    }

    func testTrackpadFollowZoneStartsNearViewportEdgeWhenZoomed() {
        let resolver = PointerGestureResolver(mode: .trackpad, autoPanMargin: 48)
        let zoomed = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        let cursor = TrackpadCursor(position: CGPoint(x: 650, y: 500), isVisible: true)

        let outcome = resolver.resolve(
            .dragChanged(viewPoint: .zero, translation: CGSize(width: 200, height: 0)),
            transform: zoomed,
            cursor: cursor
        )

        XCTAssertLessThan(
            outcome.transform.panOffset.width,
            zoomed.panOffset.width,
            "Zoomed trackpad pan should begin once the cursor approaches the viewport edge."
        )
        XCTAssertEqual(outcome.commands, [
            RFBPointerCommand(buttonMask: 0x00, x: 782, y: 500)
        ])
    }

    func testZoomedTrackpadPanCouplingStaysSubtleAwayFromEdge() {
        let resolver = PointerGestureResolver(mode: .trackpad, autoPanMargin: 48)
        let zoomed = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        let cursor = TrackpadCursor(position: CGPoint(x: 500, y: 500), isVisible: true)
        let touchTranslation = CGSize(width: 180, height: 0)

        let outcome = resolver.resolve(
            .dragChanged(viewPoint: .zero, translation: touchTranslation),
            transform: zoomed,
            cursor: cursor
        )

        XCTAssertEqual(
            outcome.transform.panOffset.width,
            -57.6,
            accuracy: 1e-6,
            "Central zoomed trackpad motion should follow the cursor without making the viewport feel over-dragged."
        )
        XCTAssertEqual(outcome.commands, [
            RFBPointerCommand(buttonMask: 0x00, x: 619, y: 500)
        ])
    }

    func testZoomedTrackpadCentralSamplesPanSmoothlyWithoutChangingVisibleCursorPace() {
        let resolver = PointerGestureResolver(mode: .trackpad, autoPanMargin: 48)
        var currentTransform = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        var currentCursor = TrackpadCursor(position: CGPoint(x: 500, y: 500), isVisible: true)
        let touchDelta = CGSize(width: 16, height: 0)

        for _ in 0..<10 {
            let beforeCursorViewPoint = currentTransform.viewPoint(fromFramebufferPoint: currentCursor.position)
            let beforePan = currentTransform.panOffset.width
            let outcome = resolver.resolve(
                .dragChanged(viewPoint: .zero, translation: touchDelta),
                transform: currentTransform,
                cursor: currentCursor
            )
            let afterCursorViewPoint = outcome.transform.viewPoint(fromFramebufferPoint: outcome.cursor.position)

            XCTAssertEqual(
                outcome.transform.panOffset.width - beforePan,
                -5.12,
                accuracy: 1e-6,
                "Central zoomed trackpad pan should advance by a predictable per-sample step."
            )
            XCTAssertEqual(
                afterCursorViewPoint.x - beforeCursorViewPoint.x,
                touchDelta.width,
                accuracy: 0.5,
                "Viewport follow-pan should not make the visible cursor outrun or lag behind the finger."
            )

            currentTransform = outcome.transform
            currentCursor = outcome.cursor
        }
    }

    func testTrackpadAutoPanKeepsUpNearViewportEdge() {
        let resolver = PointerGestureResolver(mode: .trackpad, autoPanMargin: 48)
        let zoomed = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        let cursor = TrackpadCursor(position: CGPoint(x: 650, y: 500), isVisible: true)

        let outcome = resolver.resolve(
            .dragChanged(viewPoint: .zero, translation: CGSize(width: 200, height: 0)),
            transform: zoomed,
            cursor: cursor
        )

        XCTAssertLessThanOrEqual(
            outcome.transform.panOffset.width,
            -45,
            "Trackpad auto-pan should move with the cursor instead of lagging at the edge."
        )
        XCTAssertGreaterThan(
            outcome.transform.panOffset.width,
            -220,
            "Auto-pan should still damp the full reveal delta rather than snapping."
        )
    }

    func testTrackpadAutoPanKeepsUpForTinyTouchSamplesWithoutSnapping() {
        let resolver = PointerGestureResolver(mode: .trackpad, autoPanMargin: 48)
        let zoomed = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        let cursor = TrackpadCursor(position: CGPoint(x: 745, y: 500), isVisible: true)

        let outcome = resolver.resolve(
            .dragChanged(viewPoint: .zero, translation: CGSize(width: 4, height: 0)),
            transform: zoomed,
            cursor: cursor
        )

        XCTAssertLessThan(
            outcome.transform.panOffset.width,
            zoomed.panOffset.width,
            "The viewport should still follow a cursor that is close to the edge."
        )
        XCTAssertGreaterThanOrEqual(
            outcome.transform.panOffset.width,
            -5,
            "Tiny high-refresh touch samples should not pan faster than the finger can visually carry the cursor."
        )
        XCTAssertLessThanOrEqual(
            outcome.transform.panOffset.width,
            -3,
            "Tiny high-refresh touch samples should still make visible follow-pan progress."
        )
    }

    func testTrackpadAutoPanTinySamplesDoNotMoveCursorBackwardOnScreen() {
        let resolver = PointerGestureResolver(mode: .trackpad, autoPanMargin: 48)
        var currentTransform = transform().zoomed(to: 2, about: CGPoint(x: 500, y: 500))
        var currentCursor = TrackpadCursor(position: CGPoint(x: 745, y: 500), isVisible: true)
        let touchDelta = CGSize(width: 4, height: 0)

        for _ in 0..<24 {
            let before = currentTransform.viewPoint(fromFramebufferPoint: currentCursor.position)
            let outcome = resolver.resolve(
                .dragChanged(viewPoint: .zero, translation: touchDelta),
                transform: currentTransform,
                cursor: currentCursor
            )
            let after = outcome.transform.viewPoint(fromFramebufferPoint: outcome.cursor.position)

            XCTAssertGreaterThan(
                after.x - before.x,
                0,
                "Near-edge auto-pan must not make the visible cursor travel opposite the finger."
            )
            XCTAssertLessThanOrEqual(
                after.x - before.x,
                touchDelta.width + 0.5,
                "Near-edge auto-pan should slow visible cursor travel smoothly instead of overshooting."
            )

            currentTransform = outcome.transform
            currentCursor = outcome.cursor
        }
    }
}
