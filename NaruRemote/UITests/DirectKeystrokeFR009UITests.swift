import XCTest

/// FR-009 verification (T043 in `specs/002-direct-keystroke-mode/tasks.md`).
///
/// Asserts the one-time-per-session entry-warning dialog contract:
///
/// 1. First Direct-mode entry of a fresh session shows the warning
///    ("Got it" confirmation button).
/// 2. After dismissing once and toggling back to Compose, re-entering
///    Direct mode in the same session does NOT show the warning.
///
/// The dialog's button label "Got it" is sourced from
/// `NaruRemote/App/Features/RemoteInputDock/DirectModeWarningDialog.swift`.
/// Anchor on the button rather than the dialog title because SwiftUI
/// `confirmationDialog` exposes its action button reliably across
/// iPhone / iPad layouts while the title element placement varies.
///
/// Pure assertion test — no screenshots; the screenshot-evidence
/// test already lives in `DirectKeystrokeBadgeAndWarningScreenshotsUITests`
/// and is frozen as artifact.
@MainActor
final class DirectKeystrokeFR009UITests: XCTestCase {

    func testWarningShowsOnFirstDirectModeEntryOfFreshSession() {
        let app = launchAppWithEmptyProfileStoreWithoutSuppressingWarning()

        XCTAssertTrue(
            app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8),
            "Remote Input Dock heading must be visible after launch"
        )

        let directSegment = app.buttons["Direct"]
        XCTAssertTrue(directSegment.waitForExistence(timeout: 4))
        directSegment.tap()

        // SwiftUI `confirmationDialog` exposes the action button
        // twice in the a11y tree (parent + inner element).  Use
        // `firstMatch` to disambiguate (same disambiguation pattern
        // as `DirectKeystrokeBadgeAndWarningScreenshotsUITests`).
        let confirm = app.buttons["Got it"].firstMatch
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 4),
            "Direct-mode entry warning must show on first activation of a fresh session (FR-009)"
        )

        confirm.tap()

        XCTAssertTrue(
            confirm.waitForNonExistence(timeout: 3),
            "Warning dialog must dismiss after tapping Got it"
        )
    }

    func testWarningDoesNotShowOnSecondDirectModeEntryInSameSession() {
        let app = launchAppWithEmptyProfileStoreWithoutSuppressingWarning()

        XCTAssertTrue(
            app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8),
            "Remote Input Dock heading must be visible after launch"
        )

        // First entry — dismiss the warning so the
        // `hasShownEntryWarningThisSession` flag flips.
        let directSegment = app.buttons["Direct"]
        XCTAssertTrue(directSegment.waitForExistence(timeout: 4))
        directSegment.tap()

        let confirm = app.buttons["Got it"].firstMatch
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 4),
            "Warning must show on first entry so we have a baseline to dismiss"
        )
        confirm.tap()
        XCTAssertTrue(
            confirm.waitForNonExistence(timeout: 3),
            "Warning must dismiss before we can test the second-entry contract"
        )

        // Toggle back to Compose, then back to Direct.
        let composeSegment = app.buttons["Compose"]
        XCTAssertTrue(composeSegment.waitForExistence(timeout: 2))
        composeSegment.tap()

        // Anchor on the QWERTY page disappearing so we know the
        // toggle-out actually settled before re-toggling in.
        XCTAssertTrue(
            app.buttons["Key q"].waitForNonExistence(timeout: 3),
            "Custom keyboard must dismiss after toggling back to Compose"
        )

        let directAgain = app.buttons["Direct"]
        XCTAssertTrue(directAgain.waitForExistence(timeout: 2))
        directAgain.tap()

        // Custom keyboard must reappear (positive control — proves
        // the second toggle actually fired).
        XCTAssertTrue(
            app.buttons["Key q"].waitForExistence(timeout: 4),
            "Custom keyboard must reappear after second toggle into Direct mode"
        )

        // FR-009 negative: warning must NOT come back this session.
        // `waitForNonExistence` confirms the dialog never appears
        // within the timeout window after the second toggle.
        XCTAssertTrue(
            confirm.waitForNonExistence(timeout: 2),
            "Warning dialog must not reappear on second Direct-mode entry of the same session (FR-009)"
        )
    }

    // MARK: - Helpers

    private func launchAppWithEmptyProfileStoreWithoutSuppressingWarning() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = "studio.tailnet.ts.net"
        app.launchEnvironment["NARU_TEST_START_PROFILE_DETAIL"] = "1"
        // CRITICAL: do NOT set NARU_TEST_SUPPRESS_DIRECT_WARNING here.
        // FR-009's contract is that the warning DOES fire on first
        // entry; the suppression hook would defeat the test.
        app.launch()
        return app
    }
}

private extension XCUIElement {
    /// Mirror of `waitForExistence` with the inverse predicate so the
    /// test can wait for an element to leave the tree without
    /// resorting to `sleep(...)` (forbidden by the agent's guidance).
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
