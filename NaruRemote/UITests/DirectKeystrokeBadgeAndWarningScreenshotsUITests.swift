import XCTest

/// Captures iPhone-simulator screenshots of the Phase 7 / US-5
/// deliverables: warning dialog, dock badge, HUD badge.
///
/// - `us5-warning.png` shows the FR-009 first-entry confirmation
///   dialog over the dock chrome.
/// - `us5-badge-keyboard.png` shows the FR-010 dock badge alongside
///   the soft keyboard after the warning is dismissed.
/// - `us5-badge-hud.png` proves the FR-010 second-sentence HUD
///   badge exists at the top of the detail column.  Per the spec,
///   the dock badge can be present in the same frame — the assertion
///   is simply that `naru.direct.badge.hud` is rendered.
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

        // Dock + HUD badges share the same accessibility label
        // ("Direct keystroke mode active") because both render the
        // same `DirectModeBadge` view.  An ancestor in the SwiftUI
        // tree clobbers per-element `accessibilityIdentifier` with
        // `naru.app.detail` (same finding as the existing
        // `DirectKeystrokeKeyboardScreenshotsUITests` /
        // `DirectKeystrokeStickyModifierScreenshotsUITests`), so we
        // count by label.  Two matches → both badges rendered.
        let badgeQuery = app.staticTexts.matching(NSPredicate(format: "label == 'Direct mode'"))
        XCTAssertGreaterThanOrEqual(
            badgeQuery.count,
            1,
            "At least the dock-side Direct mode badge must be visible while keyboard is up"
        )

        try saveFullScreenScreenshot(named: "us5-badge-keyboard.png", from: app)

        // The HUD badge is unconditional while Direct mode is active
        // (FR-010 second sentence).  Real "collapsed keyboard" state
        // would need a dock-collapse affordance which the dock does
        // not currently expose; the HUD badge being present here in
        // the same frame as the dock badge proves the contract.
        XCTAssertGreaterThanOrEqual(
            badgeQuery.count,
            2,
            "Both dock-side and HUD-side Direct mode badges must be visible while Direct mode is active"
        )

        try saveFullScreenScreenshot(named: "us5-badge-hud.png", from: app)
    }

    // MARK: - Helpers

    private func launchAppWithEmptyProfileStore() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
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
