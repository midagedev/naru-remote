import Foundation
import XCTest
@testable import NaruRemoteCore

final class RFBRawFramebufferDecoderTests: XCTestCase {
    func testDecodesLittleEndianThirtyTwoBitRawRectangleIntoRGBAFramebuffer() throws {
        let framebuffer = try RFBRawFramebufferDecoder.decode(
            updateData: Self.rawTwoByTwoUpdateData(),
            serverInit: Self.serverInit(width: 2, height: 2)
        )

        XCTAssertEqual(framebuffer.width, 2)
        XCTAssertEqual(framebuffer.height, 2)
        XCTAssertEqual(framebuffer[0, 0], RFBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(framebuffer[1, 0], RFBColor(red: 0, green: 255, blue: 0))
        XCTAssertEqual(framebuffer[0, 1], RFBColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(framebuffer[1, 1], RFBColor(red: 255, green: 255, blue: 255))
    }

    func testAppliesIncrementalRawRectangleOntoPreviousFramebuffer() throws {
        let previousFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 2,
            fill: RFBColor(red: 255, green: 0, blue: 0)
        )
        let capturedAt = Date(timeIntervalSince1970: 100)

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Self.singleBluePixelUpdateData(x: 1, y: 0),
            serverInit: Self.serverInit(width: 2, height: 2),
            previousFramebuffer: previousFramebuffer,
            capturedAt: capturedAt
        )

        XCTAssertEqual(result.framebuffer[0, 0], RFBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(result.framebuffer[1, 0], RFBColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(result.framebuffer[0, 1], RFBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(result.framebuffer[1, 1], RFBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(result.dirtyRectangles, [
            RFBFrameDamageRect(x: 1, y: 0, width: 1, height: 1)
        ])
        XCTAssertEqual(result.changedPixelCount, 1)
        XCTAssertEqual(result.capturedAt, capturedAt)
    }

    func testRejectsPreviousFramebufferSizeMismatch() throws {
        let previousFramebuffer = RFBRawFramebuffer(width: 3, height: 2)

        XCTAssertThrowsError(
            try RFBRawFramebufferDecoder.apply(
                updateData: Self.singleBluePixelUpdateData(x: 1, y: 0),
                serverInit: Self.serverInit(width: 2, height: 2),
                previousFramebuffer: previousFramebuffer
            )
        ) { error in
            XCTAssertEqual(
                error as? RFBRawFramebufferDecoderError,
                .framebufferSizeMismatch(
                    expectedWidth: 2,
                    expectedHeight: 2,
                    actualWidth: 3,
                    actualHeight: 2
                )
            )
        }
    }

    func testClassifiesFrameChangeActivityByChangedPixelRatio() {
        let framebuffer = RFBRawFramebuffer(width: 100, height: 100)

        XCTAssertEqual(
            RFBFramebufferUpdateResult(
                framebuffer: framebuffer,
                dirtyRectangles: [],
                changedPixelCount: 0
            ).changeActivity,
            .idle
        )
        XCTAssertEqual(
            RFBFramebufferUpdateResult(
                framebuffer: framebuffer,
                dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 10, height: 10)],
                changedPixelCount: 100
            ).changeActivity,
            .idle
        )
        XCTAssertEqual(
            RFBFramebufferUpdateResult(
                framebuffer: framebuffer,
                dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 30, height: 30)],
                changedPixelCount: 1_000
            ).changeActivity,
            .moderate
        )
        XCTAssertEqual(
            RFBFramebufferUpdateResult(
                framebuffer: framebuffer,
                dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 70, height: 70)],
                changedPixelCount: 3_000
            ).changeActivity,
            .high
        )
    }

    func testRejectsUnsupportedFramebufferEncoding() throws {
        // Encoding 2 (RRE) is not implemented; encodings 5 (Hextile) and
        // 1 (CopyRect) are now supported (spec 004), so this uses an
        // encoding Naru genuinely cannot decode.
        let updateData = Data([
            0, 0, 0, 1,
            0, 0, 0, 0, 0, 1, 0, 1,
            0, 0, 0, 2
        ])

        XCTAssertThrowsError(
            try RFBRawFramebufferDecoder.decode(
                updateData: updateData,
                serverInit: Self.serverInit(width: 1, height: 1)
            )
        ) { error in
            XCTAssertEqual(error as? RFBRawFramebufferDecoderError, .unsupportedEncoding(2))
        }
    }

    func testRejectsOutOfBoundsRectangle() throws {
        let updateData = Data([
            0, 0, 0, 1,
            0, 1, 0, 1, 0, 2, 0, 2,
            0, 0, 0, 0
        ])

        XCTAssertThrowsError(
            try RFBRawFramebufferDecoder.decode(
                updateData: updateData,
                serverInit: Self.serverInit(width: 2, height: 2)
            )
        ) { error in
            XCTAssertEqual(error as? RFBRawFramebufferDecoderError, .rectangleOutOfBounds)
        }
    }

    func testRejectsIncompleteRawPixelPayload() throws {
        // A 2x2 raw rectangle needs 16 pixel bytes but only 4 are
        // present. The incremental reader surfaces a typed
        // RFBByteReaderError (spec 004 FR-002 / SP-006) — no trap, no
        // out-of-bounds read.
        let updateData = Data([
            0, 0, 0, 1,
            0, 0, 0, 0, 0, 2, 0, 2,
            0, 0, 0, 0,
            0, 0, 255, 0
        ])

        XCTAssertThrowsError(
            try RFBRawFramebufferDecoder.decode(
                updateData: updateData,
                serverInit: Self.serverInit(width: 2, height: 2)
            )
        ) { error in
            XCTAssertEqual(
                error as? RFBByteReaderError,
                .insufficientData(requested: 16, available: 4)
            )
        }
    }

    private static func rawTwoByTwoUpdateData() -> Data {
        Data([
            0, 0, 0, 1,
            0, 0, 0, 0, 0, 2, 0, 2,
            0, 0, 0, 0,
            0, 0, 255, 0,
            0, 255, 0, 0,
            255, 0, 0, 0,
            255, 255, 255, 0
        ])
    }

    private static func singleBluePixelUpdateData(x: UInt16, y: UInt16) -> Data {
        Data([
            0, 0, 0, 1,
            UInt8(x >> 8), UInt8(x & 0x00ff),
            UInt8(y >> 8), UInt8(y & 0x00ff),
            0, 1,
            0, 1,
            0, 0, 0, 0,
            255, 0, 0, 0
        ])
    }

    private static func serverInit(width: Int, height: Int) -> RFBServerInit {
        RFBServerInit(
            width: width,
            height: height,
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
            name: "Test"
        )
    }
}
