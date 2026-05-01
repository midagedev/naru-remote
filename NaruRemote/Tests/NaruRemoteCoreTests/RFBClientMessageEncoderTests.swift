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
}
