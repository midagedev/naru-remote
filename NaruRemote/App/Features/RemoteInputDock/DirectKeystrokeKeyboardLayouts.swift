import Foundation
import NaruRemoteCore

/// Pure-data static descriptors for the Direct-mode soft keyboard.
/// Two pages: `.qwerty` and `.special`. Each page is a list of rows;
/// each row is a list of keys.  No SwiftUI types here — the
/// `DirectKeystrokeKeyboardView` consumes these and renders.
///
/// Phase 4: Ctrl/Alt/Cmd/Shift on the special-keys page now route
/// through `DirectKey.modifier(_)` so the renderer can branch on
/// `.modifier` role and render `ModifierKeyButton` (three visual
/// states: idle / armed / locked).  The Shift on the QWERTY page
/// stays as a `.named(.shiftLeft)` one-shot for now — sticky shift
/// on the alphabetic page is a separate UX item that ships only
/// when the page-level layout allows it.
enum DirectKeystrokeKeyboardLayouts {

    /// The full layout for a single page.
    struct PageLayout: Equatable {
        let rows: [Row]
    }

    /// One horizontal row of keys.
    struct Row: Equatable {
        let keys: [KeyDescriptor]
    }

    /// One on-screen key.  `widthUnits` is in the same arbitrary
    /// "key width unit" used by all rows on a page — the renderer
    /// computes the actual point width by dividing the available row
    /// width by the row's total units.
    struct KeyDescriptor: Equatable {
        let label: String
        let widthUnits: CGFloat
        let key: DirectKey
        let role: Role

        enum Role: Equatable {
            case standard
            case wide      // backspace, return, shift — visually wider
            case modifier  // Ctrl/Alt/Cmd/Shift visual peer (Phase 4 makes these sticky)
            case toggle    // page-toggle (123/ABC) — never emits a KeyEvent
            case space
        }

        init(
            label: String,
            widthUnits: CGFloat = 1.0,
            key: DirectKey,
            role: Role = .standard
        ) {
            self.label = label
            self.widthUnits = widthUnits
            self.key = key
            self.role = role
        }
    }

    static func layout(for page: KeyboardPage) -> PageLayout {
        switch page {
        case .qwerty:  return qwerty
        case .special: return special
        }
    }

    // MARK: - QWERTY page

    private static let qwerty: PageLayout = PageLayout(rows: [
        // row 1: q w e r t y u i o p
        Row(keys: "qwertyuiop".map { c in
            KeyDescriptor(label: String(c), key: .character(c))
        }),
        // row 2: a s d f g h j k l
        Row(keys: "asdfghjkl".map { c in
            KeyDescriptor(label: String(c), key: .character(c))
        }),
        // row 3: shift z x c v b n m backspace
        Row(keys: [
            KeyDescriptor(label: "⇧",  widthUnits: 1.5, key: .named(.shiftLeft),  role: .modifier),
        ] + "zxcvbnm".map { c in
            KeyDescriptor(label: String(c), key: .character(c))
        } + [
            KeyDescriptor(label: "⌫",  widthUnits: 1.5, key: .named(.backspace),  role: .wide),
        ]),
        // row 4: page-toggle, space, return.  Punch-list #205:
        // the toggle label was previously "123", which read like a
        // generic mode shift (and like the iOS system keyboard).
        // Use the bidirectional arrow glyph "⇄" so the affordance
        // says "switches to special keys" at a glance.  The
        // label "Direct space" on the spacebar plus the
        // surface-raised key fills (see `backgroundFor(role:)`)
        // round out the differentiation from the iOS keyboard.
        Row(keys: [
            KeyDescriptor(label: "⇄",            widthUnits: 1.5, key: .pageToggle,     role: .toggle),
            KeyDescriptor(label: "Direct space", widthUnits: 5.0, key: .character(" "), role: .space),
            KeyDescriptor(label: "return",       widthUnits: 2.5, key: .named(.return), role: .wide),
        ]),
    ])

