import XCTest

/// Raising the input dock in a chosen mode, after spec 033 collapsed the idle
/// dock's two pills into one capsule.
///
/// The capsule shows the mode the session is resting in — Type on an active
/// session, Compose before one — and carries the switch inside itself. So the
/// mode-specific identifier exists only when that mode is the resting one, and
/// a test that needs the *other* mode has to go through the switch. This is
/// where that fork lives, once, for every UITest that raises the dock.
enum DockEntryMode {
    case type
    case compose

    /// The identifier the resting capsule carries when this is the mode.
    var revealIdentifier: String {
        switch self {
        case .type: return "naru.input.type-reveal"
        case .compose: return "naru.input.compose-reveal"
        }
    }

    /// The identifier of this mode's item inside the switch menu.
    var selectIdentifier: String {
        switch self {
        case .type: return "naru.input.mode-select.type"
        case .compose: return "naru.input.mode-select.compose"
        }
    }
}

extension XCUIApplication {
    /// Taps whatever raises the dock in `mode` and returns whether it found it.
    ///
    /// Tries the resting capsule first, because that is the one-tap path a user
    /// takes most often, then the switch menu.
    @discardableResult
    func raiseInputDock(
        in mode: DockEntryMode,
        timeout: TimeInterval = 8
    ) -> Bool {
        let reveal = buttons[mode.revealIdentifier].firstMatch
        if reveal.waitForExistence(timeout: timeout), reveal.isHittable {
            reveal.tap()
            return true
        }

        // The dock can already be up in this mode with the keyboard down —
        // Type mode keeps its keyboard-up layout while the mirror holds a
        // draft, and then there is no capsule to tap, only the keyboard key
        // (spec 035 FR-001).
        if mode == .type {
            let raise = buttons["naru.input.keyboard-raise"].firstMatch
            if raise.exists, raise.isHittable {
                raise.tap()
                return true
            }
        }

        let modeSwitch = buttons["naru.input.mode-switch"].firstMatch
        guard modeSwitch.waitForExistence(timeout: timeout), modeSwitch.isHittable else {
            return false
        }
        modeSwitch.tap()

        let item = buttons[mode.selectIdentifier].firstMatch
        guard item.waitForExistence(timeout: 4), item.isHittable else {
            return false
        }
        item.tap()
        return true
    }
}
