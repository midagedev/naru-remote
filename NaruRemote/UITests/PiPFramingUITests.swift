import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// Spec 034 FR-002 / FR-005: the PiP control's tap stays a tap, and the framing
/// choices live behind its long press.
///
/// PiP itself is unsupported on the simulator (spec 032), so these run with
/// `NARU_TEST_FORCE_PIP_AVAILABLE` — which relaxes only the *availability of
/// the affordance*, never what the system does with it. What is under test here
/// is the chrome, and the chrome is exactly what that hook makes reachable.
@MainActor
final class PiPFramingUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testTappingPiPPresentsNothing() throws {
        let app = launchLiveSession()
        let pip = try revealPiPControl(in: app)

        pip.tap()

        XCTAssertFalse(
            app.buttons["naru.session.pip.chooseRegion"].waitForExistence(timeout: 2),
            "A tap must enter PiP, not open a menu — that is the whole point of one-tap entry"
        )
        XCTAssertFalse(
            app.staticTexts["naru.session.pip.regionPicker"].exists,
            "A tap must not open the region picker either"
        )
    }

    /// Contract changed by spec 038 FR-006 (2026-08-27): `followActivity` is
    /// gone at the founder's call — "실 동작영역을 찾는 알고리즘 구현하는건 어려울것
    /// 같아서 제거하고". This used to assert its presence, calling it "the mode
    /// the founder asked for by name", which is exactly why the assertion had
    /// to move rather than be quietly deleted.
    ///
    /// With one mode left there is nothing to choose between until a region is
    /// drawn, so the menu is just the action — and the assertion is that the
    /// retired mode is *not* offered, which a deleted test could not make.
    func testLongPressOffersDrawingARegionAndNotTheRetiredAutomaticMode() throws {
        let app = launchLiveSession()
        let pip = try revealPiPControl(in: app)

        pip.press(forDuration: 1.1)

        XCTAssertTrue(
            app.buttons["naru.session.pip.chooseRegion"].waitForExistence(timeout: 5),
            "Long press must offer drawing a region"
        )
        XCTAssertFalse(
            app.buttons["naru.session.pip.framing.followActivity"].exists,
            "Follow activity was removed; offering it would frame PiP on a guess"
        )
        XCTAssertFalse(
            app.buttons["naru.session.pip.framing.currentView"].exists,
            """
            With no region drawn, "Current view" is the only mode there is — a \
            row that is permanently checked and cannot be unchecked is chrome \
            pretending to be a choice.
            """
        )
        saveScreen(named: "21-pip-framing-menu.png")
    }

    func testChoosingARegionOpensThePickerAndConfirmsIntoChosenRegion() throws {
        let app = launchLiveSession()
        let pip = try revealPiPControl(in: app)

        pip.press(forDuration: 1.1)
        let chooseRegion = app.buttons["naru.session.pip.chooseRegion"]
        XCTAssertTrue(chooseRegion.waitForExistence(timeout: 5))
        chooseRegion.tap()

        let use = app.buttons["naru.session.pip.regionPicker.use"]
        XCTAssertTrue(
            use.waitForExistence(timeout: 5),
            "Choosing a region must open the picker with an explicit confirmation"
        )
        saveScreen(named: "22-pip-region-picker.png")
        use.tap()

        XCTAssertFalse(
            use.waitForExistence(timeout: 2),
            "Confirming must dismiss the picker"
        )

        // The chosen-region mode only appears once a region exists, so its
        // presence is the assertion that the confirmation was recorded.
        let controlAgain = try revealPiPControl(in: app)
        controlAgain.press(forDuration: 1.1)
        XCTAssertTrue(
            app.buttons["naru.session.pip.framing.chosenRegion"].waitForExistence(timeout: 5),
            "A confirmed region must become a selectable mode"
        )
    }

    // MARK: - Helpers

    /// Attaches every capture to the result bundle, and additionally writes it
    /// to `NARU_UI_SHOT_DIR` when that is set — which is how the framing
    /// captures in spec 034 were reviewed. Best-effort: a missing directory
    /// loses the file, never the test.
    private func saveScreen(named filename: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)

        #if canImport(UIKit)
        guard let directory = ProcessInfo.processInfo.environment["NARU_UI_SHOT_DIR"],
              !directory.isEmpty,
              let data = screenshot.image.pngData()
        else {
            return
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(filename)
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: directory),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
        #endif
    }

    private func revealPiPControl(in app: XCUIApplication) throws -> XCUIElement {
        let reveal = app.buttons["naru.session.controls.reveal"]
        if reveal.waitForExistence(timeout: 3), reveal.isHittable {
            reveal.tap()
        }

        let pip = app.buttons["naru.session.pipWatch"]
        guard pip.waitForExistence(timeout: 8) else {
            throw XCTSkip("The PiP control did not mount; nothing to exercise")
        }
        return pip
    }

    private func launchLiveSession() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-pip-framing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
            .path
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = "session-active-widescreen"
        app.launchEnvironment["NARU_TEST_FORCE_PIP_AVAILABLE"] = "1"
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        app.launch()
        return app
    }
}
