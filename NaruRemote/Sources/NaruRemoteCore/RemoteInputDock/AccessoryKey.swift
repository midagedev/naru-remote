import Foundation

/// Accessory-strip presentation metadata for sticky modifiers
/// (spec 011 US2). The strip renders ⌃ ⌥ ⌘ ⇧ before the named keys,
/// matching a physical Mac keyboard's bottom row.
public extension DirectKeystrokeModifier {
    /// Left-to-right strip order.
    static let stripOrder: [DirectKeystrokeModifier] = [
        .control, .alt, .meta, .shift,
    ]

    /// Short strip label in macOS glyph notation (spec 012 US2-3).
    /// The Latin words ("ctrl"/"alt"/"cmd"/"shift") needed 48 pt each
    /// and pushed Esc/Tab/⌃C past the right edge on an iPhone-width
    /// strip; the glyphs fit in 36 pt and match both a physical Mac
    /// keyboard and the ⌃C key next to them. VoiceOver reads the
    /// modifier kind and slot state from `ModifierKeyButton`, not from
    /// this label, so the glyph costs no accessibility information.
    var stripLabel: String {
        switch self {
        case .control: return "⌃"
        case .alt: return "⌥"
        case .meta: return "⌘"
        case .shift: return "⇧"
        }
    }
}

/// A discrete terminal/remote key reachable from the shared accessory
/// strip that sits above the editor in both dock modes (spec 011,
/// modeled on orca mobile's terminal accessory keys).
///
/// Strip keys emit through the same `KeystrokeEmitter` path as the
/// retired Direct soft keyboard and the Compose quick keys: an X11
/// keysym wrapped in any active sticky modifiers (`StickyModifiers`).
/// They never modify the Compose draft and never emit while no session
/// is active.
public enum AccessoryKey: String, Sendable, Equatable, CaseIterable, Codable {
    case escape
    case tab
    case delete
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case home
    case end
    case pageUp
    case pageDown
    case insert
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    /// Short user-facing label for the strip button.
    public var label: String {
        switch self {
        case .escape: return "Esc"
        case .tab: return "Tab"
        case .delete: return "Del"
        case .arrowUp: return "↑"
        case .arrowDown: return "↓"
        case .arrowLeft: return "←"
        case .arrowRight: return "→"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PgUp"
        case .pageDown: return "PgDn"
        case .insert: return "Ins"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        }
    }

    /// Accessibility label (spoken form) for the strip button.
    public var accessibilityLabel: String {
        switch self {
        case .escape: return "Escape"
        case .tab: return "Tab"
        case .delete: return "Forward delete"
        case .arrowUp: return "Arrow up"
        case .arrowDown: return "Arrow down"
        case .arrowLeft: return "Arrow left"
        case .arrowRight: return "Arrow right"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "Page up"
        case .pageDown: return "Page down"
        case .insert: return "Insert"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        }
    }

    /// Whether a hold on this strip key auto-repeats (spec 012 US2-1).
    /// True only for the four arrows and Del — the orca-measured
    /// repeatable set. Backspace is not on this strip. Every other
    /// key fires once: holding Esc/Tab/Fn keys is treated as
    /// destructive.
    public var repeatable: Bool {
        switch self {
        case .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .delete:
            return true
        case .escape, .tab, .home, .end, .pageUp, .pageDown, .insert,
             .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
            return false
        }
    }

    /// The X11 keysym this strip key emits. Sticky modifiers are merged
    /// by the caller (`NaruRemoteAppModel.sendAccessoryKey(_:)`).
    public var keysym: UInt32 {
        switch self {
        case .escape: return KeysymMapping.keysym(for: .escape)
        case .tab: return KeysymMapping.keysym(for: .tab)
        case .delete: return KeysymMapping.keysym(for: .delete)
        case .arrowUp: return KeysymMapping.keysym(for: .up)
        case .arrowDown: return KeysymMapping.keysym(for: .down)
        case .arrowLeft: return KeysymMapping.keysym(for: .left)
        case .arrowRight: return KeysymMapping.keysym(for: .right)
        case .home: return KeysymMapping.keysym(for: .home)
        case .end: return KeysymMapping.keysym(for: .end)
        case .pageUp: return KeysymMapping.keysym(for: .pageUp)
        case .pageDown: return KeysymMapping.keysym(for: .pageDown)
        case .insert: return KeysymMapping.keysym(for: .insert)
        case .f1: return KeysymMapping.keysym(for: .f1)
        case .f2: return KeysymMapping.keysym(for: .f2)
        case .f3: return KeysymMapping.keysym(for: .f3)
        case .f4: return KeysymMapping.keysym(for: .f4)
        case .f5: return KeysymMapping.keysym(for: .f5)
        case .f6: return KeysymMapping.keysym(for: .f6)
        case .f7: return KeysymMapping.keysym(for: .f7)
        case .f8: return KeysymMapping.keysym(for: .f8)
        case .f9: return KeysymMapping.keysym(for: .f9)
        case .f10: return KeysymMapping.keysym(for: .f10)
        case .f11: return KeysymMapping.keysym(for: .f11)
        case .f12: return KeysymMapping.keysym(for: .f12)
        }
    }

    /// Keys always visible on the primary strip row. Kept narrow so
    /// the row remains readable on the smallest iPhone widths without
    /// horizontal scroll.
    public static let primaryStripKeys: [AccessoryKey] = [
        .escape, .tab, .arrowLeft, .arrowUp, .arrowDown, .arrowRight, .delete,
    ]

    /// Keys revealed by the Fn expansion. Arranged to match a physical
    /// keyboard's function-row grouping.
    public static let expandedStripKeys: [AccessoryKey] = [
        .home, .end, .pageUp, .pageDown, .insert,
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12,
    ]
}
