import XCTest

/// Captures iPhone-simulator screenshots of the Direct-mode special-
/// keys page with each modifier in idle / armed / locked states for
/// the spec-driven vision-iteration loop (Phase 4 / US-2 / T028).
///
/// Constitution rule: visible state is the indicator, not just text.
/// The vision-judge step verifies the three states are clearly
/// visually distinct on iPhone 17 Pro / iOS 26.2.
///
/// Note 1: an ancestor in the SwiftUI tree clobbers the per-button
/// `accessibilityIdentifier` with `naru.app.detail` (same finding as
/// `DirectKeystrokeKeyboardScreenshotsUITests`), so we drive the
/// test through `accessibilityLabel` ("Control modifier, idle" etc).
///
/// Note 2: XCUITest's synthesised taps land ~600 ms apart, well
/// outside the production 400 ms double-tap lock window.  For the
/// `locked` screenshot, we use the `NARU_TEST_PRELOCK_MODIFIERS`
/// launch environment variable (read in
/// `NaruRemoteApplication.applyTestStickyModifierOverrides`) which
/// double-taps the requested modifiers via two back-to-back
/// `@MainActor` calls, landing < 400 ms apart by construction.
///
/// Output paths are hard-coded to the repo's artifacts dir; TODO to
/// parameterise once the broader screenshot loop is unified.
@MainActor
final class DirectKeystrokeStickyModifierScreenshotsUITests: XCTestCase {

    private let outputDirectory = "/Users/hckim/repo/naru-remote/artifacts/screenshots/direct-keystroke"

    func testCapturesIdleAndArmedModifierStatesOnIPhone() throws {
        let app = launchAppWithEmptyProfileStore()

        XCTAssertTrue(
            app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8),
            "Remote Input Dock heading must be visible after launch"
        )

        let directSegment = app.buttons["Direct"]
        XCTAssertTrue(directSegment.waitForExistence(timeout: 4))
        directSegment.tap()

        // Anchor on a QWERTY-only key so we know the keyboard is up.
        let qKey = app.buttons["Key q"]
        XCTAssertTrue(qKey.waitForExistence(timeout: 4))

        // Switch to special-keys page.
        let pageToggle = app.buttons["Switch keyboard page"]
        XCTAssertTrue(pageToggle.waitForExistence(timeout: 2))
        pageToggle.tap()

        // Anchor on F1 (special-page-only) to confirm we landed.
        XCTAssertTrue(
            app.buttons["Key f1"].waitForExistence(timeout: 4),
            "Special-keys page must render"
        )

        // Idle screenshot — no modifiers tapped.
        XCTAssertTrue(
            controlButtonInState(app: app, "idle").waitForExistence(timeout: 2),
            "Control modifier should be in idle state initially"
        )
        try saveFullScreenScreenshot(named: "us2-modifiers-idle.png", from: app)

        // Tap Control once → armed.
        let controlIdle = controlButtonInState(app: app, "idle")
        XCTAssertTrue(controlIdle.exists)
        controlIdle.tap()

        let controlArmed = controlButtonInState(app: app, "armed")
        XCTAssertTrue(
            controlArmed.waitForExistence(timeout: 2),
            "Control modifier should transition to armed after one tap"
        )
        try saveFullScreenScreenshot(named: "us2-modifiers-armed.png", from: app)
    }

    func testCapturesLockedModifierStateOnIPhone() throws {
        // Pre-lock Control via the test launch hook because
        // XCUITest taps land too far apart to reach the lock
        // window from real taps.
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = "studio.tailnet.ts.net"
        app.launchEnvironment["NARU_TEST_START_PROFILE_DETAIL"] = "1"
        app.launchEnvironment["NARU_TEST_PRELOCK_MODIFIERS"] = "control"
        // Phase 7: suppress the first-entry warning dialog so the
        // prelock hook drops us straight onto the keyboard.
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8),
            "Remote Input Dock heading must be visible after launch"
        )

        // Direct mode is auto-toggled on by the prelock hook;
        // anchor on a QWERTY key to confirm the keyboard is up.
        XCTAssertTrue(
            app.buttons["Key q"].waitForExistence(timeout: 4),
            "Direct keyboard must render after launch with prelock hook"
        )

        // Switch to the special-keys page where the modifier
        // buttons live.
        let pageToggle = app.buttons["Switch keyboard page"]
        XCTAssertTrue(pageToggle.waitForExistence(timeout: 2))
        pageToggle.tap()

        XCTAssertTrue(
            app.buttons["Key f1"].waitForExistence(timeout: 4),
            "Special-keys page must render"
        )

        // The prelock hook runs an async double-tap in the model
        // — wait for the locked-state button to appear before
        // taking the screenshot.
        XCTAssertTrue(
            controlButtonInState(app: app, "locked").waitForExistence(timeout: 4),
            "Control modifier should be locked via the test prelock hook"
        )

        try saveFullScreenScreenshot(named: "us2-modifiers-locked.png", from: app)
    }

    // MARK: - Helpers

    /// Locate the Control modifier button by its
    /// `accessibilityLabel` of the form "Control modifier, <state>".
    /// Using label rather than identifier because an ancestor in
    /// the SwiftUI tree clobbers the per-button identifier with
    /// `naru.app.detail` (`DirectKeystrokeKeyboardScreenshotsUITests`
    /// hit the same).
    private func controlButtonInState(app: XCUIApplication, _ state: String) -> XCUIElement {
        app.buttons["Control modifier, \(state)"]
    }

    private func launchAppWithEmptyProfileStore() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = "studio.tailnet.ts.net"
        app.launchEnvironment["NARU_TEST_START_PROFILE_DETAIL"] = "1"
        // Phase 7: suppress the first-entry warning dialog so the
        // sticky-modifier screenshots can land on the special-keys
        // page without the dialog covering the keyboard.
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        app.launch()
        return app
    }

    private func saveFullScreenScreenshot(named filename: String, from app: XCUIApplication) throws {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = filename
        add(attachment)

        let fm = FileManager.default
        try? fm.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )

        let url = URL(fileURLWithPath: outputDirectory)
            .appendingPathComponent(filename)
        try screenshot.pngRepresentation.write(to: url)

        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "Screenshot \(filename) must not be empty")
    }
}