    // MARK: - Special-keys page

    private static let special: PageLayout = PageLayout(rows: [
        // row 1: digits 1-0
        Row(keys: "1234567890".map { c in
            KeyDescriptor(label: String(c), key: .character(c))
        }),
        // row 2: common shell punctuation
        Row(keys: "-=[]\\;',./".map { c in
            KeyDescriptor(label: String(c), key: .character(c))
        }),
        // row 3: F1-F12 (12 cells)
        Row(keys: [
            KeyDescriptor(label: "F1",  key: .named(.f1)),
            KeyDescriptor(label: "F2",  key: .named(.f2)),
            KeyDescriptor(label: "F3",  key: .named(.f3)),
            KeyDescriptor(label: "F4",  key: .named(.f4)),
            KeyDescriptor(label: "F5",  key: .named(.f5)),
            KeyDescriptor(label: "F6",  key: .named(.f6)),
            KeyDescriptor(label: "F7",  key: .named(.f7)),
            KeyDescriptor(label: "F8",  key: .named(.f8)),
            KeyDescriptor(label: "F9",  key: .named(.f9)),
            KeyDescriptor(label: "F10", key: .named(.f10)),
            KeyDescriptor(label: "F11", key: .named(.f11)),
            KeyDescriptor(label: "F12", key: .named(.f12)),
        ]),
        // row 4: terminal-essential modifiers + Tab + Esc + Clear
        // (Phase 7 / FR-013): Clear sits next to the four sticky
        // modifiers as the panic affordance — one tap drops every
        // armed-or-locked slot back to idle.  Visually styled as a
        // wide key (matching ⌫ / ↵) so it doesn't read as a
        // modifier itself.
        Row(keys: [
            KeyDescriptor(label: "Tab",   widthUnits: 1.25, key: .named(.tab),          role: .wide),
            KeyDescriptor(label: "Esc",   widthUnits: 1.25, key: .named(.escape),       role: .wide),
            KeyDescriptor(label: "⌃",     widthUnits: 1.0,  key: .modifier(.control),   role: .modifier),
            KeyDescriptor(label: "⌥",     widthUnits: 1.0,  key: .modifier(.alt),       role: .modifier),
            KeyDescriptor(label: "⌘",     widthUnits: 1.0,  key: .modifier(.meta),      role: .modifier),
            KeyDescriptor(label: "⇧",     widthUnits: 1.0,  key: .modifier(.shift),     role: .modifier),
            KeyDescriptor(label: "Clr",   widthUnits: 1.0,  key: .clearModifiers,       role: .wide),
            KeyDescriptor(label: "⌫",     widthUnits: 1.25, key: .named(.backspace),    role: .wide),
            KeyDescriptor(label: "↵",     widthUnits: 1.25, key: .named(.return),       role: .wide),
        ]),
        // row 5: nav cluster + page-back.  Same bidirectional
        // arrow as the QWERTY toggle — the glyph reads "switch
        // pages" regardless of which page the user is currently on.
        Row(keys: [
            KeyDescriptor(label: "⇄",     widthUnits: 1.5, key: .pageToggle,           role: .toggle),
            KeyDescriptor(label: "←",     key: .named(.left)),
            KeyDescriptor(label: "↓",     key: .named(.down)),
            KeyDescriptor(label: "↑",     key: .named(.up)),
            KeyDescriptor(label: "→",     key: .named(.right)),
            KeyDescriptor(label: "Home",  key: .named(.home)),
            KeyDescriptor(label: "End",   key: .named(.end)),
            KeyDescriptor(label: "PgUp",  key: .named(.pageUp)),
            KeyDescriptor(label: "PgDn",  key: .named(.pageDown)),
            KeyDescriptor(label: "Ins",   key: .named(.insert)),
            KeyDescriptor(label: "Del",   key: .named(.delete)),
        ]),
    ])
}
