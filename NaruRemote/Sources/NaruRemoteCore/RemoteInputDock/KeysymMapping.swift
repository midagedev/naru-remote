import Foundation

/// Pure-logic mapping table from on-screen keys (and, via the
/// App-side `KeysymMapping+UIKit` overload, hardware `UIKey.keyCode`
/// values) to X11 keysyms used on the RFB wire (RFC 6143 §7.5.4).
///
/// One source-of-truth for both Direct Keystroke Streaming Mode
/// emission paths so the on-screen and hardware paths are
/// byte-identical on the wire (`spec.md` SC-005). Core stays
/// UIKit-free; the `UIKey.keyCode` overload lives App-side under
/// `#if canImport(UIKit)` and reuses the keysyms defined here.
///
/// Direct mode is English-only by spec (constitution §I default
/// keeps multilingual text on Compose & Send); non-ASCII characters
/// return `nil` from `keysym(for character:)`.
public enum KeysymMapping {
    /// Closed set of named keys the custom soft keyboard's
    /// special-keys page renders, plus the four sticky-modifier
    /// keysyms. Inline raw values come from X.Org's
    /// `keysymdef.h` and are stable since 1989; see
    /// `specs/002-direct-keystroke-mode/research.md` R-1.
    public enum NamedKey: String, Sendable, Equatable, CaseIterable, Codable {
        case backspace
        case tab
        case `return`
        case escape
        case left
        case up
        case right
        case down
        case home
        case end
        case pageUp
        case pageDown
        case insert
        case delete
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
        case shiftLeft
        case controlLeft
        case altLeft
        case metaLeft
    }

    /// Printable ASCII (`0x20`–`0x7E`) maps to the identical X11
    /// keysym integer. Non-ASCII characters return `nil` —
    /// constitution §I keeps multilingual text on Compose & Send,
    /// so a Direct-mode keyboard tap on a non-ASCII glyph drops
    /// silently (FR-015 surface; the on-screen QWERTY page does
    /// not render non-ASCII keys).
    public static func keysym(for character: Character) -> UInt32? {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1
        else {
            return nil
        }

        let value = scalar.value
        guard (0x20 ... 0x7E).contains(value) else {
            return nil
        }

        return value
    }

    /// Named keys map to their X11 keysym constants. Total
    /// surface, never `nil` — every `NamedKey.allCases` entry has
    /// a keysym by construction.
    public static func keysym(for namedKey: NamedKey) -> UInt32 {
        switch namedKey {
        case .backspace:    return 0xFF08
        case .tab:          return 0xFF09
        case .return:       return 0xFF0D
        case .escape:       return 0xFF1B
        case .home:         return 0xFF50
        case .left:         return 0xFF51
        case .up:           return 0xFF52
        case .right:        return 0xFF53
        case .down:         return 0xFF54
        case .pageUp:       return 0xFF55
        case .pageDown:     return 0xFF56
        case .end:          return 0xFF57
        case .insert:       return 0xFF63
        case .delete:       return 0xFFFF
        case .f1:           return 0xFFBE
        case .f2:           return 0xFFBF
        case .f3:           return 0xFFC0
        case .f4:           return 0xFFC1
        case .f5:           return 0xFFC2
        case .f6:           return 0xFFC3
        case .f7:           return 0xFFC4
        case .f8:           return 0xFFC5
        case .f9:           return 0xFFC6
        case .f10:          return 0xFFC7
        case .f11:          return 0xFFC8
        case .f12:          return 0xFFC9
        case .shiftLeft:    return 0xFFE1
        case .controlLeft:  return 0xFFE3
        case .altLeft:      return 0xFFE9
        case .metaLeft:     return 0xFFE7
        }
    }
}
