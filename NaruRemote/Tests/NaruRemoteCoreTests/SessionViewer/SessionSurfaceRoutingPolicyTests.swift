import XCTest
@testable import NaruRemoteCore

final class SessionSurfaceRoutingPolicyTests: XCTestCase {
    func testFailedWithoutFramebufferLeavesOperationSurface() {
        XCTAssertTrue(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .failed,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
    }

    func testClosedWithoutFramebufferLeavesOperationSurface() {
        XCTAssertTrue(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .closed,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
    }

    func testConnectingStaysOnOperationSurface() {
        XCTAssertFalse(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .connecting,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
    }

    func testActiveStaysOnOperationSurface() {
        XCTAssertFalse(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .active,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
    }

    func testFailedWithFramebufferStaysOnOperationSurface() {
        XCTAssertFalse(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .failed,
                hasFramebuffer: true,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
    }

    func testTestingPinKeepsFailedSessionOnOperationSurface() {
        XCTAssertFalse(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .failed,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: true
            )
        )
    }
}
