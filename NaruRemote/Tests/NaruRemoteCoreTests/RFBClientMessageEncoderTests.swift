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

    func testExtendedClipboardCapsUsesNegativeLengthAndTextCapability() throws {
        let message = try RFBClientMessageEncoder.extendedClipboardCaps(textMaximumBytes: 4096)
        let expectedFlags: RFBExtendedClipboardFlags = [
            .text,
            .caps,
            .request,
            .notify,
            .provide
        ]

        XCTAssertEqual(message.count, 16)
        XCTAssertEqual(message.prefix(4), Data([6, 0, 0, 0]))
        XCTAssertEqual(Self.int32(message, at: 4), -8)
        XCTAssertEqual(Self.uint32(message, at: 8), expectedFlags.rawValue)
        XCTAssertEqual(Self.uint32(message, at: 12), 4096)
    }

    func testExtendedClipboardProvideTextCarriesUTF8Payload() throws {
        let message = try RFBClientMessageEncoder.extendedClipboardProvideText("첫줄\n둘째 😊")
        let expectedFlags: RFBExtendedClipboardFlags = [.text, .provide]
        var serverMessage = message
        serverMessage[serverMessage.startIndex] = 3

        XCTAssertEqual(message.prefix(4), Data([6, 0, 0, 0]))
        XCTAssertLessThan(Self.int32(message, at: 4), 0)
        XCTAssertEqual(Self.uint32(message, at: 8), expectedFlags.rawValue)

        guard case .extendedClipboard(let decoded) = try RFBProtocolDecoder.parseServerCutTextMessage(serverMessage) else {
            XCTFail("Expected extended clipboard message")
            return
        }
        XCTAssertTrue(decoded.flags.contains(.text))
        XCTAssertTrue(decoded.flags.contains(.provide))
        XCTAssertEqual(decoded.text, "첫줄\n둘째 😊")
    }

    func testExtendedClipboardProvideTextUsesSingleRFC1950ZlibWrapper() throws {
        let message = try RFBClientMessageEncoder.extendedClipboardProvideText("hello")

        // Ground truth from Python `zlib.compress` over:
        // [u32 text length = 6]["hello"][NUL].
        let expectedCompressed = Data([
            0x78, 0x9c,
            0x63, 0x60, 0x60, 0x60, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x67, 0x00, 0x00,
            0x08, 0x6f, 0x02, 0x1b
        ])
        let compressed = message.subdata(in: 12..<message.count)

        XCTAssertEqual(compressed, expectedCompressed)
        XCTAssertEqual(compressed.prefix(2), Data([0x78, 0x9c]))
        XCTAssertNotEqual(compressed.dropFirst(2).prefix(2), Data([0x78, 0x9c]))
    }

    func testPasteCommandEmitsModifierAndVKeyEvents() {
        let command = RFBClientMessageEncoder.pasteCommand(.controlV)

        XCTAssertEqual(command.count, 32)
        XCTAssertEqual(command.prefix(8), Data([4, 1, 0, 0, 0, 0, 0xff, 0xe3]))
        XCTAssertEqual(command.dropFirst(8).prefix(8), Data([4, 1, 0, 0, 0, 0, 0, 0x76]))
        XCTAssertEqual(command.dropFirst(16).prefix(8), Data([4, 0, 0, 0, 0, 0, 0, 0x76]))
        XCTAssertEqual(command.dropFirst(24).prefix(8), Data([4, 0, 0, 0, 0, 0, 0xff, 0xe3]))
    }

    func testCommandVPasteUsesMetaLeftMapping() {
        let command = RFBClientMessageEncoder.pasteCommand(.commandV)

        XCTAssertEqual(command.count, 32)
        XCTAssertEqual(command.prefix(8), Data([4, 1, 0, 0, 0, 0, 0xff, 0xe7]))
        XCTAssertEqual(command.dropFirst(8).prefix(8), Data([4, 1, 0, 0, 0, 0, 0, 0x76]))
        XCTAssertEqual(command.dropFirst(16).prefix(8), Data([4, 0, 0, 0, 0, 0, 0, 0x76]))
        XCTAssertEqual(command.dropFirst(24).prefix(8), Data([4, 0, 0, 0, 0, 0, 0xff, 0xe7]))
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

    // MARK: - Continuous updates / fence pacing extensions

    func testEnableContinuousUpdatesProducesTigerVNCWireFrame() {
        let message = RFBClientMessageEncoder.enableContinuousUpdates(
            true,
            x: 1,
            y: 2,
            width: 300,
            height: 400
        )

        XCTAssertEqual(message, Data([
            150, 1,
            0, 1,
            0, 2,
            0x01, 0x2c,
            0x01, 0x90
        ]))
    }

    func testClientFenceProducesTigerVNCWireFrame() throws {
        let payload = Data([0xaa, 0xbb, 0xcc])
        let message = try RFBClientMessageEncoder.fence(flags: [.request, .syncNext], payload: payload)

        XCTAssertEqual(message, Data([
            248, 0, 0, 0,
            0x80, 0x00, 0x00, 0x04,
            3,
            0xaa, 0xbb, 0xcc
        ]))
    }

    func testClientFenceRejectsUnsupportedFlagsAndOversizedPayload() {
        XCTAssertThrowsError(
            try RFBClientMessageEncoder.fence(flags: RFBFenceFlags(rawValue: 1 << 8))
        ) { error in
            XCTAssertEqual(error as? RFBClientMessageEncodingError, .unsupportedFenceFlags(1 << 8))
        }

        XCTAssertThrowsError(
            try RFBClientMessageEncoder.fence(flags: .request, payload: Data(repeating: 0, count: 65))
        ) { error in
            XCTAssertEqual(
                error as? RFBClientMessageEncodingError,
                .fencePayloadTooLarge(maximum: 64, actual: 65)
            )
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

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        let bytes = [UInt8](data)
        return UInt32(bytes[offset]) << 24 |
            UInt32(bytes[offset + 1]) << 16 |
            UInt32(bytes[offset + 2]) << 8 |
            UInt32(bytes[offset + 3])
    }

    private static func int32(_ data: Data, at offset: Int) -> Int32 {
        Int32(bitPattern: uint32(data, at: offset))
    }
}
