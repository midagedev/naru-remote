import Foundation
import XCTest
@testable import NaruRemoteCore

/// FAIL-first contracts for the untrusted RFB length fields that the
/// 2026-08-17 code audit found were allocated without a cap (P1-1,
/// P1-2, P1-3).
final class RFBUntrustedAllocationLimitTests: XCTestCase {
    func testParseServerInitRejectsDesktopNameLongerThan64KiB() {
        var prefix = Data(count: 24)
        prefix.replaceSubrange(20..<24, with: Self.uint32Bytes(UInt32(RFBProtocolDecoder.maxDesktopNameLength + 1)))

        XCTAssertThrowsError(try RFBProtocolDecoder.parseServerInit(prefix)) { error in
            XCTAssertEqual(
                error as? RFBProtocolDecoderError,
                .desktopNameTooLong(
                    maximum: RFBProtocolDecoder.maxDesktopNameLength,
                    actual: RFBProtocolDecoder.maxDesktopNameLength + 1
                )
            )
        }
    }

    func testParseServerInitAcceptsDesktopNameAt64KiBLimit() throws {
        var data = Data(count: 24)
        data.replaceSubrange(20..<24, with: Self.uint32Bytes(UInt32(RFBProtocolDecoder.maxDesktopNameLength)))
        data.append(Data(repeating: 0x41, count: RFBProtocolDecoder.maxDesktopNameLength))

        let serverInit = try RFBProtocolDecoder.parseServerInit(data)
        XCTAssertEqual(serverInit.name.count, RFBProtocolDecoder.maxDesktopNameLength)
    }

    func testParseServerCutTextRejectsPayloadLongerThan4MiBWithoutRequiringTheBytes() {
        var header = Data([3, 0, 0, 0])
        header.append(contentsOf: Self.uint32Bytes(UInt32(RFBProtocolDecoder.maxServerCutTextPayloadLength + 1)))

        XCTAssertThrowsError(try RFBProtocolDecoder.parseServerCutText(header)) { error in
            XCTAssertEqual(
                error as? RFBProtocolDecoderError,
                .serverCutTextPayloadTooLarge(
                    maximum: RFBProtocolDecoder.maxServerCutTextPayloadLength,
                    actual: RFBProtocolDecoder.maxServerCutTextPayloadLength + 1
                )
            )
        }
    }

    func testParseServerCutTextStillRejectsInt32MinLength() {
        var header = Data([3, 0, 0, 0])
        header.append(contentsOf: Self.uint32Bytes(UInt32(bitPattern: Int32.min)))

        XCTAssertThrowsError(try RFBProtocolDecoder.parseServerCutText(header)) { error in
            XCTAssertEqual(
                error as? RFBProtocolDecoderError,
                .malformedExtendedServerCutText
            )
        }
    }

    func testConsumeServerCutTextSkipsOversizedPayloadThenParsesTheNextMessage() throws {
        let oversizedLength = RFBProtocolDecoder.maxServerCutTextPayloadLength + 1
        var oversizedHeader = Data([3, 0, 0, 0])
        oversizedHeader.append(contentsOf: Self.uint32Bytes(UInt32(oversizedLength)))

        let nextPayload = Data("ok".utf8)
        var nextMessage = Data([3, 0, 0, 0])
        nextMessage.append(contentsOf: Self.uint32Bytes(UInt32(nextPayload.count)))
        nextMessage.append(nextPayload)

        let reader = ChunkRecordingByteReader(
            prefix: oversizedHeader,
            fabricatedByteCount: oversizedLength,
            suffix: nextMessage
        )

        let first = try RFBProtocolDecoder.consumeServerCutText(from: reader)
        guard case .ignoredOversizedPayload = first else {
            XCTFail("expected oversized CutText to be skipped, got \(intakeSummary(first))")
            return
        }
        XCTAssertLessThanOrEqual(reader.maxReadSize, RFBProtocolDecoder.untrustedPayloadSkipChunkSize)
        XCTAssertGreaterThan(reader.readSizes.count, 1)

        let second = try RFBProtocolDecoder.consumeServerCutText(from: reader)
        XCTAssertEqual(second, .message(.legacyText("ok")))
    }

