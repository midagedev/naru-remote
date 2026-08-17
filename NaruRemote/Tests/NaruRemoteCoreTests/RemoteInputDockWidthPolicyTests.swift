import XCTest
@testable import NaruRemoteCore

/// Spec 012 US3-1 — iPad regular-width pinned dock caps at 720 pt
/// (orca `CONTENT_MAX_WIDTH`); compact / floating stay unchanged.
final class RemoteInputDockWidthPolicyTests: XCTestCase {
    func testRegularPinnedColumnCapsAt720() {
        XCTAssertEqual(RemoteInputDockWidthPolicy.regularPinnedContentMaxWidth, 720)
        XCTAssertEqual(
            RemoteInputDockWidthPolicy.pinnedColumnMaxWidth(
                isCompactSizeClass: false,
                windowWidth: 1024
            ),
            720
        )
        XCTAssertEqual(
            RemoteInputDockWidthPolicy.pinnedColumnMaxWidth(
                isCompactSizeClass: false,
                windowWidth: nil
            ),
            720
        )
    }

    func testCompactPinnedColumnKeepsWindowWidth() {
        XCTAssertEqual(
            RemoteInputDockWidthPolicy.pinnedColumnMaxWidth(
                isCompactSizeClass: true,
                windowWidth: 390
            ),
            390
        )
        XCTAssertNil(
            RemoteInputDockWidthPolicy.pinnedColumnMaxWidth(
                isCompactSizeClass: true,
                windowWidth: nil
            )
        )
    }

    func testFloatingOverlayIsNotCappedOnRegularWidth() {
        XCTAssertNil(
            RemoteInputDockWidthPolicy.floatingOverlayWidth(
                isCompactSizeClass: false,
                windowWidth: 1024
            ),
            "Floating pill is content-sized; no 720 cap."
        )
        XCTAssertEqual(
            RemoteInputDockWidthPolicy.floatingOverlayWidth(
                isCompactSizeClass: true,
                windowWidth: 390
            ),
            390
        )
    }
}
