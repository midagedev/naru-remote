import NaruRemoteCore
import XCTest
@testable import NaruRemoteApp

final class ConnectionGridCardFailureDerivationTests: XCTestCase {
    func testFailureAnnotatesOnlyTheFailedProfileCard() throws {
        let failed = try ConnectionProfile(displayName: "Failed Desk", host: "failed.tailnet.ts.net")
        let other = try ConnectionProfile(displayName: "Other Desk", host: "other.tailnet.ts.net")
        let session = RemoteSession(
            profileID: failed.id,
            state: .failed,
            hudMessage: "Credential unavailable",
            lastError: "Credential unavailable"
        )
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [failed, other],
            session: session
        )

        XCTAssertEqual(
            snapshot.connectionGridCards.first { $0.id == failed.id }?.failure?.message,
            "Credential unavailable"
        )
        XCTAssertNil(snapshot.connectionGridCards.first { $0.id == other.id }?.failure)
    }

    func testConnectingClearsCardFailureEvenIfPriorErrorRemainsOnSession() throws {
        let profile = try ConnectionProfile(displayName: "Retry Desk", host: "retry.tailnet.ts.net")
        let other = try ConnectionProfile(displayName: "Idle Desk", host: "idle.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .connecting,
            hudMessage: "Connecting to retry.tailnet.ts.net:5900",
            lastError: "Credential unavailable"
        )
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile, other],
            session: session
        )

        XCTAssertNil(snapshot.connectionGridCards.first { $0.id == profile.id }?.failure)
        XCTAssertNil(snapshot.connectionGridCards.first { $0.id == other.id }?.failure)
    }

    /// A user-initiated disconnect ends as `.closed` with
    /// `hudMessage = "Disconnected"` and no `lastError`
    /// (`NaruRemoteAppModel.disconnect()`). Leaving normally is not a
    /// failure, so the card must stay clean.
    func testUserDisconnectDoesNotAnnotateTheCard() throws {
        let profile = try ConnectionProfile(displayName: "Closed Desk", host: "closed.tailnet.ts.net")
        let other = try ConnectionProfile(displayName: "Quiet Desk", host: "quiet.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .closed,
            hudMessage: "Disconnected",
            lastError: nil
        )
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile, other],
            session: session
        )

        XCTAssertNil(snapshot.connectionGridCards.first { $0.id == profile.id }?.failure)
        XCTAssertNil(snapshot.connectionGridCards.first { $0.id == other.id }?.failure)
    }

    /// A closed session that did carry a failure reason still annotates.
    func testClosedSessionWithFailureReasonAnnotatesOnlyItsCard() throws {
        let profile = try ConnectionProfile(displayName: "Closed Desk", host: "closed.tailnet.ts.net")
        let other = try ConnectionProfile(displayName: "Quiet Desk", host: "quiet.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .closed,
            hudMessage: "Disconnected",
            lastError: "Credential unavailable"
        )
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile, other],
            session: session
        )

        XCTAssertEqual(
            snapshot.connectionGridCards.first { $0.id == profile.id }?.failure?.message,
            "Credential unavailable"
        )
        XCTAssertNil(snapshot.connectionGridCards.first { $0.id == other.id }?.failure)
    }

    func testFailedSessionWithFramebufferDoesNotAnnotateAnyCard() throws {
        let profile = try ConnectionProfile(displayName: "Framed Desk", host: "framed.tailnet.ts.net")
        let other = try ConnectionProfile(displayName: "Spare Desk", host: "spare.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .failed,
            hudMessage: "Connection lost. Please reconnect.",
            lastError: "Connection lost. Please reconnect."
        )
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile, other],
            session: session,
            latestFramebuffer: RFBRawFramebuffer(width: 4, height: 4)
        )

        XCTAssertNil(snapshot.connectionGridCards.first { $0.id == profile.id }?.failure)
        XCTAssertNil(snapshot.connectionGridCards.first { $0.id == other.id }?.failure)
    }
}
