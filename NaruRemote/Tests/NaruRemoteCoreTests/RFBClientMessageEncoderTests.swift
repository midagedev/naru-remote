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
}
