import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// Spec 039 FR-004: a hostname field opens on a Latin keyboard.
///
/// Spec 016 FR-010 already declared this closed — "a hostname is machine text
/// … or the field opening on a Korean IME page [is a] functional defect" — and
/// closed it with `.keyboardType(.URL)`. That picks a *layout*, not a
/// *language*: on a phone whose last-used keyboard is Korean, the URL keyboard
/// is the Korean keyboard with `.com` and `/` added. The 2026-08-25 audit
/// capture of the add-profile form shows exactly that, ㅂㅈㄷㄱ and `.com` in
/// one frame.
///
/// This is the gate the earlier fix did not have. It reads the keys, because
/// the keys are the thing that was wrong.
///
/// One field is gated, not both. Every hostname field in the editor — the VNC
/// host and the helper host — wears the same `hostnameInputTraits()` modifier,
/// so the trait is closed at one place rather than at each field; a second
/// walk down a `Form` past two toggles to reach the helper row tests
/// `swipeUp`, not the traits.
@MainActor
final class HostFieldKeyboardUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testTheHostFieldOpensOnALatinKeyboardEvenWhenTheDeviceTypesKorean() throws {
        try skipUnlessANonLatinKeyboardIsInstalled()

        let app = launch()
        let addProfile = app.buttons["naru.home.empty.addProfile"]
        XCTAssertTrue(addProfile.waitForExistence(timeout: 10))
        addProfile.tap()

        let hostField = app.textFields["MagicDNS or private host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        // The editor focuses the host field on appear; tapping is belt and
        // braces for the case where that changes.
        if !hostField.hasKeyboardFocus {
            hostField.tap()
        }

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "No keyboard came up, so there is nothing to judge"
        )

        // `q` is on the primary plane of every Latin layout Naru can get and
        // on none of the Korean ones.
        let latinKey = app.keys["q"]
        XCTAssertTrue(
            latinKey.waitForExistence(timeout: 5),
            """
            The host field came up on a non-Latin keyboard. A hostname is \
            machine text: every character of it is ASCII, and a page the user \
            has to switch away from before typing the first letter is a page \
            that should not have opened. Keys present: \
            \(Self.visibleKeyLabels(in: app))
            """
        )

        // A hostname is mostly dots — `studio.tailnet.ts.net` is four of them.
        // A plane the user has to leave for every separator is only half a fix.
        XCTAssertTrue(
            app.keys["."].exists,
            """
            The period is not on the plane that opened, so typing a MagicDNS \
            name means switching planes for every dot. Keys present: \
            \(Self.visibleKeyLabels(in: app, limit: 40))
            """
        )

        for hangulKey in ["ㅂ", "ㅈ", "ㄷ", "ㄱ"] {
            XCTAssertFalse(
                app.keys[hangulKey].exists,
                "\(hangulKey) is on screen, so the Korean plane is the one that opened"
            )
        }
    }

    // MARK: - Helpers

    /// A device with only Latin keyboards installed cannot produce the outcome
    /// under test — every assertion here would pass without the fix, which is
    /// worse than not running. Skip narrowly: the presence of a non-Latin
    /// keyboard is the precondition, not the platform.
    private func skipUnlessANonLatinKeyboardIsInstalled() throws {
        #if canImport(UIKit)
        let nonLatin = UITextInputMode.activeInputModes.contains { mode in
            guard let language = mode.primaryLanguage else { return false }
            return Self.nonLatinPrefixes.contains { language.hasPrefix($0) }
        }
        try XCTSkipUnless(
            nonLatin,
            """
            This device has no non-Latin keyboard installed, so a Latin \
            keyboard would appear whatever the field asked for. Add a Korean \
            (or Japanese / Chinese) keyboard in Settings to run this gate.
            """
        )
        #else
        throw XCTSkip("UIKit required")
        #endif
    }

    private static let nonLatinPrefixes = ["ko", "ja", "zh", "ru", "ar", "he", "th", "hi", "el"]

    private static func visibleKeyLabels(in app: XCUIApplication, limit: Int = 12) -> String {
        let labels = app.keyboards.keys.allElementsBoundByIndex
            .prefix(limit)
            .map(\.label)
        return labels.isEmpty ? "(none)" : labels.joined(separator: " ")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-host-keyboard-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
            .path
        app.launch()
        return app
    }
}

private extension XCUIElement {
    var hasKeyboardFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
