import XCTest
@testable import NaruRemoteCore

final class PiPWatchSessionTests: XCTestCase {
    func testPiPWatchSessionStartsAsWatchOnlyForActiveSession() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 99)
        )
        let startedAt = Date(timeIntervalSince1970: 100)
        let frame = PiPFrameSnapshot(
            width: 1024,
            height: 768,
            capturedAt: Date(timeIntervalSince1970: 101),
            changeActivity: .moderate
        )
        var watchSession = PiPWatchSession(sessionID: session.id)

        watchSession.prepare(from: session, at: startedAt)
        watchSession.markWatching(frame: frame)

        XCTAssertEqual(watchSession.state, .watching)
        XCTAssertEqual(watchSession.startedAt, startedAt)
        XCTAssertEqual(watchSession.lastFrame, frame)
        XCTAssertEqual(watchSession.inputPolicy, .watchOnly)
        XCTAssertFalse(watchSession.allowsRemoteInputFromPiP)
    }

    func testPiPWatchSessionRejectsInactiveSession() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .connecting)
        var watchSession = PiPWatchSession(sessionID: session.id)

        watchSession.prepare(from: session)

        XCTAssertEqual(watchSession.state, .unavailable)
        XCTAssertEqual(watchSession.safeMessage, "PiP Watch is unavailable for this session state.")
    }

    func testPiPWatchSessionRejectsActiveSessionWithoutFrame() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        var watchSession = PiPWatchSession(sessionID: session.id)

        watchSession.prepare(from: session)

        XCTAssertEqual(watchSession.state, .unavailable)
        XCTAssertEqual(watchSession.safeMessage, "PiP Watch is available after a remote frame is active.")
    }

    func testPiPWatchSessionHonorsProfileOptOut() throws {
        let profile = try ConnectionProfile(
            displayName: "Sensitive Desk",
            host: "sensitive.tailnet.ts.net",
            allowsPiPWatch: false
        )
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 99)
        )
        var watchSession = PiPWatchSession(sessionID: session.id)

        watchSession.prepare(from: session, profileAllowsPiPWatch: profile.allowsPiPWatch)

        XCTAssertEqual(watchSession.state, .unavailable)
        XCTAssertEqual(watchSession.safeMessage, "PiP Watch is disabled for this profile.")
    }

    func testPiPFramePolicyUsesAdaptiveIntervals() {
        let policy = PiPFramePolicy(
            idleFrameInterval: 2.0,
            moderateFrameInterval: 0.5,
            highFrameInterval: 0.1,
            staleAfter: 5.0
        )

        XCTAssertEqual(policy.targetFrameInterval(for: .idle), 2.0)
        XCTAssertEqual(policy.targetFrameInterval(for: .moderate), 0.5)
        XCTAssertEqual(policy.targetFrameInterval(for: .high), 0.1)
    }

    func testPiPWatchSessionMarksStaleFrameWithoutFailingMainSession() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 10)
        )
        let oldFrame = PiPFrameSnapshot(
            width: 1024,
            height: 768,
            capturedAt: Date(timeIntervalSince1970: 10),
            changeActivity: .idle
        )
        var watchSession = PiPWatchSession(
            sessionID: session.id,
            framePolicy: PiPFramePolicy(staleAfter: 3)
        )

        watchSession.prepare(from: session, at: Date(timeIntervalSince1970: 11))
        watchSession.markWatching(frame: oldFrame)
        watchSession.refreshStaleness(now: Date(timeIntervalSince1970: 14))

        XCTAssertEqual(watchSession.state, .stale)
        XCTAssertEqual(watchSession.safeMessage, "PiP frame is stale; main session remains available.")
        XCTAssertEqual(session.state, .active)
    }

    func testPiPWatchSessionRejectsUnpreparedFrame() {
        let frame = PiPFrameSnapshot(width: 1024, height: 768)
        var watchSession = PiPWatchSession(sessionID: UUID())

        watchSession.markWatching(frame: frame)

        XCTAssertEqual(watchSession.state, .failed)
        XCTAssertEqual(watchSession.safeMessage, "PiP Watch must be prepared before frames are shown.")
    }

    func testPiPWatchSessionRejectsUnrenderableFrame() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 99)
        )
        var watchSession = PiPWatchSession(sessionID: session.id)

        watchSession.prepare(from: session)
        watchSession.markWatching(frame: PiPFrameSnapshot(width: 0, height: 768))

        XCTAssertEqual(watchSession.state, .failed)
        XCTAssertEqual(watchSession.safeMessage, "PiP frame cannot be rendered.")
    }
}
