import Foundation
import XCTest
@testable import NaruRemoteCore

final class RFBClientMessageEncoderTests: XCTestCase {
    func testClientCutTextUsesUTF8ByteLength() {
        let text = "한글과 English 😊"
        let message = RFBClientMessageEncoder.clientCutText(text)
        let payload = Data(text.utf8)

        XCTAssertEqual(message.prefix(4), Data([6, 0, 0, 0]))
        XCTAssertEqual(message[4], UInt8((payload.count >> 24) & 0xff))
        XCTAssertEqual(message[5], UInt8((payload.count >> 16) & 0xff))
        XCTAssertEqual(message[6], UInt8((payload.count >> 8) & 0xff))
        XCTAssertEqual(message[7], UInt8(payload.count & 0xff))
        XCTAssertEqual(message.suffix(payload.count), payload)
    }

    func testPasteCommandEmitsModifierAndVKeyEvents() {
        let command = RFBClientMessageEncoder.pasteCommand(.controlV)

        XCTAssertEqual(command.count, 32)
        XCTAssertEqual(command.prefix(8), Data([4, 1, 0, 0, 0, 0, 0xff, 0xe3]))
        XCTAssertEqual(command.dropFirst(8).prefix(8), Data([4, 1, 0, 0, 0, 0, 0, 0x76]))
        XCTAssertEqual(command.dropFirst(16).prefix(8), Data([4, 0, 0, 0, 0, 0, 0, 0x76]))
        XCTAssertEqual(command.dropFirst(24).prefix(8), Data([4, 0, 0, 0, 0, 0, 0xff, 0xe3]))
    }

    func testEncodePointerEventEmitsSixByteRFC6143Frame() {
        let message = RFBClientMessageEncoder.encodePointerEvent(buttonMask: 0x01, x: 100, y: 200)

        // RFC 6143 §7.5.5 wire layout: [type=5][mask][xHi][xLo][yHi][yLo].
        XCTAssertEqual(message.count, 6)
        XCTAssertEqual(message[0], 5)
        XCTAssertEqual(message[1], 0x01)
        XCTAssertEqual(message[2], 0)
        XCTAssertEqual(message[3], 100)
        XCTAssertEqual(message[4], 0)
        XCTAssertEqual(message[5], 200)
    }

    func testEncodePointerEventBoundaryCoordinates() {
        let zero = RFBClientMessageEncoder.encodePointerEvent(buttonMask: 0, x: 0, y: 0)
        XCTAssertEqual(zero, Data([5, 0, 0, 0, 0, 0]))

        // x=65535 exercises the high byte = 0xff path; y stays at 0 so
        // a stuck big-endian decode would surface as a swapped pair.
        let wide = RFBClientMessageEncoder.encodePointerEvent(buttonMask: 0, x: 65535, y: 0)
        XCTAssertEqual(wide, Data([5, 0, 0xff, 0xff, 0, 0]))

        // Asymmetric coordinates catch x/y transposition bugs.
        let asymmetric = RFBClientMessageEncoder.encodePointerEvent(
            buttonMask: 0,
            x: 0x1234,
            y: 0xabcd
        )
        XCTAssertEqual(asymmetric, Data([5, 0, 0x12, 0x34, 0xab, 0xcd]))
    }

    func testEncodePointerEventButtonMaskBoundaries() {
        let none = RFBClientMessageEncoder.encodePointerEvent(buttonMask: 0x00, x: 1, y: 2)
        XCTAssertEqual(none[1], 0x00)

        let all = RFBClientMessageEncoder.encodePointerEvent(buttonMask: 0xFF, x: 1, y: 2)
        XCTAssertEqual(all[1], 0xFF)
    }

    func testEncodePointerEventPreservesEachIndividualButtonMaskBit() {
        // RFC 6143: bits 0..7 of the button-mask byte are forwarded
        // verbatim — bit 0 = button 1 (left), bit 1 = button 2
        // (middle), bit 2 = button 3 (right), bits 3+ = wheel/extra.
        // Each bit must round-trip on its own so a future encoder
        // change does not silently drop, swap, or shift any single
        // button.
        for bit in 0..<8 {
            let mask = UInt8(1 << bit)
            let message = RFBClientMessageEncoder.encodePointerEvent(buttonMask: mask, x: 0, y: 0)
            XCTAssertEqual(message[1], mask, "bit \(bit) did not round-trip")
        }
    }

    // MARK: - KeyEvent (Direct Keystroke Mode coverage)

    func testKeyEventLowercaseCDownProducesEightByteFrame() {
        // Direct Keystroke Mode worked example from
        // contracts/keystroke-emitter.md — pressing 'c' (no modifiers)
        // emits exactly these 8 bytes on the wire.
        let message = RFBClientMessageEncoder.keyEvent(keysym: 0x0063, isDown: true)
        XCTAssertEqual(message, Data([0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x63]))
    }

    func testKeyEventControlLeftReleaseProducesEightByteFrame() {
        // Releasing Control_L (X11 keysym 0xFFE3) is the modifier-up
        // tail of a Ctrl-c chord per contracts/keystroke-emitter.md.
        let message = RFBClientMessageEncoder.keyEvent(keysym: 0xFFE3, isDown: false)
        XCTAssertEqual(message, Data([0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xE3]))
    }

    func testKeyEventBoundaryKeysyms() {
        // 0x00000000 — minimum value — surfaces a broken big-endian
        // encoder as a length-mismatch or wrong-byte error.
        let zero = RFBClientMessageEncoder.keyEvent(keysym: 0x00000000, isDown: true)
        XCTAssertEqual(zero, Data([0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))

        // 0xFFFFFFFF — every keysym byte set — proves all four
        // big-endian byte positions actually carry the correct
        // shifted slice.
        let max = RFBClientMessageEncoder.keyEvent(keysym: 0xFFFFFFFF, isDown: false)
        XCTAssertEqual(max, Data([0x04, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]))

        // Asymmetric value catches byte-order regressions: 0x12345678
        // would survive a swapped-pair bug but not a fully reversed
        // big-endian / little-endian flip.
        let asymmetric = RFBClientMessageEncoder.keyEvent(keysym: 0x12345678, isDown: true)
        XCTAssertEqual(asymmetric, Data([0x04, 0x01, 0x00, 0x00, 0x12, 0x34, 0x56, 0x78]))
    }

    func testKeyEventPaddingBytesAreAlwaysZero() {
        // RFC 6143 §7.5.4 reserves bytes 2-3 as padding. They MUST
        // be 0x00; some servers reject non-zero padding outright.
        for keysym: UInt32 in [0x0000, 0x0063, 0xFF1B, 0xFFE3, 0xFFFFFFFF] {
            for isDown in [true, false] {
                let message = RFBClientMessageEncoder.keyEvent(keysym: keysym, isDown: isDown)
                XCTAssertEqual(message[2], 0, "padding byte 2 not zero for keysym \(keysym)")
                XCTAssertEqual(message[3], 0, "padding byte 3 not zero for keysym \(keysym)")
            }
        }
    }
}
