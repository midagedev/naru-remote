import Foundation
import Compression

public struct RFBExtendedClipboardFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let text = RFBExtendedClipboardFlags(rawValue: 1 << 0)
    public static let rtf = RFBExtendedClipboardFlags(rawValue: 1 << 1)
    public static let html = RFBExtendedClipboardFlags(rawValue: 1 << 2)
    public static let dib = RFBExtendedClipboardFlags(rawValue: 1 << 3)
    public static let files = RFBExtendedClipboardFlags(rawValue: 1 << 4)

    public static let caps = RFBExtendedClipboardFlags(rawValue: 1 << 24)
    public static let request = RFBExtendedClipboardFlags(rawValue: 1 << 25)
    public static let peek = RFBExtendedClipboardFlags(rawValue: 1 << 26)
    public static let notify = RFBExtendedClipboardFlags(rawValue: 1 << 27)
    public static let provide = RFBExtendedClipboardFlags(rawValue: 1 << 28)
}

public struct RFBFenceFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let blockBefore = RFBFenceFlags(rawValue: 1 << 0)
    public static let blockAfter = RFBFenceFlags(rawValue: 1 << 1)
    public static let syncNext = RFBFenceFlags(rawValue: 1 << 2)
    public static let request = RFBFenceFlags(rawValue: 1 << 31)

    public static let supported: RFBFenceFlags = [
        .blockBefore,
        .blockAfter,
        .syncNext,
        .request
    ]
}

public enum RFBClientMessageEncodingError: Error, Equatable {
    case unsupportedFenceFlags(UInt32)
    case fencePayloadTooLarge(maximum: Int, actual: Int)
    case extendedClipboardPayloadTooLarge(maximum: Int, actual: Int)
    case zlibCompressionFailed
}

public enum RFBClientMessageEncoder {
    private static let keySymControlLeft: UInt32 = 0xffe3
    private static let keySymAltLeft: UInt32 = 0xffe9
    private static let keySymMetaLeft: UInt32 = 0xffe7
    private static let keySymLowercaseV: UInt32 = 0x0076
    private static let maxFencePayloadLength = 64

    public static func clientCutText(_ text: String) -> Data {
        let payload = Data(text.utf8)
        var bytes: [UInt8] = [6, 0, 0, 0]
        bytes.append(contentsOf: uint32Bytes(UInt32(payload.count)))
        return Data(bytes) + payload
    }

    /// Encodes the client capability response for the Extended Clipboard
    /// pseudo-encoding. The single size entry corresponds to the `text`
    /// format bit and tells the server the largest unsolicited UTF-8 text
    /// payload Naru is willing to receive.
    public static func extendedClipboardCaps(
        textMaximumBytes: UInt32 = 20 * 1024 * 1024
    ) throws -> Data {
        let flags: RFBExtendedClipboardFlags = [
            .text,
            .caps,
            .request,
            .notify,
            .provide
        ]
        var body = Data(uint32Bytes(flags.rawValue))
        body.append(contentsOf: uint32Bytes(textMaximumBytes))
        return try extendedClientCutText(body: body)
    }

    /// Encodes a UTF-8 text clipboard update using the Extended Clipboard
    /// `provide` action. This is the VNC path required for Korean/CJK/emoji
    /// text on servers that confirmed support through a caps message.
    public static func extendedClipboardProvideText(_ text: String) throws -> Data {
        var textPayload = Data(extendedClipboardTextPayload(for: text).utf8)
        textPayload.append(0)

        var uncompressed = Data(uint32Bytes(UInt32(textPayload.count)))
        uncompressed.append(textPayload)
        let compressed = try RFBZlibDeflate.deflateZlibWrapped([UInt8](uncompressed))

        var body = Data(uint32Bytes((RFBExtendedClipboardFlags.text.union(.provide)).rawValue))
        body.append(contentsOf: compressed)
        return try extendedClientCutText(body: body)
    }

