import Foundation

public enum RFBClientMessageEncoder {
    private static let keySymControlLeft: UInt32 = 0xffe3
    private static let keySymMetaLeft: UInt32 = 0xffe7
    private static let keySymLowercaseV: UInt32 = 0x0076

    public static func clientCutText(_ text: String) -> Data {
        let payload = Data(text.utf8)
        var bytes: [UInt8] = [6, 0, 0, 0]
        bytes.append(contentsOf: uint32Bytes(UInt32(payload.count)))
        return Data(bytes) + payload
    }

    public static func pasteCommand(_ command: PasteCommand) -> Data {
        let modifier: UInt32 = switch command {
        case .commandV:
            keySymMetaLeft
        case .controlV:
            keySymControlLeft
        }

        return keyEvent(keysym: modifier, isDown: true) +
            keyEvent(keysym: keySymLowercaseV, isDown: true) +
            keyEvent(keysym: keySymLowercaseV, isDown: false) +
            keyEvent(keysym: modifier, isDown: false)
    }

    public static func keyEvent(keysym: UInt32, isDown: Bool) -> Data {
        var bytes: [UInt8] = [4, isDown ? 1 : 0, 0, 0]
        bytes.append(contentsOf: uint32Bytes(keysym))
        return Data(bytes)
    }

    /// Encodes an RFB `PointerEvent` (RFC 6143 §7.5.5, message type 5).
    ///
    /// Wire layout (6 bytes total):
    ///   - 1 byte: message type (always 5)
    ///   - 1 byte: button-mask — bit 0 = button 1 (left), bit 1 = button 2
    ///     (middle), bit 2 = button 3 (right), bits 3..7 = wheel/extra
    ///   - 2 bytes: x position, big-endian, in remote framebuffer pixel
    ///     coordinates (origin at the top-left of the remote framebuffer)
    ///   - 2 bytes: y position, big-endian, in remote framebuffer pixel
    ///     coordinates
    ///
    /// A button-1 click is the pair `(buttonMask: 0x01, …)` followed by
    /// `(buttonMask: 0x00, …)` at the same `(x, y)`. The encoder is a pure
    /// transformation — caller-provided coordinates are NOT logged at this
    /// boundary (constitution §IV).
    public static func encodePointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) -> Data {
        var bytes: [UInt8] = [5, buttonMask]
        bytes.append(contentsOf: uint16Bytes(x))
        bytes.append(contentsOf: uint16Bytes(y))
        return Data(bytes)
    }

    private static func uint16Bytes(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0x00ff), UInt8(value & 0x00ff)]
    }

    private static func uint32Bytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0x000000ff),
            UInt8((value >> 16) & 0x000000ff),
            UInt8((value >> 8) & 0x000000ff),
            UInt8(value & 0x000000ff)
        ]
    }
}
