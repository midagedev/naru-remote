import XCTest

@MainActor
final class NaruRemoteLaunchUITests: XCTestCase {
    func testAppShellLaunchesOnIPadSimulator() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = launchAppWithEmptyProfileStore()

        XCTAssertTrue(app.staticTexts["Naru Remote"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Add a private VNC profile"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["First Run"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Private target"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Compose locally"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["No remote frame yet"].waitForExistence(timeout: 2))
        let pipWatchButton = app.buttons["PiP Watch"]
        XCTAssertTrue(pipWatchButton.waitForExistence(timeout: 2))
        XCTAssertFalse(pipWatchButton.isEnabled)
    }

    func testRemoteInputDockMovesAboveKeyboardWhileComposing() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = launchAppWithEmptyProfileStore()

        let editor = app.textViews["Remote input text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

        let verticalGap = keyboard.frame.minY - editor.frame.maxY
        XCTAssertGreaterThanOrEqual(verticalGap, 0)
        XCTAssertLessThan(verticalGap, 96)
    }

    func testAddProfileOpensProfileEditor() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = launchAppWithEmptyProfileStore()

        let addProfile = app.buttons["Add Profile"]
        XCTAssertTrue(addProfile.waitForExistence(timeout: 8))
        addProfile.tap()

        XCTAssertTrue(app.navigationBars["Add Profile"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["Profile name"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["MagicDNS or private host"].waitForExistence(timeout: 2))
    }

    private func launchAppWithEmptyProfileStore() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launch()
        return app
    }
}