    /// Encodes a `SetEncodings` message (RFC 6143 §7.5.2, message
    /// type 2): advertises the encodings Naru supports in
    /// server-honored preference order (spec 004 FR-001).
    ///
    /// Wire layout:
    ///   - 1 byte:  message type (always 2)
    ///   - 1 byte:  padding (0)
    ///   - 2 bytes: number-of-encodings (big-endian)
    ///   - 4 bytes × N: encoding types (signed s32, big-endian)
    public static func setEncodings(_ encodings: [Int32]) -> Data {
        let count = min(encodings.count, Int(UInt16.max))
        var bytes: [UInt8] = [2, 0]
        bytes.append(contentsOf: uint16Bytes(UInt16(count)))
        for encoding in encodings.prefix(count) {
            bytes.append(contentsOf: uint32Bytes(UInt32(bitPattern: encoding)))
        }
        return Data(bytes)
    }

    /// Encodes a `SetPixelFormat` message (RFC 6143 §7.5.1, message
    /// type 0). Naru keeps 32-bit true-colour, so this only ever
    /// re-asserts the format Naru already decodes (spec 004 D2 / FR-014).
    ///
    /// Wire layout (20 bytes):
    ///   - 1 byte:  message type (always 0)
    ///   - 3 bytes: padding (0)
    ///   - 16 bytes: PIXEL_FORMAT
    ///       bpp, depth, big-endian-flag, true-colour-flag,
    ///       r-max u16, g-max u16, b-max u16,
    ///       r-shift, g-shift, b-shift, 3 bytes padding
    public static func setPixelFormat(_ format: RFBPixelFormat) -> Data {
        var bytes: [UInt8] = [0, 0, 0, 0]
        bytes.append(format.bitsPerPixel)
        bytes.append(format.depth)
        bytes.append(format.isBigEndian ? 1 : 0)
        bytes.append(format.isTrueColor ? 1 : 0)
        bytes.append(contentsOf: uint16Bytes(format.redMax))
        bytes.append(contentsOf: uint16Bytes(format.greenMax))
        bytes.append(contentsOf: uint16Bytes(format.blueMax))
        bytes.append(format.redShift)
        bytes.append(format.greenShift)
        bytes.append(format.blueShift)
        bytes.append(contentsOf: [0, 0, 0])
        return Data(bytes)
    }

    /// Encodes TigerVNC's `EnableContinuousUpdates` client message
    /// (message type 150): one enable byte plus the requested framebuffer
    /// rectangle. Callers must only send this after the server has
    /// confirmed support via the ContinuousUpdates pseudo-encoding path.
    public static func enableContinuousUpdates(
        _ enable: Bool,
        x: UInt16,
        y: UInt16,
        width: UInt16,
        height: UInt16
    ) -> Data {
        var bytes: [UInt8] = [150, enable ? 1 : 0]
        bytes.append(contentsOf: uint16Bytes(x))
        bytes.append(contentsOf: uint16Bytes(y))
        bytes.append(contentsOf: uint16Bytes(width))
        bytes.append(contentsOf: uint16Bytes(height))
        return Data(bytes)
    }

