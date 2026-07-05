import XCTest

/// Captures iPhone-simulator screenshots of the spec 010 guided Naru
/// Helper onboarding sheet, one per step, so the flow can be reviewed
/// against the spec.  Mirrors the existing screenshot-UITest idiom
/// (seed a profile via `NARU_TEST_*`, drive the real UI, write PNGs to
/// `artifacts/screenshots/...`).
@MainActor
final class HelperOnboardingScreenshotsUITests: XCTestCase {

    private let outputDirectory =
        "/Users/hckim/repo/naru-remote/artifacts/screenshots/helper-onboarding"

    func testCapturesOnboardingStepsOnIPhone() throws {
        let app = launchSeeded()

        // Open the Add Profile editor (add mode defaults to a private
        // MagicDNS host, so the "Set up Naru Helper" entry shows).
        let addButton = firstHittable(
            in: app,
            identifiers: ["naru.profile.add", "naru.connection.grid.add"],
            labels: ["Add Profile"]
        )
        XCTAssertNotNil(addButton, "Add Profile affordance must exist")
        addButton?.tap()

        XCTAssertTrue(
            app.otherElements["naru.profile.editor"].waitForExistence(timeout: 8)
                || app.navigationBars["Add Profile"].waitForExistence(timeout: 4),
            "Profile editor must present"
        )

        let setup = app.buttons["naru.profile.editor.helper.setup"]
        if !setup.waitForExistence(timeout: 4) || !setup.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(setup.waitForExistence(timeout: 4), "Set up Naru Helper button must exist")
        setup.tap()

        XCTAssertTrue(
            app.otherElements["naru.helper.onboarding"].waitForExistence(timeout: 6),
            "Onboarding sheet must present"
        )

        // Step 1 — intro.
        try save("01-intro.png")

        let primary = app.buttons["naru.helper.onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 4))

        // Step 2 — configure (secret + fingerprint + snippet).
        primary.tap()
        XCTAssertTrue(
            app.buttons["naru.helper.onboarding.copySecret"].waitForExistence(timeout: 4),
            "Configure step must show the Copy secret action"
        )
        try save("02-configure.png")

        // Step 3 — permissions.
        primary.tap()
        _ = app.staticTexts["Grant two macOS permissions"].waitForExistence(timeout: 4)
        try save("03-permissions.png")

        // Step 4 — verify.
        primary.tap()
        _ = app.buttons["naru.helper.onboarding.test"].waitForExistence(timeout: 4)
        try save("04-verify.png")
    }

    // MARK: - Helpers

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = "studio.tailnet.ts.net"
        app.launch()
        return app
    }

    private func firstHittable(
        in app: XCUIApplication,
        identifiers: [String],
        labels: [String]
    ) -> XCUIElement? {
        for id in identifiers {
            let element = app.buttons[id]
            if element.waitForExistence(timeout: 3) { return element }
        }
        for label in labels {
            let element = app.buttons[label].firstMatch
            if element.waitForExistence(timeout: 2) { return element }
        }
        return nil
    }

    private func save(_ filename: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = filename
        add(attachment)

        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename)
        try screenshot.pngRepresentation.write(to: url)

        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "Screenshot \(filename) must not be empty")
    }
}
