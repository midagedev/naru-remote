import XCTest
@testable import NaruRemoteCore

final class TextKeystrokeTranscoderTests: XCTestCase {
    func testTranscodesASCIIToPlainKeysyms() {
        let result = TextKeystrokeTranscoder.transcode("Az 9")

        XCTAssertTrue(result.canEmit)
        XCTAssertEqual(result.payloadEncoding, .ascii)
        XCTAssertFalse(result.usesUnicodeKeysyms)
        XCTAssertEqual(
            result.events.map(\.keysym),
            [0x41, 0x7A, 0x20, 0x39]
        )
    }

    func testTranscodesCommittedHangulSyllablesAsX11UnicodeKeysyms() {
        let result = TextKeystrokeTranscoder.transcode("한글")

        XCTAssertTrue(result.canEmit)
        XCTAssertEqual(result.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertTrue(result.usesUnicodeKeysyms)
        XCTAssertEqual(
            result.events.map(\.keysym),
            [0x0100_D55C, 0x0100_AE00]
        )
    }

    func testTranscodesTabAndNewlinesToNamedKeysyms() {
        let result = TextKeystrokeTranscoder.transcode("a\tb\r\nc\n")

        XCTAssertTrue(result.canEmit)
        XCTAssertEqual(
            result.events.map(\.keysym),
            [
                0x61,
                KeysymMapping.keysym(for: .tab),
                0x62,
                KeysymMapping.keysym(for: .return),
                0x63,
                KeysymMapping.keysym(for: .return),
            ]
        )
    }

    func testRejectsEmptyTextAndUnsupportedControls() {
        let empty = TextKeystrokeTranscoder.transcode("")
        XCTAssertFalse(empty.canEmit)
        XCTAssertEqual(empty.failureCode, .emptyText)

        let unsupported = TextKeystrokeTranscoder.transcode("a\u{0000}b")
        XCTAssertFalse(unsupported.canEmit)
        XCTAssertEqual(unsupported.failureCode, .unsupportedControlScalar)
        XCTAssertEqual(unsupported.events.map(\.keysym), [])
    }

    func testUnicodeKeysymMappingFollowsX11OffsetRule() {
        XCTAssertEqual(
            TextKeystrokeTranscoder.keysym(for: UnicodeScalar(0x0100)!),
            0x0100_0100
        )
        XCTAssertEqual(
            TextKeystrokeTranscoder.keysym(for: UnicodeScalar(0x1F642)!),
            0x0101_F642
        )
    }
}
