import XCTest

/// Simulator UI storm test for Live type-through mode (spec 009, task T018).
///
/// Follows the `ComposeInputResponsivenessUITests` pattern: it enters Live mode
/// on an active-session fixture, focuses the editor, and types a rapid
/// multilingual storm. The assertion is local-echo integrity — every committed
/// unit lands in order with no loss, duplication, or reorder while the
/// type-through dispatch runs (FR-008). Per-tier delivery routing is covered by
/// the app-model `LiveTypeThroughRoutingTests`; the pure window/coalesce logic
/// by `LiveEditingWindowTests`.
@MainActor
final class LiveTypeThroughStormUITests: XCTestCase {

    func testLiveModeAcceptsRapidKoreanStormWithoutLoss() {
        let app = launchAppWithSeededProfile()

        enterLiveMode(in: app)

        let editor = focusedLiveEditor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 8), "Live editor must be present after entering Live mode")

        // On the standard (pre-session) layout the editor is visible and the
        // tap focuses it. In a live session's compact dock (spec 015 v1.1)
        // the editor is a 1×1 hidden first responder — not hittable, already
        // focused by the reveal — so the tap is conditional.
        if editor.isHittable {
            editor.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))

        // A rapid multilingual storm: Hangul syllables interleaved with ASCII.
        // Each syllable is a committed unit; the local mirror must accumulate
        // them in order with no dropped or duplicated graphemes.
        let syllables = ["안", "녕", "하", "세", "요", " ", "n", "a", "r", "u"]
        var expected = ""
        for syllable in syllables {
            app.typeText(syllable)
            expected += syllable
        }

        waitForEditor(editor, toContain: "안녕하세요 naru")

        saveScreenshot(named: "live-mode-dock.png")
    }

    func testLiveModeSurfacesTransportDisclosureBadge() {
        let app = launchAppWithSeededProfile()

        enterLiveMode(in: app)

        // The persistent transport disclosure badge is the standing notice for
        // Live mode (FR-014), peer to Direct's "IME off" badge.
        let disclosure = app.descendants(matching: .any)["naru.input.live-disclosure"].firstMatch
        XCTAssertTrue(
            disclosure.waitForExistence(timeout: 6),
            "Live mode must surface a persistent transport disclosure badge"
        )
    }

    // MARK: - Helpers

    private func enterLiveMode(in app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8),
            "Remote Input Dock heading must be visible after launch"
        )
        // Spec 011 two-mode dock: the standard detail dock renders the
        // Type|Compose segmented picker; entering Type taps the "Type"
        // segment.
        let typeSegment = app.buttons["Type"].firstMatch
        XCTAssertTrue(typeSegment.waitForExistence(timeout: 6), "Type mode segment must exist")
        typeSegment.tap()
    }

    private func focusedLiveEditor(in app: XCUIApplication) -> XCUIElement {
        // Reveal the compact editor if the idle accessory is showing
        // (spec 011: the reveal control enters/keeps Type mode).
        let reveal = app.buttons["naru.input.type-reveal"].firstMatch
        if reveal.waitForExistence(timeout: 2) {
            reveal.tap()
        }
        return composeEditor(in: app)
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
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "value CONTAINS %@", expectedText)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: editor)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        let value = editor.value as? String ?? ""
        XCTAssertEqual(
            result,
            .completed,
            "Expected Live editor value to contain \(expectedText), got \(value)",
            file: file,
            line: line
        )
    }

    private let screenshotOutputDirectory =
        "/Users/hckim/repo/naru-remote/artifacts/screenshots/live-type-through"

    private func saveScreenshot(named filename: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = filename
        add(attachment)

        let fm = FileManager.default
        try? fm.createDirectory(atPath: screenshotOutputDirectory, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: screenshotOutputDirectory).appendingPathComponent(filename)
        try? screenshot.pngRepresentation.write(to: url)
    }

    private func launchAppWithSeededProfile() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-live-storm-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = "studio.tailnet.ts.net"
        app.launchEnvironment["NARU_TEST_START_PROFILE_DETAIL"] = "1"
        app.launch()
        return app
    }
}
