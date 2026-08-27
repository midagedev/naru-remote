import XCTest
@testable import NaruRemoteCore

/// Spec 039 FR-003. The screen staying on is not testable from here — the idle
/// timer belongs to `UIApplication`. The *decision* is, and the decision is the
/// half that had a hole in it: a hold that is raised on one path and released
/// on none.
final class ScreenWakePolicyTests: XCTestCase {

    func testAConnectionBeingWatchedHoldsTheScreenOn() {
        let resolution = ScreenWakePolicy.resolve(
            sessionState: .active,
            hasFramebuffer: true,
            isAppForeground: true,
            userKeepsScreenAwake: true
        )

        XCTAssertEqual(resolution.decision, .holdAwake)
        XCTAssertEqual(resolution.reason, .sessionLive)
    }

    /// The reason this feature exists. Watching a build run is, to auto-lock,
    /// indistinguishable from having put the phone down.
    func testAnActiveSessionWithNoInputStillHoldsTheScreenOn() {
        // Nothing here says "the user touched something recently", because
        // nothing about the policy depends on that. That is the point.
        let resolution = ScreenWakePolicy.resolve(
            sessionState: .active,
            hasFramebuffer: true,
            isAppForeground: true,
            userKeepsScreenAwake: true
        )

        XCTAssertTrue(resolution.holdsAwake)
    }

    func testConnectingHoldsTheScreenOnBeforeTheFirstFrameArrives() {
        let resolution = ScreenWakePolicy.resolve(
            sessionState: .connecting,
            hasFramebuffer: false,
            isAppForeground: true,
            userKeepsScreenAwake: true
        )

        XCTAssertTrue(
            resolution.holdsAwake,
            "Reaching a Mac over a tunnel is when the user is watching hardest"
        )
    }

    func testNoSessionLetsTheScreenSleep() {
        let resolution = ScreenWakePolicy.resolve(
            sessionState: nil,
            hasFramebuffer: false,
            isAppForeground: true,
            userKeepsScreenAwake: true
        )

        XCTAssertEqual(resolution.decision, .allowSleep)
        XCTAssertEqual(resolution.reason, .noSession)
    }

    /// The leak this policy exists to prevent. The last frame stays on screen
    /// after a drop so the user can read what was there, and a `hasFramebuffer`
    /// check on its own would read that still image as a live session forever.
    func testATerminalSessionReleasesTheHoldEvenWithAFrameStillOnScreen() {
        for state in [RemoteSessionState.failed, .closed] {
            let resolution = ScreenWakePolicy.resolve(
                sessionState: state,
                hasFramebuffer: true,
                isAppForeground: true,
                userKeepsScreenAwake: true
            )

            XCTAssertEqual(
                resolution.decision,
                .allowSleep,
                "\(state.identifier) must not keep the phone awake"
            )
            XCTAssertEqual(resolution.reason, .noSession)
        }
    }

    func testLeavingTheAppReleasesTheHold() {
        let resolution = ScreenWakePolicy.resolve(
            sessionState: .active,
            hasFramebuffer: true,
            isAppForeground: false,
            userKeepsScreenAwake: true
        )

        XCTAssertEqual(resolution.decision, .allowSleep)
        XCTAssertEqual(resolution.reason, .appNotForeground)
    }

    func testTheUserSwitchingItOffWins() {
        let resolution = ScreenWakePolicy.resolve(
            sessionState: .active,
            hasFramebuffer: true,
            isAppForeground: true,
            userKeepsScreenAwake: false
        )

        XCTAssertEqual(resolution.decision, .allowSleep)
        XCTAssertEqual(resolution.reason, .userDeclined)
    }

    /// A reconnect is the worst possible moment to dim: the session is coming
    /// back and the user is deciding whether to wait.
    func testReconnectingKeepsTheHold() {
        let resolution = ScreenWakePolicy.resolve(
            sessionState: .reconnecting(attempt: 2, of: 6),
            hasFramebuffer: true,
            isAppForeground: true,
            userKeepsScreenAwake: true
        )

        XCTAssertTrue(resolution.holdsAwake)
    }

    /// Every state resolves. A `switch` that grew a case and forgot the hold is
    /// the recurrence shape, and this is the assertion that would catch it.
    func testEveryLiveStateIsDecidedAndNoStateIsUndecidable() {
        let states: [RemoteSessionState] = [
            .connecting, .authenticating, .active, .degraded,
            .reconnecting(attempt: 1, of: 6), .failed, .closed
        ]
        let live = Set(["connecting", "authenticating", "active", "degraded", "reconnecting"])

        for state in states {
            let holds = ScreenWakePolicy.isSessionLive(
                sessionState: state,
                hasFramebuffer: false
            )
            XCTAssertEqual(
                holds,
                live.contains(state.identifier),
                "\(state.identifier) is on the wrong side of the live/terminal line"
            )
        }
    }

    // MARK: - Settings

    func testTheHoldIsOnByDefault() {
        XCTAssertTrue(AppSettings().keepsScreenAwakeDuringSession)
    }

    func testAnOlderSettingsFileWithoutTheKeyKeepsTheHold() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data("{}".utf8)
        )

        XCTAssertTrue(settings.keepsScreenAwakeDuringSession)
    }

    func testSwitchingTheHoldOffSurvivesARoundTrip() throws {
        var settings = AppSettings()
        settings.keepsScreenAwakeDuringSession = false

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertFalse(decoded.keepsScreenAwakeDuringSession)
    }

    /// The default stays out of the file, so `{}` remains the default document
    /// and a future default change is not fought by every existing install.
    func testTheDefaultIsNotWrittenToTheFile() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        let json = String(decoding: encoded, as: UTF8.self)

        XCTAssertFalse(json.contains("keepsScreenAwakeDuringSession"))
    }
}
