import Foundation
import XCTest
@testable import NaruRemoteCore

/// Multi-encoding decoder coverage (spec 004 Increment 1): CopyRect,
/// Hextile, the LastRect / DesktopSize pseudo-encodings, mixed updates,
/// and hostile-input robustness. Raw coverage lives in
/// `RFBRawFramebufferDecoderTests`.
final class RFBFramebufferDecoderTests: XCTestCase {
    private let red = RFBColor(red: 255, green: 0, blue: 0)
    private let green = RFBColor(red: 0, green: 255, blue: 0)
    private let blue = RFBColor(red: 0, green: 0, blue: 255)
    private let white = RFBColor(red: 255, green: 255, blue: 255)
    private let black = RFBColor(red: 0, green: 0, blue: 0)

    // MARK: - CopyRect (encoding 1)

    func testCopyRectCopiesSourceRegionToDestination() throws {
        // 4x2: row0 coloured, row1 black. Copy row0 down to row1.
        let previous = try RFBRawFramebufferDecoder.decode(
            updateData: rawUpdate(x: 0, y: 0, width: 4, height: 2, colors: [
                red, green, blue, white,
                black, black, black, black
            ]),
            serverInit: serverInit(width: 4, height: 2)
        )

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: copyRectUpdate(dstX: 0, dstY: 1, width: 4, height: 1, srcX: 0, srcY: 0),
            serverInit: serverInit(width: 4, height: 2),
            previousFramebuffer: previous
        )

