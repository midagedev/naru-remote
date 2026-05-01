#if canImport(UIKit)
import UIKit
import NaruRemoteCore

/// App-side overload of `KeysymMapping` that translates raw
/// `UIKeyboardHIDUsage` values from a hardware keyboard's
/// `pressesBegan(_:with:)` / `pressesEnded(_:with:)` stream into the
/// X11 keysyms `KeystrokeEmitter` already speaks (`research.md` R-1
/// for the locked values, R-2 for the capture API choice, R-4 for
/// Cmd → Meta_L).
///
/// **Hardware-path keysym convention**: the values returned here are
/// always the **shift-unmodified** form — lowercase ASCII letter,
/// base-row symbol.  Capitalization is the remote VNC server's job
/// because the user's Shift_L UIPress fires its own modifier-down /
/// modifier-up around the character press, exactly like a physical
/// X server would see it.  This convention matches what `xev` shows
/// for hardware typing on Linux and is what makes SC-005 (byte
/// identity between on-screen and hardware paths) hold by
/// construction.
///
/// Per FR-015, any `UIKeyboardHIDUsage` value with no X11 mapping
/// (Globe, Dictation, function-row consumer keys, error-rollover
/// sentinel, etc.) returns `nil` so the caller drops the press
/// silently.
///
/// `KeysymMapping` is a NaruRemoteCore type; extending it from the
/// App module is fine because the extension only adds new static
/// methods — it does not perturb the Core surface for tests that
/// build Core in isolation.
extension KeysymMapping {
    /// Map a hardware-keyboard `UIPress.key.keyCode` to its X11
    /// keysym, or `nil` if the key has no X11 mapping (Globe,
    /// Dictation, etc. — FR-015 silent drop).
    public static func keysym(forUIKeyCode code: UIKeyboardHIDUsage) -> UInt32? {
        switch code {

        // MARK: Letters — keyboardA (4) … keyboardZ (29) → 0x61 … 0x7A.
        case .keyboardA: return 0x61
        case .keyboardB: return 0x62
        case .keyboardC: return 0x63
        case .keyboardD: return 0x64
        case .keyboardE: return 0x65
        case .keyboardF: return 0x66
        case .keyboardG: return 0x67
        case .keyboardH: return 0x68
        case .keyboardI: return 0x69
        case .keyboardJ: return 0x6A
        case .keyboardK: return 0x6B
        case .keyboardL: return 0x6C
        case .keyboardM: return 0x6D
        case .keyboardN: return 0x6E
        case .keyboardO: return 0x6F
        case .keyboardP: return 0x70
        case .keyboardQ: return 0x71
        case .keyboardR: return 0x72
        case .keyboardS: return 0x73
        case .keyboardT: return 0x74
        case .keyboardU: return 0x75
        case .keyboardV: return 0x76
        case .keyboardW: return 0x77
        case .keyboardX: return 0x78
        case .keyboardY: return 0x79
        case .keyboardZ: return 0x7A

        // MARK: Top-row digits — base-row glyphs (no shift glyphs here;
        // shifted symbols are produced by the remote when Shift_L
        // is also pressed via its own UIPress).
        case .keyboard1: return 0x31
        case .keyboard2: return 0x32
        case .keyboard3: return 0x33
        case .keyboard4: return 0x34
        case .keyboard5: return 0x35
        case .keyboard6: return 0x36
        case .keyboard7: return 0x37
        case .keyboard8: return 0x38
        case .keyboard9: return 0x39
        case .keyboard0: return 0x30

        // MARK: Whitespace / control.
        case .keyboardSpacebar:           return 0x20
        case .keyboardReturnOrEnter:      return 0xFF0D
        case .keyboardEscape:             return 0xFF1B
        case .keyboardTab:                return 0xFF09
        case .keyboardDeleteOrBackspace:  return 0xFF08
        case .keyboardDeleteForward:      return 0xFFFF

        // MARK: Punctuation — base-row glyphs (US QWERTY layout per
        // UIKeyboardHIDUsage's `keyboard*` naming).
        case .keyboardHyphen:             return 0x2D  // "-"
        case .keyboardEqualSign:          return 0x3D  // "="
        case .keyboardOpenBracket:        return 0x5B  // "["
        case .keyboardCloseBracket:       return 0x5D  // "]"
        case .keyboardBackslash:          return 0x5C  // "\\"
        case .keyboardSemicolon:          return 0x3B  // ";"
        case .keyboardQuote:              return 0x27  // "'"
        case .keyboardGraveAccentAndTilde: return 0x60 // "`"
        case .keyboardComma:              return 0x2C  // ","
        case .keyboardPeriod:             return 0x2E  // "."
        case .keyboardSlash:              return 0x2F  // "/"

        // MARK: Modifiers (left side; per R-4 always _Left).
        case .keyboardLeftControl:  return 0xFFE3
        case .keyboardLeftShift:    return 0xFFE1
        case .keyboardLeftAlt:      return 0xFFE9
        case .keyboardLeftGUI:      return 0xFFE7   // Cmd → Meta_L (R-4).
        case .keyboardRightControl: return 0xFFE3
        case .keyboardRightShift:   return 0xFFE1
        case .keyboardRightAlt:     return 0xFFE9
        case .keyboardRightGUI:     return 0xFFE7

        // MARK: Function row (F1..F12 — sequential 0xFFBE..0xFFC9).
        case .keyboardF1:  return 0xFFBE
        case .keyboardF2:  return 0xFFBF
        case .keyboardF3:  return 0xFFC0
        case .keyboardF4:  return 0xFFC1
        case .keyboardF5:  return 0xFFC2
        case .keyboardF6:  return 0xFFC3
        case .keyboardF7:  return 0xFFC4
        case .keyboardF8:  return 0xFFC5
        case .keyboardF9:  return 0xFFC6
        case .keyboardF10: return 0xFFC7
        case .keyboardF11: return 0xFFC8
        case .keyboardF12: return 0xFFC9

        // MARK: Arrows.
        case .keyboardLeftArrow:  return 0xFF51
        case .keyboardUpArrow:    return 0xFF52
        case .keyboardRightArrow: return 0xFF53
        case .keyboardDownArrow:  return 0xFF54

        // MARK: Navigation.
        case .keyboardHome:     return 0xFF50
        case .keyboardEnd:      return 0xFF57
        case .keyboardPageUp:   return 0xFF55
        case .keyboardPageDown: return 0xFF56
        case .keyboardInsert:   return 0xFF63

        // MARK: Unmapped — Globe, Dictation, brightness, error-rollover,
        // keypad keys we do not need for terminal use, etc.  Drop
        // silently per FR-015.
        default:
            return nil
        }
    }

    /// Translate `UIKey.modifierFlags` (or
    /// `UIPressesEvent.modifierFlags`) into the sticky-modifier set
    /// `KeystrokeEmitter` consumes.
    ///
    /// Per R-4, `.command` maps to `.meta` so the wire emits
    /// Meta_L (0xFFE7) regardless of device class.  `.alphaShift`
    /// (caps-lock) and `.numericPad` are deliberately ignored — they
    /// are not part of Naru's sticky-modifier set, and a remote
    /// VNC server interprets caps-lock as the user pressing the
    /// physical key (a separate `keyboardCapsLock` UIPress flows
    /// through the regular handler).
    public static func modifiers(
        fromUIKeyModifierFlags flags: UIKeyModifierFlags
    ) -> Set<DirectKeystrokeModifier> {
        var modifiers: Set<DirectKeystrokeModifier> = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift)   { modifiers.insert(.shift)   }
        if flags.contains(.alternate) { modifiers.insert(.alt)   }
        if flags.contains(.command) { modifiers.insert(.meta)    }
        return modifiers
    }
}
#endif
