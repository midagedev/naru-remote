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

    private static func uint32Bytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0x000000ff),
            UInt8((value >> 16) & 0x000000ff),
            UInt8((value >> 8) & 0x000000ff),
            UInt8(value & 0x000000ff)
        ]
    }
}
