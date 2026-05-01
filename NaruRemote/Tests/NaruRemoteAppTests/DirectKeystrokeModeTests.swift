import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class DirectKeystrokeModeTests: XCTestCase {

    // MARK: - Initial state

    func testFreshModelIsInComposeMode() {
        let model = NaruRemoteAppModel()
        XCTAssertFalse(model.directKeystrokeMode.isActive)
        XCTAssertEqual(model.directKeystrokeMode.page, .qwerty)
        XCTAssertFalse(model.directKeystrokeMode.hasShownEntryWarningThisSession)
    }

    // MARK: - toggleDirectKeystrokeMode

    func testToggleFlipsIsActive() {
        let model = NaruRemoteAppModel()

        model.toggleDirectKeystrokeMode()
        XCTAssertTrue(model.directKeystrokeMode.isActive)

        model.toggleDirectKeystrokeMode()
        XCTAssertFalse(model.directKeystrokeMode.isActive)
    }

    func testToggleEntryResetsPageToQwerty() {
        // Toggle on, switch to special, toggle off, toggle on
        // again — fresh entry returns to QWERTY page.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()
        model.setDirectKeystrokePage(.special)
        XCTAssertEqual(model.directKeystrokeMode.page, .special)

        model.toggleDirectKeystrokeMode()
        model.toggleDirectKeystrokeMode()
        XCTAssertEqual(model.directKeystrokeMode.page, .qwerty)
    }

    func testToggleDoesNotTouchEntryWarningFlag() {
        // The flag is only flipped by
        // dismissDirectModeEntryWarning() — so the SwiftUI
        // dialog can render conditionally on
        // (isActive && !hasShownEntryWarningThisSession) and
        // every fresh-session entry shows the warning until the
        // user dismisses it.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()
        XCTAssertFalse(model.directKeystrokeMode.hasShownEntryWarningThisSession)

        model.toggleDirectKeystrokeMode()
        model.toggleDirectKeystrokeMode()
        XCTAssertFalse(model.directKeystrokeMode.hasShownEntryWarningThisSession)
    }

    // MARK: - setDirectKeystrokePage

    func testSetPageUpdatesPageOnly() {
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        model.setDirectKeystrokePage(.special)
        XCTAssertEqual(model.directKeystrokeMode.page, .special)
        XCTAssertTrue(model.directKeystrokeMode.isActive)

        model.setDirectKeystrokePage(.qwerty)
        XCTAssertEqual(model.directKeystrokeMode.page, .qwerty)
        XCTAssertTrue(model.directKeystrokeMode.isActive)
    }

    // MARK: - dismissDirectModeEntryWarning

    func testDismissEntryWarningSetsFlag() {
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()
        XCTAssertFalse(model.directKeystrokeMode.hasShownEntryWarningThisSession)

        model.dismissDirectModeEntryWarning()
        XCTAssertTrue(model.directKeystrokeMode.hasShownEntryWarningThisSession)

        // Subsequent toggle off / on within the same session
        // keeps the flag set.
        model.toggleDirectKeystrokeMode()
        model.toggleDirectKeystrokeMode()
        XCTAssertTrue(model.directKeystrokeMode.hasShownEntryWarningThisSession)
    }

    // MARK: - tapDirectKey

    func testTapDirectKeyPageToggleSwapsPagesWithoutEmitting() async {
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()
        XCTAssertEqual(model.directKeystrokeMode.page, .qwerty)

        await model.tapDirectKey(.pageToggle)
        XCTAssertEqual(model.directKeystrokeMode.page, .special)

        await model.tapDirectKey(.pageToggle)
        XCTAssertEqual(model.directKeystrokeMode.page, .qwerty)
    }

    func testTapDirectKeyDropsCharacterEmissionWhenNotActive() async {
        // Direct mode off → emission silently dropped (FR-014
        // default; spec.md IN-003 fallback "drop silently when
        // not `.active`").  Without an active session there is
        // also no keystrokeEmitter, so the test asserts no
        // crash and consistent state.
        let model = NaruRemoteAppModel()
        // Direct mode is off by default — emission should drop.
        await model.tapDirectKey(.character("c"))

        // Toggling on with no session attached also drops since
        // keystrokeEmitter is still nil.
        model.toggleDirectKeystrokeMode()
        await model.tapDirectKey(.character("c"))

        XCTAssertTrue(model.directKeystrokeMode.isActive)
    }

    func testTapDirectKeyDropsNonAsciiCharacters() async {
        // Korean / CJK / emoji belong to Compose & Send
        // (constitution §I); the QWERTY page does not render
        // these keys but if a Character somehow arrives, drop
        // it rather than emit garbage.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.character("한"))
        await model.tapDirectKey(.character("😊"))

        // No assertion on wire (no active session); the test's
        // value is that no crash / typed exception leaks out.
        XCTAssertTrue(model.directKeystrokeMode.isActive)
    }
}