        XCTAssertEqual(result.framebuffer[0, 1], red)
        XCTAssertEqual(result.framebuffer[1, 1], green)
        XCTAssertEqual(result.framebuffer[2, 1], blue)
        XCTAssertEqual(result.framebuffer[3, 1], white)
        // Source row untouched.
        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.dirtyRectangles, [RFBFrameDamageRect(x: 0, y: 1, width: 4, height: 1)])
        XCTAssertEqual(result.changedPixelCount, 4)
    }

    func testCopyRectOverlapIsSnapshotSafe() throws {
        // 4x1 = [a,b,c,d]; copy src(0,0,3,1) to dst(1,0). A snapshot-safe
        // copy yields [a,a,b,c]; an in-place left-to-right copy would
        // smear to [a,a,a,a].
        let previous = try RFBRawFramebufferDecoder.decode(
            updateData: rawUpdate(x: 0, y: 0, width: 4, height: 1, colors: [red, green, blue, white]),
            serverInit: serverInit(width: 4, height: 1)
        )

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: copyRectUpdate(dstX: 1, dstY: 0, width: 3, height: 1, srcX: 0, srcY: 0),
            serverInit: serverInit(width: 4, height: 1),
            previousFramebuffer: previous
        )

        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.framebuffer[1, 0], red)
        XCTAssertEqual(result.framebuffer[2, 0], green)
        XCTAssertEqual(result.framebuffer[3, 0], blue)
    }

    func testCopyRectReportsZeroChangedPixelsWhenDestinationAlreadyMatches() throws {
        let previous = try RFBRawFramebufferDecoder.decode(
            updateData: rawUpdate(x: 0, y: 0, width: 2, height: 1, colors: [red, green]),
            serverInit: serverInit(width: 2, height: 1)
        )

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: copyRectUpdate(dstX: 0, dstY: 0, width: 2, height: 1, srcX: 0, srcY: 0),
            serverInit: serverInit(width: 2, height: 1),
            previousFramebuffer: previous
        )

        XCTAssertEqual(result.changedPixelCount, 0)
    }

    func testCopyRectRejectsOutOfBoundsSource() throws {
        let previous = RFBRawFramebuffer(width: 4, height: 1, fill: red)
        XCTAssertThrowsError(
            try RFBRawFramebufferDecoder.apply(
                // src x=2 + width 4 = 6 > framebuffer width 4.
                updateData: copyRectUpdate(dstX: 0, dstY: 0, width: 4, height: 1, srcX: 2, srcY: 0),
                serverInit: serverInit(width: 4, height: 1),
                previousFramebuffer: previous
            )
        ) { error in
            XCTAssertEqual(error as? RFBRawFramebufferDecoderError, .copyRectOutOfBounds)
        }
    }

    func testMixedRawAndCopyRectUpdateAppliesInWireOrder() throws {
        // One FramebufferUpdate with two rectangles: a Raw rect that
        // paints row0, then a CopyRect that copies row0 to row1.
        var bytes = messageHeader(rectangleCount: 2)
        bytes += rectangleHeader(x: 0, y: 0, width: 2, height: 1, encoding: RFBEncoding.raw)
        bytes += pixelBytes(red) + pixelBytes(green)
        bytes += rectangleHeader(x: 0, y: 1, width: 2, height: 1, encoding: RFBEncoding.copyRect)
        bytes += [0, 0, 0, 0] // src (0,0)

        let previous = RFBRawFramebuffer(width: 2, height: 2, fill: black)
        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 2, height: 2),
            previousFramebuffer: previous
        )

        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.framebuffer[1, 0], green)
        XCTAssertEqual(result.framebuffer[0, 1], red)
        XCTAssertEqual(result.framebuffer[1, 1], green)
        XCTAssertEqual(result.dirtyRectangles.count, 2)
    }

    // MARK: - Hextile (encoding 5)

    func testHextileBackgroundColorCarriesAcrossTiles() throws {
        // 32x1 = two horizontal tiles. Tile 0 specifies a red
        // background; tile 1 specifies nothing and MUST reuse it.
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 32, height: 1, encoding: RFBEncoding.hextile)
        bytes += [0x02] + pixelBytes(red) // tile 0: BackgroundSpecified
        bytes += [0x00]                    // tile 1: carry background

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 32, height: 1),
            previousFramebuffer: nil
        )

        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.framebuffer[15, 0], red)
        XCTAssertEqual(result.framebuffer[16, 0], red) // second tile carried red
        XCTAssertEqual(result.framebuffer[31, 0], red)
    }

    func testHextileRawTile() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 2, height: 2, encoding: RFBEncoding.hextile)
        bytes += [0x01] // Raw tile
        bytes += pixelBytes(red) + pixelBytes(green) + pixelBytes(blue) + pixelBytes(white)

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 2, height: 2),
            previousFramebuffer: nil
        )

        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.framebuffer[1, 0], green)
        XCTAssertEqual(result.framebuffer[0, 1], blue)
        XCTAssertEqual(result.framebuffer[1, 1], white)
    }

    func testHextileReportsZeroChangedPixelsWhenFrameIsIdentical() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 2, height: 2, encoding: RFBEncoding.hextile)
        bytes += [0x01] // Raw tile
        bytes += pixelBytes(red) + pixelBytes(green) + pixelBytes(blue) + pixelBytes(white)
        let update = Data(bytes)
        let init2x2 = serverInit(width: 2, height: 2)
        let first = try RFBRawFramebufferDecoder.apply(
            updateData: update,
            serverInit: init2x2
        )

        let second = try RFBRawFramebufferDecoder.apply(
            updateData: update,
            serverInit: init2x2,
            previousFramebuffer: first.framebuffer
        )

        XCTAssertEqual(second.changedPixelCount, 0)
    }

    func testHextileColouredSubrect() throws {
        // 4x4 tile, black background, one red coloured 1x1 subrect at (1,1).
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 4, height: 4, encoding: RFBEncoding.hextile)
        bytes += [UInt8(0x02 | 0x08 | 0x10)] // Background + AnySubrects + SubrectsColoured
        bytes += pixelBytes(black)     // background
        bytes += [1]                   // one subrect
        bytes += pixelBytes(red)       // subrect colour
        bytes += [0x11, 0x00]          // xy=(1,1), wh=(1,1)

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 4, height: 4),
            previousFramebuffer: nil
        )

        XCTAssertEqual(result.framebuffer[1, 1], red)
        XCTAssertEqual(result.framebuffer[0, 0], black)
        XCTAssertEqual(result.framebuffer[3, 3], black)
    }

    func testHextileForegroundSubrectUsesCarriedForeground() throws {
        // 4x4 tile, black background, green foreground, one (not
        // coloured) 2x2 subrect at (2,2) painted with the foreground.
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 4, height: 4, encoding: RFBEncoding.hextile)
        bytes += [UInt8(0x02 | 0x04 | 0x08)] // Background + Foreground + AnySubrects
        bytes += pixelBytes(black)     // background
        bytes += pixelBytes(green)     // foreground
        bytes += [1]                   // one subrect
        bytes += [0x22, 0x11]          // xy=(2,2), wh=(2,2)

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 4, height: 4),
            previousFramebuffer: nil
        )

        XCTAssertEqual(result.framebuffer[2, 2], green)
        XCTAssertEqual(result.framebuffer[3, 3], green)
        XCTAssertEqual(result.framebuffer[0, 0], black)
        XCTAssertEqual(result.framebuffer[1, 1], black)
    }

    func testHextileRejectsSubrectOutsideTile() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 4, height: 4, encoding: RFBEncoding.hextile)
        bytes += [UInt8(0x02 | 0x08 | 0x10)]
        bytes += pixelBytes(black)
        bytes += [1]
        bytes += pixelBytes(red)
        bytes += [0x33, 0x11] // xy=(3,3) + wh=(2,2) → spills past the 4x4 tile

        XCTAssertThrowsError(
            try RFBRawFramebufferDecoder.apply(
                updateData: Data(bytes),
                serverInit: serverInit(width: 4, height: 4),
                previousFramebuffer: nil
            )
        ) { error in
            XCTAssertEqual(error as? RFBRawFramebufferDecoderError, .malformedHextile)
        }
    }

    // MARK: - DesktopSize / ExtendedDesktopSize (-223 / -308)

    func testDesktopSizeReallocatesFramebuffer() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 4, height: 3, encoding: RFBEncoding.desktopSize)

        let previous = RFBRawFramebuffer(width: 2, height: 2, fill: red)
        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 2, height: 2),
            previousFramebuffer: previous
        )

        XCTAssertEqual(result.framebuffer.width, 4)
        XCTAssertEqual(result.framebuffer.height, 3)
        XCTAssertTrue(result.didResizeDesktop)
    }

    func testDesktopSizeThenRawDrawsAtNewSize() throws {
        var bytes = messageHeader(rectangleCount: 2)
        bytes += rectangleHeader(x: 0, y: 0, width: 2, height: 2, encoding: RFBEncoding.desktopSize)
        bytes += rectangleHeader(x: 0, y: 0, width: 2, height: 2, encoding: RFBEncoding.raw)
        bytes += pixelBytes(red) + pixelBytes(green) + pixelBytes(blue) + pixelBytes(white)

        // Server init says 1x1; the DesktopSize grows it to 2x2 mid-update
        // and the following Raw rect validates against the new bounds.
        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 1, height: 1),
            previousFramebuffer: nil
        )

        XCTAssertEqual(result.framebuffer.width, 2)
        XCTAssertEqual(result.framebuffer.height, 2)
        XCTAssertTrue(result.didResizeDesktop)
        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.framebuffer[1, 1], white)
    }

    func testExtendedDesktopSizeConsumesScreenArrayAndResizes() throws {
        var bytes = messageHeader(rectangleCount: 1)
        // reason/result ride in x/y; width/height carry the new size.
        bytes += rectangleHeader(x: 0, y: 0, width: 3, height: 2, encoding: RFBEncoding.extendedDesktopSize)
        bytes += [1, 0, 0, 0] // number-of-screens = 1, 3 bytes padding
        bytes += [0, 0, 0, 1] // screen id
        bytes += [0, 0, 0, 0] // x, y
        bytes += [0, 3, 0, 2] // w=3, h=2
        bytes += [0, 0, 0, 0] // flags

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 5, height: 5),
            previousFramebuffer: RFBRawFramebuffer(width: 5, height: 5)
        )

        XCTAssertEqual(result.framebuffer.width, 3)
        XCTAssertEqual(result.framebuffer.height, 2)
        XCTAssertTrue(result.didResizeDesktop)
    }

    func testDesktopSizeRejectsAbsurdDimensions() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 20000, height: 20000, encoding: RFBEncoding.desktopSize)

        XCTAssertThrowsError(
            try RFBRawFramebufferDecoder.apply(
                updateData: Data(bytes),
                serverInit: serverInit(width: 2, height: 2),
                previousFramebuffer: RFBRawFramebuffer(width: 2, height: 2)
            )
        ) { error in
            XCTAssertEqual(
                error as? RFBRawFramebufferDecoderError,
                .invalidDimensions(width: 20000, height: 20000)
            )
        }
    }

    // MARK: - LastRect (-224)

    func testLastRectTerminatesUnknownCountUpdate() throws {
        // Declared count 0xFFFF: one Raw rect, then LastRect. The decoder
        // must stop at LastRect instead of trying to read 65535 rects.
        var bytes = messageHeader(rectangleCount: 0xFFFF)
        bytes += rectangleHeader(x: 0, y: 0, width: 1, height: 1, encoding: RFBEncoding.raw)
        bytes += pixelBytes(red)
        bytes += rectangleHeader(x: 0, y: 0, width: 0, height: 0, encoding: RFBEncoding.lastRect)

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 1, height: 1),
            previousFramebuffer: nil
        )

        XCTAssertEqual(result.framebuffer[0, 0], red)
    }

    // MARK: - Cursor pseudo-encoding (-239)

    func testCursorPseudoEncodingSurfacesCursorWithoutChangingFramebuffer() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 1, y: 1, width: 2, height: 2, encoding: RFBEncoding.cursor)
        bytes += pixelBytes(red) + pixelBytes(green) + pixelBytes(blue) + pixelBytes(white)
        bytes += [
            0b1000_0000, // row 0: opaque, transparent
            0b0100_0000  // row 1: transparent, opaque
        ]

        let previous = RFBRawFramebuffer(width: 3, height: 3, fill: black)
        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 3, height: 3),
            previousFramebuffer: previous
        )

        XCTAssertEqual(result.framebuffer, previous)
        XCTAssertTrue(result.dirtyRectangles.isEmpty)
        XCTAssertEqual(result.changedPixelCount, 0)

        let cursor = try XCTUnwrap(result.serverCursor)
        XCTAssertEqual(cursor.width, 2)
        XCTAssertEqual(cursor.height, 2)
        XCTAssertEqual(cursor.hotSpotX, 1)
        XCTAssertEqual(cursor.hotSpotY, 1)
        XCTAssertEqual(cursor[0, 0], red)
        XCTAssertEqual(cursor[1, 0], RFBColor(red: 0, green: 0, blue: 0, alpha: 0))
        XCTAssertEqual(cursor[0, 1], RFBColor(red: 0, green: 0, blue: 0, alpha: 0))
        XCTAssertEqual(cursor[1, 1], white)
    }

    func testXCursorPseudoEncodingSurfacesCursorWithoutChangingFramebuffer() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 2, y: 3, width: 3, height: 2, encoding: RFBEncoding.xCursor)
        bytes += [
            255, 0, 0, // primary red
            0, 255, 0  // secondary green
        ]
        bytes += [
            0b1010_0000, // row 0 bitmap: primary, secondary, primary
            0b0100_0000  // row 1 bitmap: secondary, primary, secondary
        ]
        bytes += [
            0b1110_0000, // row 0 all valid
            0b1010_0000  // row 1 middle transparent
        ]

        let previous = RFBRawFramebuffer(width: 4, height: 4, fill: black)
        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 4, height: 4),
            previousFramebuffer: previous
        )

        XCTAssertEqual(result.framebuffer, previous)
        XCTAssertTrue(result.dirtyRectangles.isEmpty)
        XCTAssertEqual(result.changedPixelCount, 0)

        let cursor = try XCTUnwrap(result.serverCursor)
        XCTAssertEqual(cursor.width, 3)
        XCTAssertEqual(cursor.height, 2)
        XCTAssertEqual(cursor.hotSpotX, 2)
        XCTAssertEqual(cursor.hotSpotY, 3)
        XCTAssertEqual(cursor[0, 0], red)
        XCTAssertEqual(cursor[1, 0], green)
        XCTAssertEqual(cursor[2, 0], red)
        XCTAssertEqual(cursor[0, 1], green)
        XCTAssertEqual(cursor[1, 1], RFBColor(red: 0, green: 0, blue: 0, alpha: 0))
        XCTAssertEqual(cursor[2, 1], green)
    }

    func testCursorPseudoEncodingRejectsAbsurdShape() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 2000, height: 2, encoding: RFBEncoding.cursor)

        XCTAssertThrowsError(
            try RFBRawFramebufferDecoder.apply(
                updateData: Data(bytes),
                serverInit: serverInit(width: 3, height: 3),
                previousFramebuffer: RFBRawFramebuffer(width: 3, height: 3)
            )
        ) { error in
            XCTAssertEqual(error as? RFBRawFramebufferDecoderError, .malformedCursor)
        }
    }

    func testXCursorPseudoEncodingRejectsAbsurdShape() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 2000, height: 2, encoding: RFBEncoding.xCursor)

        XCTAssertThrowsError(
            try RFBRawFramebufferDecoder.apply(
                updateData: Data(bytes),
                serverInit: serverInit(width: 3, height: 3),
                previousFramebuffer: RFBRawFramebuffer(width: 3, height: 3)
            )
        ) { error in
            XCTAssertEqual(error as? RFBRawFramebufferDecoderError, .malformedCursor)
        }
    }

    // MARK: - Helpers

    private func serverInit(width: Int, height: Int) -> RFBServerInit {
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

    /// Little-endian 32-bit pixel for the test format: byte order is
    /// blue, green, red, unused.
    private func pixelBytes(_ color: RFBColor) -> [UInt8] {
        [color.blue, color.green, color.red, 0]
    }

    private func messageHeader(rectangleCount: Int) -> [UInt8] {
        [0, 0, UInt8((rectangleCount >> 8) & 0xFF), UInt8(rectangleCount & 0xFF)]
    }

    private func rectangleHeader(x: Int, y: Int, width: Int, height: Int, encoding: Int32) -> [UInt8] {
        var bytes: [UInt8] = [
            UInt8((x >> 8) & 0xFF), UInt8(x & 0xFF),
            UInt8((y >> 8) & 0xFF), UInt8(y & 0xFF),
            UInt8((width >> 8) & 0xFF), UInt8(width & 0xFF),
            UInt8((height >> 8) & 0xFF), UInt8(height & 0xFF)
        ]
        let unsignedEncoding = UInt32(bitPattern: encoding)
        bytes += [
            UInt8((unsignedEncoding >> 24) & 0xFF),
            UInt8((unsignedEncoding >> 16) & 0xFF),
            UInt8((unsignedEncoding >> 8) & 0xFF),
            UInt8(unsignedEncoding & 0xFF)
        ]
        return bytes
    }

    private func rawUpdate(x: Int, y: Int, width: Int, height: Int, colors: [RFBColor]) -> Data {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: x, y: y, width: width, height: height, encoding: RFBEncoding.raw)
        for color in colors {
            bytes += pixelBytes(color)
        }
        return Data(bytes)
    }

    private func copyRectUpdate(dstX: Int, dstY: Int, width: Int, height: Int, srcX: Int, srcY: Int) -> Data {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: dstX, y: dstY, width: width, height: height, encoding: RFBEncoding.copyRect)
        bytes += [
            UInt8((srcX >> 8) & 0xFF), UInt8(srcX & 0xFF),
            UInt8((srcY >> 8) & 0xFF), UInt8(srcY & 0xFF)
        ]
        return Data(bytes)
    }
}
