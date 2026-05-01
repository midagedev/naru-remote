import Foundation

/// In-memory state for Direct Keystroke Streaming Mode (the named
/// constitution §I "MAY" exception). Resets on every fresh session
/// per `spec.md` FR-014 — Direct mode never persists across
/// disconnect / reconnect cycles or app launches; the user opts in
/// per session.
public struct DirectKeystrokeMode: Sendable, Equatable, Codable {
    public var isActive: Bool
    public var page: KeyboardPage
    public var hasShownEntryWarningThisSession: Bool

    public init(
        isActive: Bool = false,
        page: KeyboardPage = .qwerty,
        hasShownEntryWarningThisSession: Bool = false
    ) {
        self.isActive = isActive
        self.page = page
        self.hasShownEntryWarningThisSession = hasShownEntryWarningThisSession
    }
}

/// Which page of the custom soft keyboard is currently rendered.
/// Defaults to `.qwerty` on every Direct-mode entry — fresh entry =
/// familiar layout, the user toggles to `.special` via the
/// in-keyboard page button.
public enum KeyboardPage: String, Sendable, Equatable, Codable {
    case qwerty
    case special
}

/// Logical key event surfaced from the custom soft keyboard view to
/// `NaruRemoteAppModel.tapDirectKey(_:)`.
///
/// - `.character`/`.named` emit a wire `KeyEvent` (wrapped by any
///   armed-or-locked modifiers from `StickyModifierState`).
/// - `.pageToggle` swaps QWERTY ↔ special-keys page; never emits.
/// - `.modifier(_)` taps a sticky-modifier slot
///   (idle → armed → locked transitions); never emits a wire
///   `KeyEvent` directly — the modifier is applied to the next
///   non-modifier emission.
/// - `.clearModifiers` is the FR-013 panic clear; resets all four
///   sticky slots to idle.
public enum DirectKey: Sendable, Equatable {
    case character(Character)
    case named(KeysymMapping.NamedKey)
    case pageToggle
    case modifier(StickyModifierState.Modifier)
    case clearModifiers
}