    func testConsumeServerCutTextAfterTypeByteSkipsOversizedExtendedPayload() throws {
        let oversizedLength = RFBProtocolDecoder.maxServerCutTextPayloadLength + 1
        let signed = Int32(-oversizedLength)
        var remainder = Data([0, 0, 0])
        remainder.append(contentsOf: Self.uint32Bytes(UInt32(bitPattern: signed)))

        let reader = ChunkRecordingByteReader(
            prefix: remainder,
            fabricatedByteCount: oversizedLength,
            suffix: Data()
        )

        let intake = try RFBProtocolDecoder.consumeServerCutTextAfterTypeByte(from: reader)
        XCTAssertEqual(intake, .ignoredOversizedPayload)
        XCTAssertLessThanOrEqual(reader.maxReadSize, RFBProtocolDecoder.untrustedPayloadSkipChunkSize)
        XCTAssertEqual(reader.remainingFabricatedByteCount, 0)
    }

    func testExtendedClipboardInflateRejectsOutputLargerThan4MiB() throws {
        let textByteCount = RFBProtocolDecoder.maxExtendedClipboardInflateLength
        let message = Self.serverCutTextMessage(
            fromClientCutText: try RFBClientMessageEncoder.extendedClipboardProvideText(
                String(repeating: "A", count: textByteCount)
            )
        )

        XCTAssertThrowsError(try RFBProtocolDecoder.parseServerCutTextMessage(message)) { error in
            XCTAssertEqual(
                error as? RFBProtocolDecoderError,
                .malformedExtendedServerCutText
            )
        }
    }

    private func intakeSummary(_ intake: RFBServerCutTextIntake) -> String {
        switch intake {
        case .ignoredOversizedPayload:
            return "ignoredOversizedPayload"
        case .message(.legacyText(let text)):
            return "legacyText(count: \(text.count))"
        case .message(.extendedClipboard(let message)):
            return "extendedClipboard(flags: \(message.flags.rawValue), textCount: \(message.text?.count ?? -1))"
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

    private static func serverCutTextMessage(fromClientCutText message: Data) -> Data {
        var serverMessage = message
        serverMessage[serverMessage.startIndex] = 3
        return serverMessage
    }
}

/// Supplies a small real prefix/suffix and fabricates the hostile
/// payload length so the skip test does not hold a 4 MiB source buffer.
private final class ChunkRecordingByteReader: RFBByteReader {
    private var prefix: Data
    private var fabricatedRemaining: Int
    private var suffix: Data
    private(set) var readSizes: [Int] = []

    init(prefix: Data, fabricatedByteCount: Int, suffix: Data) {
        self.prefix = prefix
        self.fabricatedRemaining = fabricatedByteCount
        self.suffix = suffix
    }

    var maxReadSize: Int { readSizes.max() ?? 0 }
    var remainingFabricatedByteCount: Int { fabricatedRemaining }

    func readBytes(_ count: Int) throws -> [UInt8] {
        Array(try readData(count))
    }

    func readData(_ count: Int) throws -> Data {
        guard count >= 0 else {
            throw RFBByteReaderError.negativeRequest(count)
        }
        guard count > 0 else {
            return Data()
        }
        readSizes.append(count)

        var out = Data()
        out.reserveCapacity(count)

        if !prefix.isEmpty {
            let taken = min(count, prefix.count)
            out.append(prefix.prefix(taken))
            prefix.removeFirst(taken)
        }
        if out.count < count, fabricatedRemaining > 0 {
            let taken = min(count - out.count, fabricatedRemaining)
            out.append(Data(count: taken))
            fabricatedRemaining -= taken
        }
        if out.count < count, !suffix.isEmpty {
            let taken = min(count - out.count, suffix.count)
            out.append(suffix.prefix(taken))
            suffix.removeFirst(taken)
        }
        guard out.count == count else {
            throw RFBByteReaderError.insufficientData(
                requested: count,
                available: out.count
            )
        }
        return out
    }
}
