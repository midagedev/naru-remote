import XCTest

/// Founder report, build 10: "pip 모드 두 번 켜면 앱이 꺼진다" — entering PiP
/// Watch a second time in one session terminates the app.
///
/// The suspicion is structural rather than incidental: `startPiPWatch()`
/// calls `prepareController(_:)` on every entry, and the iOS controller's
/// `prepare(layerHost:)` builds a **new** `AVPictureInPictureController`
/// over the **same** `AVSampleBufferDisplayLayer` each time. This test
/// asserts the only thing a user cares about — the app is still running
/// after the second entry — so it stays valid whatever AVKit's precise
/// objection turns out to be.
///
/// The session state comes from the `session-active-widescreen` fixture so
/// the run needs no socket: PiP Watch requires a session that has received
/// a frame, which the fixture provides.
@MainActor
final class PiPWatchReentryUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testEnteringPiPWatchTwiceKeepsTheAppAlive() throws {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = "session-active-widescreen"
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-pip-reentry-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
            .path
        app.launch()

        guard tapPiPWatch(in: app) else {
            throw XCTSkip("PiP Watch is not offered on this runner — nothing to re-enter.")
        }

        // The system PiP transition happens outside the app's process; give
        // it a moment, then bring the app back the way a user would.
        _ = app.wait(for: .runningForeground, timeout: 3)
        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 8),
            "The app must survive the first PiP entry."
        )

        let secondEntryOffered = tapPiPWatch(in: app)

        XCTAssertTrue(
            app.state == .runningForeground || app.state == .runningBackground,
            "Entering PiP Watch a second time must not terminate the app "
                + "(observed state: \(app.state.rawValue))."
        )
        XCTAssertTrue(
            secondEntryOffered,
            "PiP Watch must stay reachable for a second entry in the same session."
        )
        XCTAssertTrue(
            app.otherElements["naru.session.viewport"].waitForExistence(timeout: 8),
            "The session viewport must still be on screen after a second PiP entry."
        )
    }

    /// Reveals the immersive control bar if it has auto-hidden and taps the
    /// PiP control, which spec 033 moved out of the tools menu and into the
    /// bar. Returns `false` when the affordance is absent or disabled, which
    /// is the runner-capability case rather than a failure.
    private func tapPiPWatch(in app: XCUIApplication) -> Bool {
        let reveal = app.buttons["naru.session.controls.reveal"]
        if reveal.waitForExistence(timeout: 2), reveal.isHittable {
            reveal.tap()
        }

        let pip = app.buttons["naru.session.pipWatch"]
        guard pip.waitForExistence(timeout: 6) else {
            return false
        }
        guard pip.isEnabled, pip.isHittable else {
            return false
        }
        pip.tap()
        return true
    }
}
