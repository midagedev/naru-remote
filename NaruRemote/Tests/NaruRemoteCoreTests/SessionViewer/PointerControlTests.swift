import CoreGraphics
import XCTest
@testable import NaruRemoteCore

final class PointerControlTests: XCTestCase {
    private let fb = CGSize(width: 1920, height: 1080)

    // MARK: PointerControlMode

    /// Trackpad since 2026-08-21 (spec 023 FR-001, founder direction). The
    /// previous assertion pinned `.directTouch`; this is a deliberate product
    /// change, not a relaxed gate.
    func testProductDefaultIsTrackpad() {
        XCTAssertEqual(PointerControlMode.productDefault, .trackpad)
        XCTAssertFalse(PointerControlMode.directTouch.isTrackpad)
        XCTAssertTrue(PointerControlMode.trackpad.isTrackpad)
    }

    // MARK: TrackpadCursor

    func testCenteredCursorIsMiddleOfFramebufferAndVisible() {
        let cursor = TrackpadCursor.centered(in: fb)
        XCTAssertEqual(cursor.position.x, 960, accuracy: 1e-6)
        XCTAssertEqual(cursor.position.y, 540, accuracy: 1e-6)
        XCTAssertTrue(cursor.isVisible)
    }

    func testRelativeMoveScalesByDisplayScaleAndSensitivity() {
        let cursor = TrackpadCursor(position: CGPoint(x: 100, y: 100), isVisible: true)
        // displayScale 0.5 means 1 view point == 2 framebuffer pixels;
        // sensitivity 1 → a 50pt drag moves 100px.
        let moved = cursor.moved(
            byViewDelta: CGSize(width: 50, height: 0),
            displayScale: 0.5,
            sensitivity: 1,
            framebufferSize: fb
        )
        XCTAssertEqual(moved.position.x, 200, accuracy: 1e-6)
        XCTAssertEqual(moved.position.y, 100, accuracy: 1e-6)
        XCTAssertTrue(moved.isVisible)
    }

    func testRelativeMoveClampsToFramebufferBounds() {
        let cursor = TrackpadCursor(position: CGPoint(x: 1900, y: 100), isVisible: true)
        let moved = cursor.moved(
            byViewDelta: CGSize(width: 10_000, height: -10_000),
            displayScale: 1,
            sensitivity: 1,
            framebufferSize: fb
        )
        XCTAssertEqual(moved.position.x, 1919, accuracy: 1e-6)
        XCTAssertEqual(moved.position.y, 0, accuracy: 1e-6)
    }

    // MARK: RFBPointerCommand

    func testClickProducesDownThenUpAtSamePoint() {
        let commands = RFBPointerCommand.click(mask: RFBPointerCommand.leftButton, x: 10, y: 20)
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0], RFBPointerCommand(buttonMask: 0x01, x: 10, y: 20))
        XCTAssertEqual(commands[1], RFBPointerCommand(buttonMask: 0x00, x: 10, y: 20))
    }

    func testClampRoundsAndBoundsCoordinate() {
        XCTAssertEqual(RFBPointerCommand.clamp(-5), 0)
        XCTAssertEqual(RFBPointerCommand.clamp(10.6), 11)
        XCTAssertEqual(RFBPointerCommand.clamp(70_000), UInt16.max)
        XCTAssertEqual(RFBPointerCommand.clamp(.nan), 0)
    }
}
