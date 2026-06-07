import XCTest

@MainActor
final class ComposeInputResponsivenessUITests: XCTestCase {
    func testComposeEditorAcceptsSecondKoreanSyllableAfterFirstInput() {
        let app = launchAppWithSampleProfile()
        let editor = composeEditor(in: app)
        if !editor.waitForExistence(timeout: 3) {
            openFirstConnectionCardIfPresent(app: app)
        }

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
    }

    func testActiveSessionCompactComposeEditorAcceptsSecondKoreanSyllableAfterFirstInput() {
        let app = launchAppWithActiveSessionFixture()
        let editor = composeEditor(in: app)

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
    }

    func testFocusedActiveSessionComposeSurvivesConfirmationStatusClearAfterFirstInput() {
        let app = launchAppWithActiveSessionConfirmationUnavailableFixture()
        let editor = composeEditor(in: app)
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 3),
            "Clearing the stale send result after the first syllable must not collapse the system keyboard."
        )

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
    }

    func testFocusedActiveSessionComposeAcceptsKoreanDuringTrackpadCursorStorm() {
        let app = launchAppWithActiveSessionConfirmationUnavailableFixture(
            trackpadCursorStorm: true
        )
        let editor = composeEditor(in: app)
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 2),
            "Viewport cursor mirror pressure must not collapse or freeze focused Compose input."
        )
    }

    private func composeEditor(in app: XCUIApplication) -> XCUIElement {
        let identified = app.descendants(matching: .any)["naru.input.editor"].firstMatch
        if identified.exists {
            return identified
        }
        return app.textViews["Remote input text"]
    }

    private func waitForEditor(
        _ editor: XCUIElement,
        toContain expectedText: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "value CONTAINS %@", expectedText)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: editor)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        let value = editor.value as? String ?? ""
        XCTAssertEqual(result, .completed, file: file, line: line)
        XCTAssertTrue(
            value.contains(expectedText),
            "Expected compose editor value to contain \(expectedText), got \(value)",
            file: file,
            line: line
        )
    }

    private func launchAppWithSampleProfile() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-compose-input-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_START_PROFILE_DETAIL"] = "1"
        try? writeSeedProfiles(
            [SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")],
            to: storeURL
        )
        app.launch()
        return app
    }

    private func launchAppWithActiveSessionFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = "session-active-widescreen"
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        app.launch()
        return app
    }

    private func launchAppWithActiveSessionConfirmationUnavailableFixture(
        trackpadCursorStorm: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = "session-active-compose-confirmation-unavailable"
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        if trackpadCursorStorm {
            app.launchEnvironment["NARU_TEST_TRACKPAD_CURSOR_STORM"] = "1"
        }
        app.launch()
        return app
    }

    private func openFirstConnectionCardIfPresent(app: XCUIApplication) {
        let gridHeading = app.staticTexts["Connections"]
        guard gridHeading.waitForExistence(timeout: 3) else {
            return
        }

        let firstCard = app.buttons["naru.connection.grid.card"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 4))
        firstCard.tap()
    }

    private struct SeedProfile {
        let id = UUID()
        let displayName: String
        let host: String
        let port = 5900
        let hostKind = "magicDNS"
    }

    private func writeSeedProfiles(_ profiles: [SeedProfile], to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = profiles.map { profile in
            [
                "id": profile.id.uuidString,
                "displayName": profile.displayName,
                "host": profile.host,
                "port": profile.port,
                "hostKind": profile.hostKind,
                "allowsPiPWatch": true
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: fileURL, options: .atomic)
    }
}
