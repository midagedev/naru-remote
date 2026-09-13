import XCTest
@testable import NaruRemoteApp

/// Spec 043 FR-005: "Entering Direct Keystroke mode from Compose mode always
/// results in the mode's selected input surface being present … Leaving and
/// re-entering is not required to recover."
///
/// Founder, 2026-09-13, physical iPhone: "컴포즈모드와 직접키보드 모드
/// 오갈때 직접입력모드에 키보드가 안나탈때가 있어". The dock's two modes are
/// Type (type-through, the mode the founder calls 직접키보드) and Compose.
/// Type mode's editor is a 1×1 invisible view — when its keyboard does not
/// come up there is nothing on screen to tap, so the session cannot type at
/// all until the user leaves and re-enters the mode.
///
/// ## Contract ↔ assertion table (FR-005 → tests)
///
/// | Clause | Test |
/// | --- | --- |
/// | The focus decision reads the editor's real first-responder state, not
///   the `@State` mirror — a mode switch moves the editor in the view tree
///   and the departing instance does not always report, leaving the mirror
///   stale at `true`. |
///   `testRequestsFocusWhenMirrorIsStaleButEditorHasNoFirstResponder` |
/// | An editor that already holds first responder is not asked again (no
///   keyboard churn on every re-render). |
///   `testDoesNotRequestFocusWhenEditorAlreadyHasFirstResponder` |
/// | Focus is only pursued when the dock has been expanded; a collapsed dock
///   must not raise the keyboard behind the user's back. |
///   `testDoesNotRequestFocusWhenExpansionWasNotRequested` |
/// | Direct Keystroke mode owns its own surface and must not have the compose
///   editor steal first responder (spec 002 FR-001). |
///   `testDoesNotRequestFocusWhileDirectKeystrokeModeIsActive` |
final class ComposeFocusAfterModeSwitchTests: XCTestCase {
    // MARK: FR-005 — the defect

    /// The failing case. A Compose→Type switch relocates the compose editor,
    /// so nothing holds first responder, but `composeFieldFocused` can still
    /// read `true` because the departing editor never reported losing it.
    /// The decision must follow the responder, so the keyboard comes back.
    func testRequestsFocusWhenMirrorIsStaleButEditorHasNoFirstResponder() {
        XCTAssertTrue(
            RemoteInputDockView.shouldRequestComposeEditorFocus(
                expansionRequested: true,
                isDirectModeActive: false,
                mirroredFocusFlag: true,
                editorHasFirstResponder: false
            ),
            """
            FR-005 violated: the dock skipped the focus request because its \
            `composeFieldFocused` mirror still read true, while no editor held \
            first responder. In Type mode the editor is invisible, so this is \
            a session the user cannot type in and cannot tap to recover.
            """
        )
    }

    // MARK: FR-005 — the contracts the fix must not break

    func testDoesNotRequestFocusWhenEditorAlreadyHasFirstResponder() {
        XCTAssertFalse(
            RemoteInputDockView.shouldRequestComposeEditorFocus(
                expansionRequested: true,
                isDirectModeActive: false,
                mirroredFocusFlag: true,
                editorHasFirstResponder: true
            ),
            "An editor that already has the keyboard must not be re-asked."
        )
        XCTAssertFalse(
            RemoteInputDockView.shouldRequestComposeEditorFocus(
                expansionRequested: true,
                isDirectModeActive: false,
                // The mirror lagging the other way (false while the editor is
                // focused) must not produce a redundant request either.
                mirroredFocusFlag: false,
                editorHasFirstResponder: true
            )
        )
    }

    func testDoesNotRequestFocusWhenExpansionWasNotRequested() {
        for hasFirstResponder in [true, false] {
            XCTAssertFalse(
                RemoteInputDockView.shouldRequestComposeEditorFocus(
                    expansionRequested: false,
                    isDirectModeActive: false,
                    mirroredFocusFlag: false,
                    editorHasFirstResponder: hasFirstResponder
                ),
                "A collapsed dock must never raise the keyboard on its own."
            )
        }
    }

    func testDoesNotRequestFocusWhileDirectKeystrokeModeIsActive() {
        XCTAssertFalse(
            RemoteInputDockView.shouldRequestComposeEditorFocus(
                expansionRequested: true,
                isDirectModeActive: true,
                mirroredFocusFlag: false,
                editorHasFirstResponder: false
            ),
            "Direct Keystroke mode owns its input surface (spec 002 FR-001)."
        )
    }
}