    /// Encodes TigerVNC's `ClientFence` message (message type 248).
    /// Payload length is capped at 64 bytes by the extension; only the
    /// published flags are accepted so malformed pacing probes never hit
    /// the wire.
    public static func fence(flags: RFBFenceFlags, payload: Data = Data()) throws -> Data {
        guard flags.rawValue & ~RFBFenceFlags.supported.rawValue == 0 else {
            throw RFBClientMessageEncodingError.unsupportedFenceFlags(flags.rawValue)
        }
        guard payload.count <= maxFencePayloadLength else {
            throw RFBClientMessageEncodingError.fencePayloadTooLarge(
                maximum: maxFencePayloadLength,
                actual: payload.count
            )
        }

        var bytes: [UInt8] = [248, 0, 0, 0]
        bytes.append(contentsOf: uint32Bytes(flags.rawValue))
        bytes.append(UInt8(payload.count))
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    public static func pasteCommand(_ command: PasteCommand) -> Data {
        let modifier: UInt32 = switch command {
        case .commandV:
            // The remote Command key. macOS Screen Sharing (screensharingd)
            // maps Meta_L (0xFFE7) to ⌘ — this matches the keysym the Direct
            // Keystroke / Mac session-control paths already send for Command
            // (KeysymMapping R-4: keyboardLeftGUI → Meta_L; MacSessionControl
            // Cmd-Tab → Meta_L). The earlier Alt_L choice (spec 001 research
            // Decision 2a) mapped to Option on current macOS, so ⌘V never
            // fired and Compose & Send pasted nothing while plain typing
            // worked — fixed to share the one proven Command keysym.
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
        fixedLengthData(byteCount: 8) { bytes in
            bytes[0] = 4
            bytes[1] = isDown ? 1 : 0
            bytes[2] = 0
            bytes[3] = 0
            bytes[4] = UInt8((keysym >> 24) & 0x000000ff)
            bytes[5] = UInt8((keysym >> 16) & 0x000000ff)
            bytes[6] = UInt8((keysym >> 8) & 0x000000ff)
            bytes[7] = UInt8(keysym & 0x000000ff)
        }
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
        fixedLengthData(byteCount: 6) { bytes in
            bytes[0] = 5
            bytes[1] = buttonMask
            bytes[2] = UInt8((x >> 8) & 0x00ff)
            bytes[3] = UInt8(x & 0x00ff)
            bytes[4] = UInt8((y >> 8) & 0x00ff)
            bytes[5] = UInt8(y & 0x00ff)
        }
    }

    @inline(__always)
    private static func fixedLengthData(
        byteCount: Int,
        _ fill: (UnsafeMutableBufferPointer<UInt8>) -> Void
    ) -> Data {
        var data = Data(count: byteCount)
        data.withUnsafeMutableBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            fill(bytes)
        }
        return data
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

    private static func extendedClientCutText(body: Data) throws -> Data {
        guard body.count <= Int(Int32.max) else {
            throw RFBClientMessageEncodingError.extendedClipboardPayloadTooLarge(
                maximum: Int(Int32.max),
                actual: body.count
            )
        }

        let signedLength = Int32(-body.count)
        var bytes: [UInt8] = [6, 0, 0, 0]
        bytes.append(contentsOf: uint32Bytes(UInt32(bitPattern: signedLength)))
        return Data(bytes) + body
    }

    private static func extendedClipboardTextPayload(for text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
    }
}

private enum RFBZlibDeflate {
    private static let outputChunkSize = 64 * 1024

    static func deflateZlibWrapped(_ input: [UInt8]) throws -> [UInt8] {
        let rawDeflate = try deflateRaw(input)
        var wrapped: [UInt8] = [0x78, 0x9c]
        wrapped.append(contentsOf: rawDeflate)
        wrapped.append(contentsOf: adler32Bytes(for: input))
        return wrapped
    }

    private static func deflateRaw(_ input: [UInt8]) throws -> [UInt8] {
        guard !input.isEmpty else {
            return []
        }

        // Apple's `COMPRESSION_ZLIB` encoder emits raw DEFLATE bytes here.
        // Extended Clipboard needs an RFC 1950 zlib wrapper, so the caller
        // adds exactly one header/trailer around this payload.
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        var initialized = false
        defer {
            if initialized {
                compression_stream_destroy(stream)
            }
            stream.deallocate()
        }

        guard compression_stream_init(stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw RFBClientMessageEncodingError.zlibCompressionFailed
        }
        initialized = true

        var output: [UInt8] = []
        var failure = false
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: outputChunkSize)
        defer { destination.deallocate() }

        input.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else {
                return
            }
            stream.pointee.src_ptr = baseAddress
            stream.pointee.src_size = source.count

            while true {
                stream.pointee.dst_ptr = destination
                stream.pointee.dst_size = outputChunkSize
                let status = compression_stream_process(
                    stream,
                    Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                )
                let produced = outputChunkSize - stream.pointee.dst_size
                if produced > 0 {
                    output.append(contentsOf: UnsafeBufferPointer(start: destination, count: produced))
                }

                switch status {
                case COMPRESSION_STATUS_OK:
                    continue
                case COMPRESSION_STATUS_END:
                    return
                default:
                    failure = true
                    return
                }
            }
        }

        if failure {
            throw RFBClientMessageEncodingError.zlibCompressionFailed
        }
        return output
    }

    private static func adler32Bytes(for input: [UInt8]) -> [UInt8] {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in input {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        let checksum = (b << 16) | a
        return [
            UInt8((checksum >> 24) & 0xff),
            UInt8((checksum >> 16) & 0xff),
            UInt8((checksum >> 8) & 0xff),
            UInt8(checksum & 0xff)
        ]
    }
}
