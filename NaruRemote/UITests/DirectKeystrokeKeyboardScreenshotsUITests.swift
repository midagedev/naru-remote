import XCTest

/// Captures iPhone-simulator screenshots of the new Direct Keystroke
/// Mode soft keyboard for the spec-driven vision-iteration loop.
///
/// The XCUITest runner process is a regular macOS process — it can
/// freely write PNG files to the host filesystem.  We therefore write
/// the screenshots from this process directly, instead of forwarding
/// a path through `app.launchEnvironment` and serialising back out of
/// the device-side app sandbox.
///
/// TODO: parameterise the output directory once T020 settles — for
/// now the path is the repo-relative-but-absolute artifacts dir so
/// that the spec-driven UI iteration loop can reliably find the PNGs
/// without per-machine tweaks.
@MainActor
final class DirectKeystrokeKeyboardScreenshotsUITests: XCTestCase {

    private let outputDirectory = "/Users/hckim/repo/naru-remote/artifacts/screenshots/direct-keystroke"

    func testCapturesQwertyAndSpecialPagesOnIPhone() throws {
        let app = launchAppWithEmptyProfileStore()

        XCTAssertTrue(
            app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8),
            "Remote Input Dock heading must be visible after launch"
        )

        let modePicker = app.otherElements["naru.input.mode-picker"]
        if !modePicker.waitForExistence(timeout: 4) {
            // SwiftUI sometimes exposes Picker via its container element
            // rather than `otherElements`; either way the Direct segment
            // is reachable as a button labeled "Direct".
            XCTAssertTrue(
                app.buttons["Direct"].waitForExistence(timeout: 4),
                "Direct segment must exist in the input mode picker"
            )
        }

        let directSegment = app.buttons["Direct"]
        XCTAssertTrue(directSegment.waitForExistence(timeout: 4))
        directSegment.tap()

        // Anchor on a known QWERTY-only key.  The container element
        // identifier `naru.direct.keyboard.qwerty` is set on a SwiftUI
        // VStack and isn't always reliably exposed in the accessibility
        // tree, but the `q` key always is.
        let qKey = app.buttons["Key q"]
        XCTAssertTrue(
            qKey.waitForExistence(timeout: 4),
            "QWERTY page must render after switching to Direct mode"
        )

        try saveFullScreenScreenshot(named: "us1-qwerty.png", from: app)

        // Some ancestor (NavigationSplitView detail column) clobbers
        // each button's accessibilityIdentifier with "naru.app.detail"
        // — match the page-toggle by its accessibilityLabel instead.
        let pageToggle = app.buttons["Switch keyboard page"]
        XCTAssertTrue(
            pageToggle.waitForExistence(timeout: 2),
            "Page-toggle key must exist on the QWERTY page"
        )
        pageToggle.tap()

        // The QWERTY-page keyboard container element keeps its
        // `naru.direct.keyboard.qwerty` identifier even after a label
        // change in some SwiftUI snapshots, so anchor on a key that
        // only exists on the special page (F1) instead.
        let f1Key = app.buttons["Key f1"]
        XCTAssertTrue(
            f1Key.waitForExistence(timeout: 4),
            "Special-keys page must render after tapping page-toggle"
        )

        try saveFullScreenScreenshot(named: "us1-special.png", from: app)
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
        // Phase 7 added a one-time-per-session warning dialog on
        // Direct-mode entry.  Suppress it here so the existing
        // QWERTY / special-page screenshots stay clean.
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        app.launch()
        return app
    }

    /// Capture the full simulator screen (so the dock is included) and
    /// write the PNG to `outputDirectory`.  Also attaches a copy to the
    /// XCResult bundle so failures still leave evidence.
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

        // Sanity assertion — write must produce a non-empty file.
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "Screenshot \(filename) must not be empty")
    }
}
