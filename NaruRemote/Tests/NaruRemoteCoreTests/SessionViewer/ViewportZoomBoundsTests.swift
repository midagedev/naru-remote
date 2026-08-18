import CoreGraphics
import XCTest
@testable import NaruRemoteCore

/// The hero viewport's opening scale and its floor are different numbers.
/// Before 2026-08-19 they were the same one (fill), so the whole remote screen
/// could never be brought into view and the session controls that ride over the
/// top and bottom edges always covered live content.
final class ViewportZoomBoundsTests: XCTestCase {

    private let phonePortrait = CGSize(width: 390, height: 844)
    private let phoneLandscape = CGSize(width: 844, height: 390)
    private let widescreen: CGFloat = 16.0 / 9.0

    // MARK: - The floor shows everything

    func testFloorIsFitSoTheWholeRemoteScreenIsVisible() {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1920, height: 1080),
            viewSize: phonePortrait,
            zoomScale: ViewportZoomBounds.floorScale
        )

        XCTAssertLessThanOrEqual(
            transform.contentSize.width.rounded(),
            phonePortrait.width.rounded(),
            "At the floor the remote screen must fit horizontally"
        )
        XCTAssertLessThanOrEqual(
            transform.contentSize.height.rounded(),
            phonePortrait.height.rounded(),
            "At the floor the remote screen must fit vertically"
        )
        XCTAssertFalse(transform.isZoomed)
    }

    /// The point of lowering the floor: at fit there is empty band above and
    /// below the content on a portrait phone, which is where the session
    /// controls can sit without covering anything live.
    func testFloorLeavesBandsForTheSessionControlsOnAPortraitPhone() {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1920, height: 1080),
            viewSize: phonePortrait,
            zoomScale: ViewportZoomBounds.floorScale
        )

        let band = (phonePortrait.height - transform.contentSize.height) / 2
        XCTAssertGreaterThan(
            band,
            88,
            "A 16:9 desktop fitted into a portrait phone should clear the control strips"
        )
    }

    // MARK: - Fill is the opening state, and it crops

    func testFillExceedsTheViewOnAPortraitPhone() {
        let fill = ViewportZoomBounds.fillScale(
            framebufferAspectRatio: widescreen,
            containerSize: phonePortrait
        )
        XCTAssertGreaterThan(fill, ViewportZoomBounds.floorScale)

        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1920, height: 1080),
            viewSize: phonePortrait,
            zoomScale: fill
        )
        XCTAssertGreaterThan(
            transform.contentSize.width,
            phonePortrait.width,
            "Fill crops horizontally on a portrait phone — that is what it is for"
        )
    }

    /// The landscape case is why the floor is fit rather than fit-by-width: a
    /// 6.9" phone in landscape is proportionally wider than a 16:9 desktop, so
    /// matching the width would push content back under the top and bottom
    /// controls.
    func testFillCropsVerticallyOnALandscapePhone() {
        let fill = ViewportZoomBounds.fillScale(
            framebufferAspectRatio: widescreen,
            containerSize: phoneLandscape
        )
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1920, height: 1080),
            viewSize: phoneLandscape,
            zoomScale: fill
        )

        XCTAssertGreaterThan(fill, ViewportZoomBounds.floorScale)
        XCTAssertGreaterThan(transform.contentSize.height, phoneLandscape.height)
    }

    func testFillIsTheRatioMismatch() {
        // A 4:3 view against a 16:9 frame needs 16/9 ÷ 4/3 = 4/3 more scale.
        let fill = ViewportZoomBounds.fillScale(
            framebufferAspectRatio: widescreen,
            containerSize: CGSize(width: 1024, height: 768)
        )
        XCTAssertEqual(fill, 4.0 / 3.0, accuracy: 0.0001)
    }

    func testMatchingAspectNeedsNoFill() {
        let fill = ViewportZoomBounds.fillScale(
            framebufferAspectRatio: widescreen,
            containerSize: CGSize(width: 1600, height: 900)
        )
        XCTAssertEqual(fill, ViewportZoomBounds.floorScale, accuracy: 0.0001)
    }

    // MARK: - Degenerate input

    func testDegenerateInputFallsBackToTheFloor() {
        let cases: [(CGFloat, CGSize)] = [
            (0, CGSize(width: 390, height: 844)),
            (widescreen, .zero),
            (.nan, CGSize(width: 390, height: 844)),
            (.infinity, CGSize(width: 390, height: 844))
        ]
        for (ratio, size) in cases {
            XCTAssertEqual(
                ViewportZoomBounds.fillScale(framebufferAspectRatio: ratio, containerSize: size),
                ViewportZoomBounds.floorScale
            )
        }
    }

    func testClampKeepsScalesInsideTheAllowedRange() {
        XCTAssertEqual(ViewportZoomBounds.clamped(0.2, maxZoomScale: 4), 1)
        XCTAssertEqual(ViewportZoomBounds.clamped(9, maxZoomScale: 4), 4)
        XCTAssertEqual(ViewportZoomBounds.clamped(2.5, maxZoomScale: 4), 2.5)
        XCTAssertEqual(ViewportZoomBounds.clamped(.nan, maxZoomScale: 4), 1)
    }
}
