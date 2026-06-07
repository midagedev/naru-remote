import XCTest

/// Captures iPhone-simulator screenshots of the Phase 7 / US-5
/// deliverables: warning dialog and the dock badge.
///
/// - `us5-warning.png` shows the FR-009 first-entry confirmation
///   dialog over the dock chrome.
/// - `us5-badge-keyboard.png` shows the FR-010 dock badge alongside
///   the soft keyboard after the warning is dismissed.
///
/// History: PR-G originally captured a third "us5-badge-hud.png"
/// for an HUD-mounted instance of the same badge.  UX punch-list
/// #107 retired the HUD instance because the dock is always pinned
/// via `.safeAreaInset(edge: .bottom)` and the two badges visually
/// collided whenever the keyboard was up.  The dock badge now
/// carries the FR-010 contract on its own.
///
/// TODO (matching the existing screenshot tests): parameterise the
/// output directory once the broader screenshot loop is unified.
@MainActor
final class DirectKeystrokeBadgeAndWarningScreenshotsUITests: XCTestCase {

    private let outputDirectory = "/Users/hckim/repo/naru-remote/artifacts/screenshots/direct-keystroke"

    func testCapturesWarningDialogAndBadgesOnIPhone() throws {
        let app = launchAppWithEmptyProfileStore()

        XCTAssertTrue(
            app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8),
            "Remote Input Dock heading must be visible after launch"
        )

        let directSegment = app.buttons["Direct"]
        XCTAssertTrue(directSegment.waitForExistence(timeout: 4))
        directSegment.tap()

        // Warning dialog should appear on first entry.  The dialog
        // uses a `confirmationDialog` whose action button is "Got it";
        // anchor on the action button so we know the dialog is up.
        // SwiftUI exposes the button twice in the a11y tree (parent
        // and inner element), so use firstMatch to disambiguate.
        let confirm = app.buttons["Got it"].firstMatch
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 4),
            "Direct-mode entry warning must show on first activation"
        )

        try saveFullScreenScreenshot(named: "us5-warning.png", from: app)

        // Dismiss the dialog and capture the dock badge + custom
        // keyboard.
        confirm.tap()

        let qKey = app.buttons["Key q"]
        XCTAssertTrue(
            qKey.waitForExistence(timeout: 4),
            "QWERTY page must render after dismissing warning"
        )

        // Punch-list #107 retired the HUD badge — only the dock
        // badge remains.  Count by label so the screenshot gate
        // follows the user-facing contract instead of SwiftUI
        // container identifier details.  At least one match → dock
        // badge rendered.  SwiftUI can expose either the wrapped
        // accessibility label or the inner visible Text, so mirror
        // the FR-010 assertion test's dual-query helper.
        let badgeLabel = NSPredicate(
            format: "label == %@",
            "Direct keystroke mode active, IME disabled"
        )
        let directModeStaticText = NSPredicate(
            format: "label == %@",
            "Direct — IME off"
        )
        XCTAssertTrue(
            waitForBadgeCount(
                in: app,
                matching: badgeLabel,
                fallback: directModeStaticText,
                expected: 1,
                timeout: 4
            ),
            "Dock-side Direct-mode badge must be visible while keyboard is up"
        )

        try saveFullScreenScreenshot(named: "us5-badge-keyboard.png", from: app)
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

    private func waitForBadgeCount(
        in app: XCUIApplication,
        matching primary: NSPredicate,
        fallback: NSPredicate,
        expected: Int,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let primaryCount = app.descendants(matching: .any).matching(primary).count
            if primaryCount == expected {
                return true
            }
            let fallbackCount = app.staticTexts.matching(fallback).count
            if min(primaryCount + fallbackCount, expected * 2) == expected
                || fallbackCount == expected
            {
                return true
            }
            _ = XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(value: false),
                    object: nil
                )],
                timeout: 0.25
            )
        }
        return false
    }
}
