#if canImport(UIKit)
import XCTest
import UIKit
import NaruRemoteCore
@testable import NaruRemoteApp

/// Phase 5 / US-3 / T029.
///
/// `KeysymMapping+UIKit` (App-side overload) must translate every
/// `UIKeyboardHIDUsage` produced by `UIPress.key.keyCode` into the
/// X11 keysym the on-screen path emits.  This test pins the locked
/// values from `data-model.md` so SC-005 (byte-identical wire output
/// across the two input sources) holds by construction.
///
/// Naming: per the hardware-path decision in the PR-E task brief,
/// hardware keysyms are always the **shift-unmodified** form
/// (lowercase letter / base symbol).  Capitalization is the remote
/// VNC server's responsibility because the modifier-key UIPress
/// fires its own Shift_L down/up around the character UIPress.  This
/// matches what `xev` shows for hardware typing on Linux and the
/// X11 protocol contract.
final class KeysymMappingUIKitTests: XCTestCase {

    // MARK: - Printable ASCII letters (keyboardA … keyboardZ → 0x61 … 0x7A)

    func testKeyboardAMapsToLowercaseA() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardA), 0x61)
    }

    func testKeyboardZMapsToLowercaseZ() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardZ), 0x7A)
    }

    func testKeyboardLetterRangeIsSequentialLowercaseAscii() {
        // a..z = 0x61..0x7A in ASCII; UIKeyboardHIDUsage's letter
        // codes are sequential `keyboardA` (4) … `keyboardZ` (29).
        let pairs: [(UIKeyboardHIDUsage, UInt32)] = [
            (.keyboardA, 0x61), (.keyboardB, 0x62), (.keyboardC, 0x63),
            (.keyboardD, 0x64), (.keyboardE, 0x65), (.keyboardF, 0x66),
            (.keyboardG, 0x67), (.keyboardH, 0x68), (.keyboardI, 0x69),
            (.keyboardJ, 0x6A), (.keyboardK, 0x6B), (.keyboardL, 0x6C),
            (.keyboardM, 0x6D), (.keyboardN, 0x6E), (.keyboardO, 0x6F),
            (.keyboardP, 0x70), (.keyboardQ, 0x71), (.keyboardR, 0x72),
            (.keyboardS, 0x73), (.keyboardT, 0x74), (.keyboardU, 0x75),
            (.keyboardV, 0x76), (.keyboardW, 0x77), (.keyboardX, 0x78),
            (.keyboardY, 0x79), (.keyboardZ, 0x7A),
        ]
        for (code, expected) in pairs {
            XCTAssertEqual(
                KeysymMapping.keysym(forUIKeyCode: code),
                expected,
                "UIKeyboardHIDUsage(\(code.rawValue)) → \(String(expected, radix: 16))"
            )
        }
    }

    // MARK: - Printable ASCII top row (digits 1..9, 0)

    func testKeyboardDigitsMapToAsciiDigits() {
        let pairs: [(UIKeyboardHIDUsage, UInt32)] = [
            (.keyboard1, 0x31), (.keyboard2, 0x32), (.keyboard3, 0x33),
            (.keyboard4, 0x34), (.keyboard5, 0x35), (.keyboard6, 0x36),
            (.keyboard7, 0x37), (.keyboard8, 0x38), (.keyboard9, 0x39),
            (.keyboard0, 0x30),
        ]
        for (code, expected) in pairs {
            XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: code), expected)
        }
    }

    // MARK: - Whitespace / control keys

    func testKeyboardSpacebarMapsToSpace() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardSpacebar), 0x20)
    }

    func testKeyboardReturnOrEnterMapsToReturn() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardReturnOrEnter), 0xFF0D)
    }

    func testKeyboardEscapeMapsToEscape() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardEscape), 0xFF1B)
    }

    func testKeyboardTabMapsToTab() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardTab), 0xFF09)
    }

    func testKeyboardDeleteOrBackspaceMapsToBackspace() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardDeleteOrBackspace), 0xFF08)
    }

    func testKeyboardDeleteForwardMapsToDelete() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardDeleteForward), 0xFFFF)
    }

    // MARK: - Modifier keys (left side; per R-4 always _Left)

    func testKeyboardLeftControlMapsToControlLeft() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardLeftControl), 0xFFE3)
    }

    func testKeyboardLeftShiftMapsToShiftLeft() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardLeftShift), 0xFFE1)
    }

    func testKeyboardLeftAltMapsToAltLeft() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardLeftAlt), 0xFFE9)
    }

    func testKeyboardLeftGUIMapsToMetaLeftPerR4() {
        // R-4: the Cmd key emits Meta_L (0xFFE7) on every device
        // class — the X11 keysym is the wire contract; remote-side
        // meaning is the remote OS's job.
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardLeftGUI), 0xFFE7)
    }

    // MARK: - Function keys (F1..F12)

    func testKeyboardF1MapsToF1() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardF1), 0xFFBE)
    }

    func testKeyboardF12MapsToF12() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardF12), 0xFFC9)
    }

    func testKeyboardF1ThroughF12IsSequential() {
        let codes: [UIKeyboardHIDUsage] = [
            .keyboardF1, .keyboardF2, .keyboardF3, .keyboardF4,
            .keyboardF5, .keyboardF6, .keyboardF7, .keyboardF8,
            .keyboardF9, .keyboardF10, .keyboardF11, .keyboardF12,
        ]
        for (offset, code) in codes.enumerated() {
            XCTAssertEqual(
                KeysymMapping.keysym(forUIKeyCode: code),
                UInt32(0xFFBE + offset),
                "F\(offset + 1) keysym"
            )
        }
    }

    // MARK: - Arrow keys

    func testKeyboardArrowsMapToX11Arrows() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardLeftArrow), 0xFF51)
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardUpArrow), 0xFF52)
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardRightArrow), 0xFF53)
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardDownArrow), 0xFF54)
    }

    // MARK: - Navigation

    func testKeyboardNavigationKeysMapToX11Constants() {
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardHome), 0xFF50)
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardEnd), 0xFF57)
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardPageUp), 0xFF55)
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardPageDown), 0xFF56)
        XCTAssertEqual(KeysymMapping.keysym(forUIKeyCode: .keyboardInsert), 0xFF63)
    }

    // MARK: - Unmapped keys return nil (FR-015 silent drop)

    func testGlobeKeyReturnsNilSilentDrop() {
        // .keyboardLANG1 / Globe / Dictation etc. are not in our
        // X11 mapping; per FR-015 the hardware path drops them.
        // Use a code that's known-unmapped — the "Reserved"
        // sentinel is explicitly listed in UIKeyboardHIDUsage.
        XCTAssertNil(KeysymMapping.keysym(forUIKeyCode: .keyboardErrorRollOver))
    }

    // MARK: - modifiers(from:)

    func testModifiersFromEmptyFlagsIsEmpty() {
        XCTAssertEqual(KeysymMapping.modifiers(fromUIKeyModifierFlags: []), [])
    }

    func testModifiersFromControlFlag() {
        XCTAssertEqual(
            KeysymMapping.modifiers(fromUIKeyModifierFlags: .control),
            [.control]
        )
    }

    func testModifiersFromShiftFlag() {
        XCTAssertEqual(
            KeysymMapping.modifiers(fromUIKeyModifierFlags: .shift),
            [.shift]
        )
    }

    func testModifiersFromAlternateFlagMapsToAlt() {
        XCTAssertEqual(
            KeysymMapping.modifiers(fromUIKeyModifierFlags: .alternate),
            [.alt]
        )
    }

    func testModifiersFromCommandFlagMapsToMetaPerR4() {
        // R-4: Command on iPhone/iPad keyboards emits Meta_L (0xFFE7).
        XCTAssertEqual(
            KeysymMapping.modifiers(fromUIKeyModifierFlags: .command),
            [.meta]
        )
    }

    func testModifiersFromControlShiftAltCommandIsAllFour() {
        let flags: UIKeyModifierFlags = [.control, .shift, .alternate, .command]
        XCTAssertEqual(
            KeysymMapping.modifiers(fromUIKeyModifierFlags: flags),
            [.control, .shift, .alt, .meta]
        )
    }

    func testModifiersFromUnrelatedFlagsDoesNotInjectSpurious() {
        // .alphaShift (caps-lock) and .numericPad are not in our
        // sticky-modifier set; they must not produce phantom flags.
        XCTAssertEqual(
            KeysymMapping.modifiers(fromUIKeyModifierFlags: .alphaShift),
            []
        )
        XCTAssertEqual(
            KeysymMapping.modifiers(fromUIKeyModifierFlags: .numericPad),
            []
        )
    }
}
#endif
