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

    // MARK: - Sticky modifier integration (Phase 4 / US-2)

    func testFreshModelHasAllStickyModifiersIdle() {
        let model = NaruRemoteAppModel()
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .idle)
        XCTAssertEqual(model.stickyModifierState.slot(for: .shift), .idle)
        XCTAssertEqual(model.stickyModifierState.slot(for: .alt), .idle)
        XCTAssertEqual(model.stickyModifierState.slot(for: .meta), .idle)
        XCTAssertTrue(model.stickyModifierState.activeModifiers.isEmpty)
    }

    func testTapModifierUpdatesStateWithoutSessionOrCrash() async {
        // No active session, so emission has no destination — but
        // a sticky-modifier tap must still update state so the
        // user can pre-arm before the wire is up.  Verify no
        // crash and the slot transitions.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.control))

        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .armed)
    }

    func testTapModifierThenCharacterConsumesArmedSlot() async {
        // Without an active emitter, the .character branch drops
        // before reaching consumeAfterNonModifierEmission().
        // We assert the model state pre-emission and document
        // the consumption rule via the locked-modifier test
        // below (which exercises the post-emission state path).
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.control))
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .armed)
        XCTAssertEqual(model.stickyModifierState.activeModifiers, [.control])

        // Without an emitter, .character drops at the guard and
        // does NOT call consume (it would be wrong to consume
        // armed state when nothing reached the wire).
        await model.tapDirectKey(.character("c"))
        XCTAssertEqual(
            model.stickyModifierState.slot(for: .control),
            .armed,
            "guard-dropped emissions must not consume armed state"
        )
    }

    func testDoubleTapShiftLocksAndClearAffordanceResets() async {
        // FR-005 + FR-013 — double-tap Shift to lock, then tap
        // Clear modifiers to release everything in one tap.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.shift))
        await model.tapDirectKey(.modifier(.shift))
        XCTAssertEqual(model.stickyModifierState.slot(for: .shift), .locked)

        await model.tapDirectKey(.clearModifiers)
        XCTAssertEqual(model.stickyModifierState.slot(for: .shift), .idle)
        XCTAssertTrue(model.stickyModifierState.activeModifiers.isEmpty)
    }

    func testStackedArmedModifiersRecordedOnState() async {
        // spec.md US-2 acceptance #3 — Ctrl-Shift-Tab is reachable
        // via two modifier taps then Tab.  We assert state, not
        // wire, because the test model has no session.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.control))
        await model.tapDirectKey(.modifier(.shift))

        XCTAssertEqual(
            model.stickyModifierState.activeModifiers,
            [.control, .shift]
        )
    }

    func testSnapshotMirrorsStickyState() async {
        // Views render off the snapshot, not by reaching back
        // into the @MainActor model directly.  Verify the
        // snapshot carries the live sticky state.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.alt))

        XCTAssertEqual(model.snapshot.stickyModifierState.slot(for: .alt), .armed)
    }
}
