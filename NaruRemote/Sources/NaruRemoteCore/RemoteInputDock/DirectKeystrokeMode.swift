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
/// `NaruRemoteAppModel.tapDirectKey(_:)`. Phase 3 only handles
/// `.character`, `.named`, and `.pageToggle`; Phase 4 will add
/// `.modifier(_)` and `.clearModifiers` once `StickyModifierState`
/// lands.
public enum DirectKey: Sendable, Equatable {
    case character(Character)
    case named(KeysymMapping.NamedKey)
    case pageToggle
}
