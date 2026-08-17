import NaruRemoteCore
import XCTest
@testable import NaruRemoteApp

final class NaruRemoteAppShellNavigationTests: XCTestCase {
    func testSavedProfileLaunchShowsConnectionGrid() {
        XCTAssertTrue(
            NaruRemoteAppShell.shouldShowConnectionGrid(
                isEmptyHome: false,
                isLiveSession: false,
                showsOperationSurface: false
            )
        )
    }

    func testExplicitOperationAndLiveSessionHideConnectionGrid() {
        XCTAssertFalse(
            NaruRemoteAppShell.shouldShowConnectionGrid(
                isEmptyHome: false,
                isLiveSession: false,
                showsOperationSurface: true
            )
        )
        XCTAssertFalse(
            NaruRemoteAppShell.shouldShowConnectionGrid(
                isEmptyHome: false,
                isLiveSession: true,
                showsOperationSurface: false
            )
        )
    }

    func testEmptyHomeRemainsPrimaryWithoutProfiles() {
        XCTAssertFalse(
            NaruRemoteAppShell.shouldShowConnectionGrid(
                isEmptyHome: true,
                isLiveSession: false,
                showsOperationSurface: false
            )
        )
    }

    func testFailedOrClosedWithoutFramebufferLeavesOperationSurface() {
        XCTAssertTrue(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .failed,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
        XCTAssertTrue(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .closed,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
    }

    func testConnectingAndActiveStayOnOperationSurface() {
        XCTAssertFalse(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .connecting,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
        XCTAssertFalse(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .active,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
    }

    func testFailedWithFramebufferOrTestingPinStaysOnOperationSurface() {
        XCTAssertFalse(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .failed,
                hasFramebuffer: true,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
        XCTAssertFalse(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .failed,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: true
            )
        )
    }

    func testEditorSaveStaysOnHostListAfterAutomaticReturn() {
        // US1-5: auto-return already clears the operation surface, and the
        // profile editor is a sheet over the grid. Save does not flip
        // `showsOperationSurface`.
        XCTAssertTrue(
            SessionSurfaceRoutingPolicy.shouldLeaveOperationSurface(
                sessionState: .failed,
                hasFramebuffer: false,
                isOperationSurfaceVisible: true,
                isPinnedForTesting: false
            )
        )
        XCTAssertTrue(
            NaruRemoteAppShell.shouldShowConnectionGrid(
                isEmptyHome: false,
                isLiveSession: false,
                showsOperationSurface: false
            )
        )
    }

    func testDiagnosticCapsuleRendersOnlyDuringConnectingOrLiveSession() {
        XCTAssertTrue(NaruRemoteAppShell.showsDiagnosticCapsule(sessionState: .connecting))
        XCTAssertTrue(NaruRemoteAppShell.showsDiagnosticCapsule(sessionState: .authenticating))
        XCTAssertTrue(NaruRemoteAppShell.showsDiagnosticCapsule(sessionState: .active))
        XCTAssertTrue(NaruRemoteAppShell.showsDiagnosticCapsule(sessionState: .degraded))
        XCTAssertTrue(
            NaruRemoteAppShell.showsDiagnosticCapsule(
                sessionState: .reconnecting(attempt: 1, of: 3)
            )
        )
        XCTAssertFalse(NaruRemoteAppShell.showsDiagnosticCapsule(sessionState: .failed))
        XCTAssertFalse(NaruRemoteAppShell.showsDiagnosticCapsule(sessionState: .closed))
        XCTAssertFalse(NaruRemoteAppShell.showsDiagnosticCapsule(sessionState: nil))
    }

    func testOnlyAdvancedPublicCardsRequireConfirmationBeforeOperation() {
        XCTAssertTrue(
            NaruRemoteAppShell.requiresPublicConnectionConfirmation(
                hostKind: .advancedManualPublicEndpoint
            )
        )
        XCTAssertFalse(
            NaruRemoteAppShell.requiresPublicConnectionConfirmation(hostKind: .magicDNS)
        )
        XCTAssertFalse(
            NaruRemoteAppShell.requiresPublicConnectionConfirmation(hostKind: .privateAddress)
        )
    }

    func testDeleteFailureCreatesRetryStateWithFixedSafeMessage() throws {
        let profileID = UUID()

        let retryState = try XCTUnwrap(
            NaruRemoteAppShell.profileDeletionRetryState(
                profileID: profileID,
                result: .failed(.profileRemoval)
            )
        )

        XCTAssertEqual(retryState.profileID, profileID)
        XCTAssertEqual(retryState.failure, .profileRemoval)
        XCTAssertEqual(
            retryState.message,
            "Profile could not be removed on this device."
        )
    }

    func testSuccessfulDeleteDoesNotCreateRetryState() {
        XCTAssertNil(
            NaruRemoteAppShell.profileDeletionRetryState(
                profileID: UUID(),
                result: .succeeded
            )
        )
    }
}
