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

    func testOperationRecoveryOnlyReplacesAnEmptyFailedViewport() {
        XCTAssertTrue(
            NaruRemoteAppShell.showsOperationRecovery(
                sessionState: .failed,
                hasFramebuffer: false
            )
        )
        XCTAssertTrue(
            NaruRemoteAppShell.showsOperationRecovery(
                sessionState: .closed,
                hasFramebuffer: false
            )
        )
        XCTAssertFalse(
            NaruRemoteAppShell.showsOperationRecovery(
                sessionState: .connecting,
                hasFramebuffer: false
            )
        )
        XCTAssertFalse(
            NaruRemoteAppShell.showsOperationRecovery(
                sessionState: .failed,
                hasFramebuffer: true
            )
        )
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
