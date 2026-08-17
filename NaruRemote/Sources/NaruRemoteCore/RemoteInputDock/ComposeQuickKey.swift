import Foundation

/// A discrete terminal-control key reachable from **Compose mode**
/// without switching to Direct Keystroke mode (spec 003 US5 / FR-013).
///
/// Compose & Send remains the multilingual default (constitution §I);
/// this is a convenience bridge for the common "I'm composing Korean
/// but need to hit Esc / Ctrl-C once" case in a terminal / AI-CLI
/// session. Each key resolves to an X11 keysym plus an optional
/// modifier set and is emitted through the same `KeystrokeEmitter` as
/// Direct mode — it never modifies the compose draft.
public enum ComposeQuickKey: String, Sendable, Equatable, CaseIterable, Codable {
    case escape
    case tab
    case controlC
    case up
    case down
    /// Remote BackSpace — a primary Compose action (delete one character
    /// on the remote), not a terminal-strip convenience.
    case backspace
    /// Remote Return/Enter — submit on the remote (run the command you
    /// just sent), a primary Compose action.
    case enter

    /// Short user-facing label for the strip button.
    public var label: String {
        switch self {
        case .escape: return "Esc"
        case .tab: return "Tab"
        case .controlC: return "⌃C"
        case .up: return "↑"
        case .down: return "↓"
        case .backspace: return "⌫"
        case .enter: return "↵"
        }
    }

    /// Accessibility label (spoken form) for the strip button.
    public var accessibilityLabel: String {
        switch self {
        case .escape: return "Escape"
        case .tab: return "Tab"
        case .controlC: return "Control C"
        case .up: return "Up arrow"
        case .down: return "Down arrow"
        case .backspace: return "Backspace"
        case .enter: return "Enter"
        }
    }

    /// The X11 keysym + sticky-modifier set this quick key emits.
    /// `Ctrl-C` is `c` (0x63) wrapped in `[.control]` so the wire
    /// envelope is `Ctrl down → c down → c up → Ctrl up`, byte-
    /// identical to Direct mode's armed-Ctrl + `c` path.
    public var emission: (keysym: UInt32, modifiers: Set<DirectKeystrokeModifier>) {
        switch self {
        case .escape:
            return (KeysymMapping.keysym(for: .escape), [])
        case .tab:
            return (KeysymMapping.keysym(for: .tab), [])
        case .controlC:
            // 'c' lowercase; KeysymMapping returns a non-nil keysym for
            // printable ASCII, but fall back to the literal 0x63 so the
            // type stays total.
            return (KeysymMapping.keysym(for: "c") ?? 0x63, [.control])
        case .up:
            return (KeysymMapping.keysym(for: .up), [])
        case .down:
            return (KeysymMapping.keysym(for: .down), [])
        case .backspace:
            return (KeysymMapping.keysym(for: .backspace), [])
        case .enter:
            return (KeysymMapping.keysym(for: .return), [])
        }
    }

    /// The discrete terminal-strip keys (Esc / Tab / ⌃C / arrows). Spec 011
    /// moved Esc / Tab / arrows onto the shared accessory strip (`AccessoryKey`);
    /// the Compose action row still renders `backspace` / `enter` only.
    /// `controlC` stays on this model for emission but is not a strip button
    /// — the dock does not render `terminalStripKeys`.
    public static let terminalStripKeys: [ComposeQuickKey] = [
        .escape, .tab, .controlC, .up, .down,
    ]
}
