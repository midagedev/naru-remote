import XCTest

/// Sticky modifiers on the accessory strip: idle → armed → locked.
///
/// This replaces six `DirectKeystroke*UITests` suites that drove the Direct
/// mode custom keyboard. Spec 011 deleted that keyboard along with the mode
/// picker, entry warning and IME-off badge (`specs/011-simplified-input-ux/spec.md`
/// line 74), so those suites had been failing against a UI that no longer
/// exists since `6bc3b0d2` — red for a reason no one needed to act on, which is
/// worse than no test.
///
/// The behaviour they were protecting *did* survive: `StickyModifierState` and
/// the modifier buttons moved onto the shared accessory strip. So the coverage
/// moves with it, and it is stated as behaviour rather than as a screenshot —
/// the button's accessibility identifier carries the slot
/// (`naru.direct.modifier.<modifier>.<slot>`), so a state change is directly
/// assertable instead of being left to a vision judge.
@MainActor
final class StickyModifierStripUITests: XCTestCase {

    func testTappingAModifierArmsIt() {
        let app = launchWithLiveDock()

        let strip = app.descendants(matching: .any)["naru.input.accessory.strip"]
        XCTAssertTrue(
            strip.waitForExistence(timeout: 8),
            "The accessory strip carries the modifiers now that the Direct keyboard is gone"
        )

        let idle = modifier(app, "control", slot: "idle")
        XCTAssertTrue(idle.waitForExistence(timeout: 4), "Control starts idle")
        idle.tap()

        XCTAssertTrue(
            modifier(app, "control", slot: "armed").waitForExistence(timeout: 4),
            "One tap arms the modifier for the next key"
        )
        XCTAssertFalse(
            modifier(app, "control", slot: "idle").exists,
            "A modifier is in exactly one slot at a time"
        )
    }

    /// The lock is a double tap inside a 400 ms window, and XCUITest's
    /// synthesised taps land ~600 ms apart, so the launch hook does it. That
    /// hook (`NARU_TEST_PRELOCK_MODIFIERS`, read by
    /// `NaruRemoteApplication.applyTestStickyModifierOverrides`) predates the
    /// Direct keyboard's removal and still works.
    func testTheLockedStateIsReachableAndDistinct() {
        let app = launchWithLiveDock(prelockedModifiers: "control")

        XCTAssertTrue(
            app.descendants(matching: .any)["naru.input.accessory.strip"].waitForExistence(timeout: 8),
            "The accessory strip must render before the modifier state can be read"
        )
        XCTAssertTrue(
            modifier(app, "control", slot: "locked").waitForExistence(timeout: 6),
            "Locked is its own slot, not a variant of armed"
        )
        XCTAssertFalse(modifier(app, "control", slot: "armed").exists)
        XCTAssertFalse(modifier(app, "control", slot: "idle").exists)

        // Kept for the vision loop, as an attachment rather than a path on one
        // machine's disk — the suite this replaces wrote to a hard-coded
        // `/Users/...` directory that no longer exists.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = "sticky-modifier-locked.png"
        add(attachment)
    }

    func testEachModifierHasItsOwnStripButton() {
        let app = launchWithLiveDock()
        XCTAssertTrue(
            app.descendants(matching: .any)["naru.input.accessory.strip"].waitForExistence(timeout: 8)
        )

        for name in ["control", "alt", "meta", "shift"] {
            XCTAssertTrue(
                modifier(app, name, slot: "idle").waitForExistence(timeout: 4),
                "\(name) must have a strip button of its own — terminal work needs all four"
            )
        }
    }

    // MARK: - Helpers

    private func modifier(_ app: XCUIApplication, _ name: String, slot: String) -> XCUIElement {
        app.buttons["naru.direct.modifier.\(name).\(slot)"]
    }

    private func launchWithLiveDock(prelockedModifiers: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        // The strip's modifiers are `.disabled` unless the session is `.active`
        // (`RemoteInputDockView.swift` — `.disabled(!showsComposeQuickKeys)`,
        // fed by `snapshot.session?.state == .active`), and tapping a seeded
        // profile only *attempts* a connection to a host that is not there. So
        // take an active session from the same fixture the store captures use.
        // `store-session-korean-compose` is the one that mounts the strip: the
        // plain active fixture leaves the dock in its floating pill form, where
        // there is no strip to press.
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = "store-session-korean-compose"
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        if let prelockedModifiers {
            app.launchEnvironment["NARU_TEST_PRELOCK_MODIFIERS"] = prelockedModifiers
        }
        app.launch()
        return app
    }
}
