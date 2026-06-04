import XCTest

/// FR-001 verification (T042 in `specs/002-direct-keystroke-mode/tasks.md`).
///
/// Asserts that toggling into Direct mode swaps the input surface to
/// the app's custom soft keyboard AND keeps the iOS system keyboard
/// off-screen.  The negative assertion on `app.keyboards.firstMatch`
/// is the load-bearing one: FR-001 says the iOS keyboard must not
/// appear in Direct mode because raw keystroke streaming and IME
/// composition cannot share the same surface.
///
/// Pure assertion test — no screenshots; the screenshot-evidence
/// tests already live in `DirectKeystrokeKeyboardScreenshotsUITests`
/// and are frozen as artifacts.
@MainActor
final class DirectKeystrokeFR001UITests: XCTestCase {

    func testDirectModeShowsCustomKeyboardAndHidesIOSKeyboard() {
        let app = launchAppWithEmptyProfileStore()

        XCTAssertTrue(
            app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8),
            "Remote Input Dock heading must be visible after launch"
        )

        // Toggle into Direct mode via the segmented mode picker.  We
        // anchor on the "Direct" segment button because the picker's
        // `accessibilityIdentifier` is sometimes consumed by an
        // ancestor (same finding as the screenshot tests).
        let directSegment = app.buttons["Direct"]
        XCTAssertTrue(
            directSegment.waitForExistence(timeout: 4),
            "Direct segment of the input mode picker must exist"
        )
        directSegment.tap()

        // Custom QWERTY keyboard must appear.  The container element
        // identifier `naru.direct.keyboard.qwerty` is set on a
        // SwiftUI VStack; in some snapshots the ancestor obscures it
        // so we ALSO assert against the `q` key, which always lives
        // in the accessibility tree.
        let customKeyboardContainer = app.otherElements["naru.direct.keyboard.qwerty"]
        let qKey = app.buttons["Key q"]
        let customKeyboardVisible =
            customKeyboardContainer.waitForExistence(timeout: 3)
            || qKey.waitForExistence(timeout: 3)
        XCTAssertTrue(
            customKeyboardVisible,
            "Naru's custom QWERTY keyboard must render after switching to Direct mode"
        )

        // FR-001 negative assertion: iOS system keyboard MUST NOT be
        // present.  `app.keyboards` is XCUITest's first-class query
        // for the system keyboard; if it has any match, the iOS
        // keyboard is up and the contract is violated.
        XCTAssertFalse(
            app.keyboards.firstMatch.exists,
            "iOS system keyboard must not appear in Direct mode (FR-001)"
        )

        // Toggle back to Compose; the custom keyboard must go away.
        let composeSegment = app.buttons["Compose"]
        XCTAssertTrue(composeSegment.waitForExistence(timeout: 2))
        composeSegment.tap()

        XCTAssertTrue(
            qKey.waitForNonExistence(timeout: 3),
            "Custom keyboard must disappear after toggling back to Compose"
        )
    }

    // MARK: - Helpers

    private func launchAppWithEmptyProfileStore() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = "studio.tailnet.ts.net"
        app.launchEnvironment["NARU_TEST_START_PROFILE_DETAIL"] = "1"
        // Suppress the first-entry warning dialog — this test is
        // about FR-001 (custom keyboard / iOS keyboard absence), not
        // FR-009 (warning dialog), and the dialog would block the
        // keyboard-visibility query.  FR-009 is covered by the sister
        // file `DirectKeystrokeFR009UITests`.
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
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
