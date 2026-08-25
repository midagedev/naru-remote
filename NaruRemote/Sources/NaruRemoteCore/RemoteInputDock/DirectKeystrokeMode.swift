import Foundation

/// In-memory state for Direct Keystroke Streaming Mode (the named
/// constitution §I "MAY" exception). Resets on every fresh session
/// per `spec.md` FR-014 — Direct mode never persists across
/// disconnect / reconnect cycles or app launches; the user opts in
/// per session.
public struct DirectKeystrokeMode: Sendable, Equatable, Codable {
    public var isActive: Bool
    public var page: KeyboardPage
    public var inputSurface: DirectKeystrokeInputSurface
    public var hasShownEntryWarningThisSession: Bool

    public init(
        isActive: Bool = false,
        page: KeyboardPage = .qwerty,
        inputSurface: DirectKeystrokeInputSurface = .customKeyboard,
        hasShownEntryWarningThisSession: Bool = false
    ) {
        self.isActive = isActive
        self.page = page
        self.inputSurface = inputSurface
        self.hasShownEntryWarningThisSession = hasShownEntryWarningThisSession
    }
}

public extension DirectKeystrokeMode {
    enum CodingKeys: String, CodingKey {
        case isActive
        case page
        case inputSurface
        case hasShownEntryWarningThisSession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isActive: try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false,
            page: try container.decodeIfPresent(KeyboardPage.self, forKey: .page) ?? .qwerty,
            inputSurface: try container.decodeIfPresent(
                DirectKeystrokeInputSurface.self,
                forKey: .inputSurface
            ) ?? .customKeyboard,
            hasShownEntryWarningThisSession: try container.decodeIfPresent(
                Bool.self,
                forKey: .hasShownEntryWarningThisSession
            ) ?? false
        )
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

/// Which local input surface is active while Direct Keystroke mode
/// is enabled.
///
/// `.customKeyboard` keeps the original FR-001 behavior: the iOS
/// system keyboard is suppressed and Naru's terminal-oriented key
/// grid is shown. `.systemKeyboard` intentionally opts into iOS'
/// built-in ASCII keyboard for users who prefer the native typing
/// feel. `.hardwareKeyboard` keeps a raw `UIPress` responder alive
/// while hiding both software keyboards so a Bluetooth / Magic
/// Keyboard does not waste screen space.
public enum DirectKeystrokeInputSurface: String, Sendable, Equatable, Codable, CaseIterable {
    case customKeyboard
    case systemKeyboard
    case hardwareKeyboard
}

/// Logical key event surfaced from the custom soft keyboard view to
/// `NaruRemoteAppModel.tapDirectKey(_:)`.
///
/// - `.character`/`.named` emit a wire `KeyEvent` (wrapped by any
///   armed-or-locked modifiers from `StickyModifiers`).
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
    case modifier(DirectKeystrokeModifier)
    case clearModifiers
}
