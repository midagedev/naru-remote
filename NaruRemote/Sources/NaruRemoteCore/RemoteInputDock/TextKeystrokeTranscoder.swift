import Foundation

/// Converts committed Compose text into a sequence of logical key events.
///
/// This is a probe/foundation type for a future Compose text key-event route.
/// It deliberately does not toggle remote IME state, decompose Hangul into
/// jamo, or infer a remote keyboard layout. Non-ASCII scalar support uses the
/// X11 Unicode keysym convention: `0x01000000 | unicodeScalar`.
public enum TextKeystrokeTranscoder {
    public static let unicodeKeysymPrefix: UInt32 = 0x0100_0000

    public static func transcode(_ text: String) -> TextKeystrokeTranscodingResult {
        guard !text.isEmpty else {
            return TextKeystrokeTranscodingResult(
                events: [],
                payloadEncoding: .ascii,
                usesUnicodeKeysyms: false,
                failureCode: .emptyText
            )
        }

        var events: [TextKeystrokeEvent] = []
        var usesUnicodeKeysyms = false
        let scalars = Array(text.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x0D {
                if index + 1 < scalars.count, scalars[index + 1].value == 0x0A {
                    index += 1
                }
                events.append(TextKeystrokeEvent(keysym: KeysymMapping.keysym(for: .return)))
            } else if let keysym = keysym(for: scalar) {
                if keysym >= unicodeKeysymPrefix {
                    usesUnicodeKeysyms = true
                }
                events.append(TextKeystrokeEvent(keysym: keysym))
            } else {
                return TextKeystrokeTranscodingResult(
                    events: [],
                    payloadEncoding: TextInjectionPayloadEncoding.classify(text),
                    usesUnicodeKeysyms: usesUnicodeKeysyms,
                    failureCode: .unsupportedControlScalar
                )
            }
            index += 1
        }

        return TextKeystrokeTranscodingResult(
            events: events,
            payloadEncoding: TextInjectionPayloadEncoding.classify(text),
            usesUnicodeKeysyms: usesUnicodeKeysyms,
            failureCode: nil
        )
    }

    public static func keysym(for scalar: UnicodeScalar) -> UInt32? {
        switch scalar.value {
        case 0x09:
            return KeysymMapping.keysym(for: .tab)
        case 0x0A, 0x0D:
            return KeysymMapping.keysym(for: .return)
        case 0x20 ... 0x7E:
            return scalar.value
        case 0xA0 ... 0xFF:
            return scalar.value
        case 0x0100 ... 0x10FFFF:
            return unicodeKeysymPrefix | scalar.value
        default:
            return nil
        }
    }
}

public struct TextKeystrokeTranscodingResult: Equatable, Sendable {
    public let events: [TextKeystrokeEvent]
    public let payloadEncoding: TextInjectionPayloadEncoding
    public let usesUnicodeKeysyms: Bool
    public let failureCode: TextKeystrokeTranscodingFailureCode?

    public var canEmit: Bool {
        failureCode == nil
    }
}

public struct TextKeystrokeEvent: Equatable, Sendable {
    public let keysym: UInt32

    public init(keysym: UInt32) {
        self.keysym = keysym
    }
}

public enum TextKeystrokeTranscodingFailureCode: String, Equatable, Sendable {
    case emptyText
    case unsupportedControlScalar
}
