import XCTest
@testable import NaruRemoteCore

/// Contract for the two-screen rule (spec 013, extended 2026-08-19 after a
/// device report that connecting still read as a third screen).
final class RemoteControlSurfacePolicyTests: XCTestCase {

    // MARK: - Connecting belongs to the host list

    func testConnectingWithoutFrameStaysOnTheHostList() {
        XCTAssertEqual(
            RemoteControlSurfacePolicy.phase(sessionState: .connecting, hasFramebuffer: false),
            .connecting
        )
        XCTAssertFalse(
            RemoteControlSurfacePolicy.showsRemoteControl(
                sessionState: .connecting,
                hasFramebuffer: false
            )
        )
    }

    func testAuthenticatingWithoutFrameStaysOnTheHostList() {
        XCTAssertEqual(
            RemoteControlSurfacePolicy.phase(sessionState: .authenticating, hasFramebuffer: false),
            .connecting
        )
        XCTAssertFalse(
            RemoteControlSurfacePolicy.showsRemoteControl(
                sessionState: .authenticating,
                hasFramebuffer: false
            )
        )
    }

    /// Mid-session blip, not an entry: the user already has a remote screen,
    /// so a retry must not throw them back to the list.
    func testConnectingWithARetainedFrameStaysOnRemoteControl() {
        XCTAssertEqual(
            RemoteControlSurfacePolicy.phase(sessionState: .connecting, hasFramebuffer: true),
            .remoteControl
        )
    }

    // MARK: - Remote control opens only with something to control

    func testActiveOpensRemoteControl() {
        // `.active` is only reachable through `markFirstFrameReceived`.
        XCTAssertEqual(
            RemoteControlSurfacePolicy.phase(sessionState: .active, hasFramebuffer: true),
            .remoteControl
        )
    }

    func testDegradedAndReconnectingStayOnRemoteControl() {
        for state in [RemoteSessionState.degraded, .reconnecting(attempt: 1, of: 3)] {
            XCTAssertEqual(
                RemoteControlSurfacePolicy.phase(sessionState: state, hasFramebuffer: true),
                .remoteControl,
                "\(state) is a mid-session condition, not a return to the list"
            )
        }
    }

    // MARK: - Terminal states return to the list

    func testFailedReturnsToTheHostListEvenWithAStaleFrame() {
        XCTAssertEqual(
            RemoteControlSurfacePolicy.phase(sessionState: .failed, hasFramebuffer: true),
            .hostList,
            "A dropped session must not leave the user holding a frozen screen"
        )
    }

    func testClosedReturnsToTheHostListEvenWithAStaleFrame() {
        XCTAssertEqual(
            RemoteControlSurfacePolicy.phase(sessionState: .closed, hasFramebuffer: true),
            .hostList
        )
    }

    func testNoSessionIsTheHostList() {
        XCTAssertEqual(
            RemoteControlSurfacePolicy.phase(sessionState: nil, hasFramebuffer: false),
            .hostList
        )
        XCTAssertFalse(
            RemoteControlSurfacePolicy.showsRemoteControl(sessionState: nil, hasFramebuffer: false)
        )
    }

    // MARK: - Test pin

    func testScreenshotPinMountsRemoteControlWithoutASession() {
        XCTAssertTrue(
            RemoteControlSurfacePolicy.showsRemoteControl(
                sessionState: nil,
                hasFramebuffer: false,
                isPinnedForTesting: true
            ),
            "Dock captures mount the surface without a session on purpose"
        )
    }

    /// The audit captures that reach the dock by tapping a card need the host
    /// list to still be there to tap — so this hook must not preempt the grid
    /// before a session exists. Collapsing it into the unconditional pin made
    /// every card-tap capture fail to find a card.
    func testRetainHookKeepsTheListUntilASessionExists() {
        XCTAssertFalse(
            RemoteControlSurfacePolicy.showsRemoteControl(
                sessionState: nil,
                hasFramebuffer: false,
                retainsEndedSessionForTesting: true
            )
        )
        XCTAssertTrue(
            RemoteControlSurfacePolicy.showsRemoteControl(
                sessionState: .failed,
                hasFramebuffer: false,
                retainsEndedSessionForTesting: true
            ),
            "A capture of the dock over a deliberately failed session must not auto-return"
        )
    }

    /// The regression this rule exists for: no session state may put an empty
    /// remote-control surface on screen.
    func testRemoteControlIsNeverShownWithoutAFrame() {
        let states: [RemoteSessionState?] = [
            nil, .connecting, .authenticating, .failed, .closed
        ]
        for state in states {
            XCTAssertFalse(
                RemoteControlSurfacePolicy.showsRemoteControl(
                    sessionState: state,
                    hasFramebuffer: false
                ),
                "\(String(describing: state)) would show an empty remote-control screen"
            )
        }
    }
}
