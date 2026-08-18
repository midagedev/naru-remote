import NaruRemoteCore
import XCTest
@testable import NaruRemoteApp

/// Spec 013 US-4: connecting happens on the host list, so the card that was
/// tapped is what reports it.
final class ConnectionGridCardConnectingDerivationTests: XCTestCase {

    func testConnectingAnnotatesOnlyItsOwnCard() throws {
        let profile = try ConnectionProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
        let other = try ConnectionProfile(displayName: "Spare Desk", host: "spare.tailnet.ts.net")
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile, other],
            session: RemoteSession(profileID: profile.id, state: .connecting)
        )

        XCTAssertEqual(
            snapshot.connectionGridCards.first { $0.id == profile.id }?.connecting?.label,
            "Connecting…"
        )
        XCTAssertNil(snapshot.connectionGridCards.first { $0.id == other.id }?.connecting)
    }

    func testAuthenticatingReportsItsOwnLabel() throws {
        let profile = try ConnectionProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            session: RemoteSession(profileID: profile.id, state: .authenticating)
        )

        XCTAssertEqual(
            snapshot.connectionGridCards.first?.connecting?.label,
            "Authenticating…"
        )
    }

    /// Once a frame exists the user is on remote control, so a progress row on
    /// the list behind it would be describing a screen they already left.
    func testAFramebufferClearsTheConnectingRow() throws {
        let profile = try ConnectionProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            session: RemoteSession(profileID: profile.id, state: .connecting),
            latestFramebuffer: RFBRawFramebuffer(width: 4, height: 4)
        )

        XCTAssertNil(snapshot.connectionGridCards.first?.connecting)
    }

    func testTerminalAndLiveStatesDoNotReportProgress() throws {
        let profile = try ConnectionProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
        let states: [RemoteSessionState] = [
            .active, .degraded, .reconnecting(attempt: 1, of: 3), .failed, .closed
        ]

        for state in states {
            let snapshot = NaruRemoteAppSnapshot(
                profiles: [profile],
                session: RemoteSession(profileID: profile.id, state: state)
            )
            XCTAssertNil(
                snapshot.connectionGridCards.first?.connecting,
                "\(state) is not connect progress"
            )
        }
    }

    /// The card must not become a channel for session text (constitution §IV):
    /// the label comes from a fixed vocabulary, never from the session.
    func testTheLabelIgnoresSessionSuppliedText() throws {
        let profile = try ConnectionProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            session: RemoteSession(
                profileID: profile.id,
                state: .connecting,
                hudMessage: "resolving studio.tailnet.ts.net:5900 via 100.64.0.7"
            )
        )

        XCTAssertEqual(snapshot.connectionGridCards.first?.connecting?.label, "Connecting…")
    }

    /// A session belonging to another profile must not spill onto this card.
    func testAnotherProfilesSessionLeavesTheCardAlone() throws {
        let profile = try ConnectionProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
        let other = try ConnectionProfile(displayName: "Spare Desk", host: "spare.tailnet.ts.net")
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile, other],
            session: RemoteSession(profileID: other.id, state: .connecting)
        )

        XCTAssertNil(snapshot.connectionGridCards.first { $0.id == profile.id }?.connecting)
    }
}
