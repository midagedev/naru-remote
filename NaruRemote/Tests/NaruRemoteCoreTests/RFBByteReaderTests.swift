import Foundation
import XCTest
@testable import NaruRemoteCore

final class RFBByteReaderTests: XCTestCase {
    func testReadsBytesAndAdvancesCursor() throws {
        let reader = RFBDataReader([0x01, 0x02, 0x03, 0x04, 0x05])
        XCTAssertEqual(reader.offset, 0)
        XCTAssertEqual(reader.remaining, 5)

        XCTAssertEqual(try reader.readBytes(2), [0x01, 0x02])
        XCTAssertEqual(reader.offset, 2)
        XCTAssertEqual(reader.remaining, 3)

        XCTAssertEqual(try reader.readBytes(3), [0x03, 0x04, 0x05])
        XCTAssertEqual(reader.remaining, 0)
    }

    func testReadsDataAndAdvancesCursor() throws {
        let reader = RFBDataReader(Data([0x10, 0x20, 0x30, 0x40]))
        XCTAssertEqual(try reader.readData(3), Data([0x10, 0x20, 0x30]))
        XCTAssertEqual(reader.offset, 3)
        XCTAssertEqual(reader.remaining, 1)
        XCTAssertEqual(try reader.readBytes(1), [0x40])
    }

    func testZeroLengthReadReturnsEmptyWithoutAdvancing() throws {
        let reader = RFBDataReader([0xAA])
        XCTAssertEqual(try reader.readBytes(0), [])
        XCTAssertEqual(reader.offset, 0)
    }

    func testReadsBigEndianIntegers() throws {
        let reader = RFBDataReader([
            0xAB,                   // u8
            0x12, 0x34,             // u16
            0x01, 0x02, 0x03, 0x04  // u32
        ])
        XCTAssertEqual(try reader.readUInt8(), 0xAB)
        XCTAssertEqual(try reader.readUInt16(), 0x1234)
        XCTAssertEqual(try reader.readUInt32(), 0x0102_0304)
    }

    func testReadsSignedInt32BigEndianForPseudoEncodings() throws {
        // 0xFFFFFF21 == -223 == RFBEncoding.desktopSize.
        let reader = RFBDataReader([0xFF, 0xFF, 0xFF, 0x21])
        XCTAssertEqual(try reader.readInt32(), RFBEncoding.desktopSize)
        XCTAssertEqual(RFBEncoding.desktopSize, -223)
    }

    func testSkipAdvancesCursor() throws {
        let reader = RFBDataReader([0x00, 0x00, 0x00, 0x99])
        try reader.skip(3)
        XCTAssertEqual(try reader.readUInt8(), 0x99)
    }

    func testInsufficientDataThrowsTypedError() throws {
        let reader = RFBDataReader([0x01, 0x02])
        XCTAssertThrowsError(try reader.readBytes(3)) { error in
            XCTAssertEqual(
                error as? RFBByteReaderError,
                .insufficientData(requested: 3, available: 2)
            )
        }
    }

    func testNegativeRequestThrowsTypedError() throws {
        let reader = RFBDataReader([0x01])
        XCTAssertThrowsError(try reader.readBytes(-1)) { error in
            XCTAssertEqual(error as? RFBByteReaderError, .negativeRequest(-1))
        }
    }
}
