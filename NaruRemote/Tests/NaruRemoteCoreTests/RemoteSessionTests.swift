import XCTest
@testable import NaruRemoteCore

final class RemoteSessionTests: XCTestCase {
    func testSessionBecomesActiveWhenFirstFrameArrives() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        var session = RemoteSession(profileID: profile.id)
        let frameDate = Date(timeIntervalSince1970: 100)

        session.markFirstFrameReceived(at: frameDate)

        XCTAssertEqual(session.state, .active)
        XCTAssertEqual(session.lastFrameAt, frameDate)
        XCTAssertEqual(session.hudMessage, "Connected")
    }

    func testSessionFailureRetainsProfileIdentity() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        var session = RemoteSession(profileID: profile.id)

        session.markFailed("VNC handshake failed")

        XCTAssertEqual(session.profileID, profile.id)
        XCTAssertEqual(session.state, .failed)
        XCTAssertEqual(session.lastError, "VNC handshake failed")
    }
}
