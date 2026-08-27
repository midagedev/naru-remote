import XCTest

/// Spec 039 FR-002: there is a way to reach the person who wrote this.
///
/// The app shipped to TestFlight with no About surface of any kind — no
/// version, no repository, no author, no acknowledgement of the one package it
/// depends on, and no statement of what leaves the device. This gate asserts
/// the surface exists and is reachable from *both* home states, because the
/// grid header is the obvious place to put it and the grid does not exist
/// until a profile does — a user stuck on their first connection would have
/// been the one person unable to find it.
@MainActor
final class AboutAndFeedbackUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testAboutIsReachableOnFirstLaunchBeforeAnyProfileExists() throws {
        let app = launch(seedsProfile: false)

        let about = app.buttons["naru.home.empty.about"]
        XCTAssertTrue(
            about.waitForExistence(timeout: 10),
            "The first-launch screen has no way to reach About, which is the screen a stuck user is on"
        )
        about.tap()

        XCTAssertTrue(app.otherElements["naru.about"].waitForExistence(timeout: 5))
    }

    func testAboutIsReachableFromTheConnectionsHeader() throws {
        let app = launch(seedsProfile: true)

        let about = app.buttons["naru.connection.grid.about"]
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        about.tap()

        XCTAssertTrue(app.otherElements["naru.about"].waitForExistence(timeout: 5))
    }

    func testAboutCarriesTheVersionTheAuthorAndAWayToReportAProblem() throws {
        let app = launch(seedsProfile: false)

        let about = app.buttons["naru.home.empty.about"]
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        about.tap()
        XCTAssertTrue(app.otherElements["naru.about"].waitForExistence(timeout: 5))

        // A version string is what turns "it broke" into a reproducible
        // report, and it is the first thing an issue template asks for.
        let version = app.staticTexts["naru.about.version"]
        XCTAssertTrue(version.waitForExistence(timeout: 3))
        XCTAssertTrue(
            version.label.hasPrefix("Version "),
            "Version row read \"\(version.label)\""
        )
        XCTAssertFalse(
            version.label.contains("—"),
            "The bundle version keys were not readable, so the row rendered its fallback"
        )

        for identifier in [
            "naru.about.reportIssue",
            "naru.about.requestFeature",
            "naru.about.source",
            "naru.about.author"
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].exists,
                "About is missing \(identifier)"
            )
        }

        saveScreen(named: "23-about-iphone.png")

        // The acknowledgement is below the fold, and a `List` does not build a
        // row it has never shown — so reaching it is part of the assertion.
        let acknowledgement = app.descendants(matching: .any)["naru.about.glasskeys"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<6 where !acknowledgement.exists {
            list.swipeUp()
        }
        XCTAssertTrue(
            acknowledgement.exists,
            "About does not acknowledge glasskeys, the one package this app depends on"
        )

        app.buttons["naru.about.done"].tap()
        XCTAssertFalse(
            app.otherElements["naru.about"].waitForExistence(timeout: 2),
            "Done must dismiss About"
        )
    }

    // MARK: - Helpers

    private func saveScreen(named filename: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(seedsProfile: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-about-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
            .path
        if seedsProfile {
            // One saved profile is all the grid needs to exist. The seed hook
            // takes a host rather than a fixture token because it builds a
            // real `ConnectionProfile`; the address is a documentation-range
            // one and nothing connects to it here.
            app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = "studio.example"
            app.launchEnvironment["NARU_TEST_SEED_PROFILE_NAME"] = "Studio Mac"
            app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        }
        app.launch()
        return app
    }
}
