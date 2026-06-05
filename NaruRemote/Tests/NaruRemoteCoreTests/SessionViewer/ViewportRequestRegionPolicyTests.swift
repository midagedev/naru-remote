import CoreGraphics
import XCTest
@testable import NaruRemoteCore

final class ViewportRequestRegionPolicyTests: XCTestCase {
    func testFitViewportUsesFullRequest() {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1000, height: 1000),
            viewSize: CGSize(width: 500, height: 500)
        )

        XCTAssertNil(transform.visibleFramebufferUpdateRegion())
    }

    func testZoomedViewportBuildsVisibleFramebufferRegion() throws {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1000, height: 1000),
            viewSize: CGSize(width: 500, height: 500),
            zoomScale: 2
        )

        let region = try XCTUnwrap(
            transform.visibleFramebufferUpdateRegion(expansionMarginPixels: 0)
        )

        XCTAssertEqual(region.x, 250)
        XCTAssertEqual(region.y, 250)
        XCTAssertEqual(region.width, 500)
        XCTAssertEqual(region.height, 500)
    }

    func testRegionExpansionIsClampedToFramebufferBounds() throws {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1000, height: 1000),
            viewSize: CGSize(width: 500, height: 500),
            zoomScale: 2
        ).panned(by: CGSize(width: 250, height: 250))

        let region = try XCTUnwrap(
            transform.visibleFramebufferUpdateRegion(expansionMarginPixels: 100)
        )

        XCTAssertEqual(region.x, 0)
        XCTAssertEqual(region.y, 0)
        XCTAssertEqual(region.width, 600)
        XCTAssertEqual(region.height, 600)
    }

    func testMinimumSavingsCanPromoteAlmostFullRegionToFullRequest() {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1000, height: 1000),
            viewSize: CGSize(width: 900, height: 900),
            zoomScale: 1.05
        )

        XCTAssertNil(
            transform.visibleFramebufferUpdateRegion(
                expansionMarginPixels: 0,
                minimumSavingsPermille: 200
            )
        )
    }

    func testPolicyUsesFullRequestForHeartbeatAndTimeoutFallback() throws {
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 1000, height: 1000),
            viewSize: CGSize(width: 500, height: 500),
            zoomScale: 2
        )
        let policy = ViewportRequestRegionPolicy(
            expansionMarginPixels: 0,
            fullHeartbeatInterval: 3,
            fullFallbackTimeoutStreak: 1
        )

        XCTAssertNotNil(
            policy.requestRegion(
                for: transform,
                incrementalRequestIndex: 1,
                regionTimeoutStreak: 0
            )
        )
        XCTAssertNil(
            policy.requestRegion(
                for: transform,
                incrementalRequestIndex: 3,
                regionTimeoutStreak: 0
            )
        )
        XCTAssertNil(
            policy.requestRegion(
                for: transform,
                incrementalRequestIndex: 4,
                regionTimeoutStreak: 1
            )
        )
    }

    func testPhonePortraitCropFillShapeKeepsFullHeightAndNarrowsWidth() throws {
        let framebuffer = CGSize(width: 1920, height: 1080)
        let view = CGSize(width: 390, height: 844)
        let fit = ViewportTransform(framebufferSize: framebuffer, viewSize: view)
        let fillZoom = max(
            view.width / framebuffer.width,
            view.height / framebuffer.height
        ) / fit.fitScale
        let transform = ViewportTransform(
            framebufferSize: framebuffer,
            viewSize: view,
            zoomScale: fillZoom
        )

        let region = try XCTUnwrap(
            transform.visibleFramebufferUpdateRegion(expansionMarginPixels: 0)
        )

        XCTAssertEqual(region.y, 0)
        XCTAssertEqual(region.height, 1080)
        XCTAssertGreaterThan(region.x, 0)
        XCTAssertLessThan(Int(region.width), 1920)
    }
}
