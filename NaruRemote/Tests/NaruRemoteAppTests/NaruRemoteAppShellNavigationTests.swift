import NaruRemoteCore
import XCTest
@testable import NaruRemoteApp

final class NaruRemoteAppShellNavigationTests: XCTestCase {
    // The grid is now a pure function of "is remote control on", which is
    // itself derived from session facts (`RemoteControlSurfacePolicy`).
    // Spec 013 US-4: connecting stays here, on the host list.

    func testSavedProfileLaunchShowsConnectionGrid() {
        XCTAssertTrue(
            NaruRemoteAppShell.shouldShowConnectionGrid(
                isEmptyHome: false,
                showsRemoteControlSurface: false
            )
        )
    }

    func testRemoteControlHidesConnectionGrid() {
        XCTAssertFalse(
            NaruRemoteAppShell.shouldShowConnectionGrid(
                isEmptyHome: false,
                showsRemoteControlSurface: true
            )
        )
    }

    func testEmptyHomeRemainsPrimaryWithoutProfiles() {
        XCTAssertFalse(
            NaruRemoteAppShell.shouldShowConnectionGrid(
                isEmptyHome: true,
                showsRemoteControlSurface: false
            )
        )
    }

    func testConnectingKeepsTheHostListOnScreen() {
        // The regression the founder reported from a device on 2026-08-19:
        // tapping a card used to open an empty remote-control screen while
        // the connection was still being made.
        for state in [RemoteSessionState.connecting, .authenticating] {
            XCTAssertTrue(
                NaruRemoteAppShell.shouldShowConnectionGrid(
                    isEmptyHome: false,
                    showsRemoteControlSurface: RemoteControlSurfacePolicy.showsRemoteControl(
                        sessionState: state,
                        hasFramebuffer: false
                    )
                ),
                "\(state) must keep the host list on screen"
            )
        }
    }

    func testFirstFrameOpensRemoteControl() {
        XCTAssertFalse(
            NaruRemoteAppShell.shouldShowConnectionGrid(
                isEmptyHome: false,
                showsRemoteControlSurface: RemoteControlSurfacePolicy.showsRemoteControl(
                    sessionState: .active,
                    hasFramebuffer: true
                )
            )
        )
    }

    func testFailedOrClosedReturnsToTheHostList() {
        for state in [RemoteSessionState.failed, .closed] {
            XCTAssertTrue(
                NaruRemoteAppShell.shouldShowConnectionGrid(
                    isEmptyHome: false,
                    showsRemoteControlSurface: RemoteControlSurfacePolicy.showsRemoteControl(
                        sessionState: state,
                        hasFramebuffer: false
                    )
                )
            )
        }
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
