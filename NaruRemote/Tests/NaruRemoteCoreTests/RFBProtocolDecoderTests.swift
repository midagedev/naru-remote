import Foundation
import XCTest
@testable import NaruRemoteCore

final class RFBProtocolDecoderTests: XCTestCase {
    func testDecodesNoAuthFixtureHandshakeAndFirstFrameHeader() throws {
        let transcript = try Self.loadHexFixture("noauth-first-frame")

        let version = try RFBProtocolDecoder.parseVersion(transcript[safe: 0..<12])
        let securityTypes = try RFBProtocolDecoder.parseSecurityTypes(transcript[safe: 12..<14])
        let securityResult = transcript[safe: 14..<18]
        let serverInit = try RFBProtocolDecoder.parseServerInit(transcript[safe: 18..<46])
        let framebufferUpdate = try RFBProtocolDecoder.parseFramebufferUpdateHeader(transcript[safe: 46..<62])

        try RFBProtocolDecoder.parseSecurityResult(securityResult)

        XCTAssertEqual(version, RFBProtocolVersion(major: 3, minor: 8))
        XCTAssertTrue(securityTypes.supportsNone)
        XCTAssertEqual(serverInit.width, 1024)
        XCTAssertEqual(serverInit.height, 768)
        XCTAssertEqual(serverInit.name, "Desk")
        XCTAssertEqual(serverInit.pixelFormat.bitsPerPixel, 32)
        XCTAssertEqual(framebufferUpdate.rectangles.count, 1)
        XCTAssertEqual(serverInit.frameMetadata().width, 1024)
        XCTAssertEqual(serverInit.frameMetadata().height, 768)
        XCTAssertEqual(framebufferUpdate.firstUpdatedRectangle?.width, 1024)
        XCTAssertEqual(framebufferUpdate.firstUpdatedRectangle?.height, 768)
    }

    func testFramebufferMetadataUsesServerInitSizeNotDirtyRectangleSize() throws {
        let updateWithDirtyRectangle = Data([
            0, 0, 0, 1,
            0, 10, 0, 20, 0, 30, 0, 40,
            0, 0, 0, 0
        ])
        let serverInit = RFBServerInit(
            width: 1024,
            height: 768,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: "Desk"
        )

        let framebufferUpdate = try RFBProtocolDecoder.parseFramebufferUpdateHeader(updateWithDirtyRectangle)

        XCTAssertEqual(framebufferUpdate.firstUpdatedRectangle?.width, 30)
        XCTAssertEqual(framebufferUpdate.firstUpdatedRectangle?.height, 40)
        XCTAssertEqual(serverInit.frameMetadata().width, 1024)
        XCTAssertEqual(serverInit.frameMetadata().height, 768)
    }

    func testRejectsFailedSecurityResult() {
        let failedSecurityResult = Data([0, 0, 0, 1])

        XCTAssertThrowsError(try RFBProtocolDecoder.parseSecurityResult(failedSecurityResult)) { error in
            XCTAssertEqual(error as? RFBProtocolDecoderError, .securityFailed(1))
        }
    }

    func testParsesServerCutTextWithCJKAndEmojiUTF8RoundTrip() throws {
        let payload = "안녕 클립보드 🚀"
        let payloadBytes = Data(payload.utf8)

        var message = Data([3, 0, 0, 0])
        message.append(contentsOf: Self.uint32Bytes(UInt32(payloadBytes.count)))
        message.append(payloadBytes)

        let decoded = try RFBProtocolDecoder.parseServerCutText(message)
        XCTAssertEqual(decoded, payload)
    }

    func testParsesEmptyServerCutTextPayload() throws {
        let message = Data([3, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(try RFBProtocolDecoder.parseServerCutText(message), "")
    }

    func testRejectsTruncatedServerCutTextPayloadWithTypedError() {
        // Header declares a 19-byte payload but only 5 payload bytes are present.
        var message = Data([3, 0, 0, 0])
        message.append(contentsOf: Self.uint32Bytes(19))
        message.append(Data([0xec, 0x95, 0x88, 0xeb, 0x85])) // first 5 bytes of "안녕"

        XCTAssertThrowsError(try RFBProtocolDecoder.parseServerCutText(message)) { error in
            XCTAssertEqual(
                error as? RFBProtocolDecoderError,
                .truncatedServerCutText(expected: 27, actual: 13)
            )
        }
    }

    func testRejectsServerCutTextWithWrongMessageType() {
        var message = Data([0, 0, 0, 0])
        message.append(contentsOf: Self.uint32Bytes(0))

        XCTAssertThrowsError(try RFBProtocolDecoder.parseServerCutText(message)) { error in
            XCTAssertEqual(error as? RFBProtocolDecoderError, .unexpectedMessageType(0))
        }
    }

    func testRejectsServerCutTextWithInvalidUTF8() {
        var message = Data([3, 0, 0, 0])
        message.append(contentsOf: Self.uint32Bytes(2))
        message.append(Data([0xC0, 0xC1])) // overlong / invalid UTF-8 lead bytes

        XCTAssertThrowsError(try RFBProtocolDecoder.parseServerCutText(message)) { error in
            XCTAssertEqual(error as? RFBProtocolDecoderError, .invalidServerCutTextEncoding)
        }
    }

    private static func uint32Bytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }

    private static func loadHexFixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            root.deleteLastPathComponent()
        }

        let fixtureURL = root
            .appendingPathComponent("TestFixtures/FakeRFBServer/Fixtures")
            .appendingPathComponent("\(name).hex")
        let text = try String(contentsOf: fixtureURL, encoding: .utf8)
        let hexPairs = text
            .split(whereSeparator: \.isNewline)
            .flatMap { line -> [Substring] in
                let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                return content.split(whereSeparator: \.isWhitespace)
            }

        return Data(try hexPairs.map { pair in
            guard let byte = UInt8(pair, radix: 16) else {
                throw FixtureError.invalidHexByte(String(pair))
            }
            return byte
        })
    }
}

private enum FixtureError: Error, Equatable {
    case invalidHexByte(String)
}

private extension Data {
    subscript(safe range: Range<Int>) -> Data {
        precondition(range.lowerBound >= 0)
        precondition(range.upperBound <= count)

        return subdata(in: range)
    }
}
