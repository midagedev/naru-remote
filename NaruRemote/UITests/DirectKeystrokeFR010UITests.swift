import XCTest

/// FR-010 verification (T044 in `specs/002-direct-keystroke-mode/tasks.md`).
///
/// Asserts the persistent "Direct — IME off" badge contract: while
/// Direct keystroke streaming is active, the user must always have a
/// visible cue alongside the dock soft keyboard.
///
/// History: PR-G originally shipped two `DirectModeBadge` instances —
/// a dock badge and a session HUD badge — with the intent that the
/// HUD copy survives keyboard collapse.  In practice the dock is
/// always pinned via `.safeAreaInset(edge: .bottom)`, so the dock
/// badge is always on screen while Direct mode is active and the HUD
/// instance only collided visually with it (UX punch-list #107).
/// Chunk 7 removed the HUD instance; the dock badge alone now carries
/// the FR-010 contract.  The badge copy was also tightened to
/// "Direct — IME off" (Coral fill) so a returning user immediately
/// sees that IME is disabled (UX punch-list #008).
///
/// The badge identifier is `naru.direct.badge.dock` and the
/// accessibility label is "Direct keystroke mode active, IME
/// disabled".  Count by label matches so this behavioral gate is
/// independent from SwiftUI container identifier reshuffling.  One
/// label match → badge rendered; zero → not rendered.
///
/// Pure assertion test — no screenshots; the screenshot-evidence
/// test already lives in `DirectKeystrokeBadgeAndWarningScreenshotsUITests`
/// and is frozen as artifact.
@MainActor
final class DirectKeystrokeFR010UITests: XCTestCase {

    func testDockBadgeAppearsOnDirectAndDisappearsOnCompose() {
        let app = launchAppWithEmptyProfileStore()

        XCTAssertTrue(
            app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8),
            "Remote Input Dock heading must be visible after launch"
        )

        // Toggle into Direct mode.
        let directSegment = app.buttons["Direct"]
        XCTAssertTrue(directSegment.waitForExistence(timeout: 4))
        directSegment.tap()

        // Anchor on the QWERTY keyboard so we know the dock has
        // reached its Direct-mode layout before sampling the badge.
        XCTAssertTrue(
            app.buttons["Key q"].waitForExistence(timeout: 4),
            "Direct keyboard must render after toggle so the badge has time to mount"
        )

        // Primary assertion: the badge renders the accessibility
        // label "Direct keystroke mode active, IME disabled".
        // SwiftUI's `accessibilityElement(children: .ignore)` makes
        // the badge surface as a single element, but in an
        // `otherElements`/`staticTexts` query the inner Text
        // ("Direct — IME off") leaks through.  Match via label
        // predicate against the catch-all `descendants(matching:
        // .any)` query so we pick up whichever element the SwiftUI
        // snapshot exposes.
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
            "Dock Direct-mode badge must be visible while Direct mode is active (FR-010)"
        )

        // Toggle back to Compose; the badge must disappear.
        let composeSegment = app.buttons["Compose"]
        XCTAssertTrue(composeSegment.waitForExistence(timeout: 2))
        composeSegment.tap()

        // The custom keyboard going away is a positive signal that
        // the toggle settled before we sample the badge.
        XCTAssertTrue(
            app.buttons["Key q"].waitForNonExistence(timeout: 3),
            "Custom keyboard must dismiss after toggling to Compose"
        )

        XCTAssertTrue(
            waitForBadgeCount(
                in: app,
                matching: badgeLabel,
                fallback: directModeStaticText,
                expected: 0,
                timeout: 3
            ),
            "Dock Direct-mode badge must disappear after toggling to Compose (FR-010 inverse)"
        )
    }

    // MARK: - Helpers

    /// Polls the app's accessibility tree until the badge count
    /// reaches `expected` or the timeout elapses.  Tries the badge's
    /// canonical accessibility label first (the
    /// `accessibilityLabel("Direct keystroke mode active, IME
    /// disabled")` set by `DirectModeBadge`); falls back to the
    /// inner `Text("Direct — IME off")` because SwiftUI sometimes
    /// exposes both forms.  Either path counts a single badge as
    /// one match — the test asserts the total across both query
    /// paths reaches the expected count.
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
            // SwiftUI sometimes exposes the inner Text rather than
            // the wrapped accessibility element.  Count those too,
            // capped by `expected` so we never double-count when
            // both forms appear for the same badge.
            let fallbackCount = app.staticTexts.matching(fallback).count
            if min(primaryCount + fallbackCount, expected * 2) == expected
                || fallbackCount == expected
            {
                return true
            }
            // Fast poll — no `sleep`; XCTNSPredicateExpectation
            // would also work but the dual-query shape doesn't fit
            // a single predicate cleanly.
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

    private func launchAppWithEmptyProfileStore() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = "studio.tailnet.ts.net"
        app.launchEnvironment["NARU_TEST_START_PROFILE_DETAIL"] = "1"
        // FR-010 verification only — suppress the FR-009 first-entry
        // warning so the dialog doesn't cover the badges and confuse
        // the count-based assertions.  FR-009 has its own dedicated
        // file (`DirectKeystrokeFR009UITests`).
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        app.launch()
        return app
    }
}

private extension XCUIElement {
    /// Mirror of `waitForExistence` with the inverse predicate so the
    /// test can wait for an element to leave the tree without
    /// resorting to `sleep(...)` (forbidden by the agent's guidance).
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
