import Foundation
import XCTest
@testable import NaruRemoteCore

final class RFBTightDecoderTests: XCTestCase {
    private let red = RFBColor(red: 255, green: 0, blue: 0)
    private let green = RFBColor(red: 0, green: 255, blue: 0)
    private let blue = RFBColor(red: 0, green: 0, blue: 255)
    private let black = RFBColor(red: 0, green: 0, blue: 0)
    private let white = RFBColor(red: 255, green: 255, blue: 255)

    func testDecodesTightFillRectangleUsingRGBTriplet() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 1, y: 0, width: 2, height: 2, encoding: RFBEncoding.tight)
        bytes += [0x80] // compression type: fill
        bytes += tightPixelBytes(red)

        let previous = RFBRawFramebuffer(width: 4, height: 2, fill: black)
        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 4, height: 2),
            previousFramebuffer: previous
        )

        XCTAssertEqual(result.framebuffer[0, 0], black)
        XCTAssertEqual(result.framebuffer[1, 0], red)
        XCTAssertEqual(result.framebuffer[2, 0], red)
        XCTAssertEqual(result.framebuffer[1, 1], red)
        XCTAssertEqual(result.framebuffer[2, 1], red)
        XCTAssertEqual(result.dirtyRectangles, [RFBFrameDamageRect(x: 1, y: 0, width: 2, height: 2)])
        XCTAssertEqual(result.changedPixelCount, 4)
    }

    func testDecodesTightNoZlibBasicCopy() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 2, height: 1, encoding: RFBEncoding.tight)
        bytes += [0xA0] // compression type: basic, no zlib, no filter byte
        bytes += tightPixelBytes(red)
        bytes += tightPixelBytes(green)

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 2, height: 1),
            previousFramebuffer: RFBRawFramebuffer(width: 2, height: 1, fill: black)
        )

        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.framebuffer[1, 0], green)
        XCTAssertEqual(result.changedPixelCount, 2)
    }

    func testDecodesSmallTightBasicCopyWithoutCompactLength() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 3, height: 1, encoding: RFBEncoding.tight)
        bytes += [0x00] // zlib stream 0, copy filter, but payload is < 12 bytes so uncompressed
        bytes += tightPixelBytes(red)
        bytes += tightPixelBytes(green)
        bytes += tightPixelBytes(blue)

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 3, height: 1),
            previousFramebuffer: RFBRawFramebuffer(width: 3, height: 1, fill: black)
        )

        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.framebuffer[1, 0], green)
        XCTAssertEqual(result.framebuffer[2, 0], blue)
        XCTAssertEqual(result.changedPixelCount, 3)
    }

    func testDecodesTightZlibBasicCopy() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 4, height: 1, encoding: RFBEncoding.tight)
        bytes += [0x00] // zlib stream 0, copy filter
        bytes += compactLength(tightZlibCopyFrame1.count)
        bytes += tightZlibCopyFrame1

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 4, height: 1),
            previousFramebuffer: RFBRawFramebuffer(width: 4, height: 1, fill: black)
        )

        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.framebuffer[1, 0], green)
        XCTAssertEqual(result.framebuffer[2, 0], blue)
        XCTAssertEqual(result.framebuffer[3, 0], white)
    }

    func testDecodesTightNoZlibBasicCopyWithCompactLength() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 4, height: 1, encoding: RFBEncoding.tight)
        bytes += [0xA0] // no-zlib copy, payload is >= 12 bytes so a compact length is present
        let pixels = tightPixelBytes(red) + tightPixelBytes(green) + tightPixelBytes(blue) + tightPixelBytes(white)
        bytes += compactLength(pixels.count)
        bytes += pixels

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 4, height: 1),
            previousFramebuffer: RFBRawFramebuffer(width: 4, height: 1, fill: black)
        )

        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.framebuffer[1, 0], green)
        XCTAssertEqual(result.framebuffer[2, 0], blue)
        XCTAssertEqual(result.framebuffer[3, 0], white)
    }

    func testTightZlibStreamPersistsAcrossUpdates() throws {
        let streams = RFBTightZlibStreams()
        let init4x1 = serverInit(width: 4, height: 1)

        let first = try RFBFramebufferDecoder.decodeUpdate(
            reader: RFBDataReader(tightZlibUpdate(compressed: tightZlibCopyFrame1)),
            serverInit: init4x1,
            previousFramebuffer: RFBRawFramebuffer(width: 4, height: 1, fill: black),
            tightZlibStreams: streams
        )
        let second = try RFBFramebufferDecoder.decodeUpdate(
            reader: RFBDataReader(tightZlibUpdate(compressed: tightZlibCopyFrame2)),
            serverInit: init4x1,
            previousFramebuffer: first.framebuffer,
            tightZlibStreams: streams
        )

        XCTAssertEqual([second.framebuffer[0, 0], second.framebuffer[1, 0]], [green, green])
        XCTAssertEqual([second.framebuffer[2, 0], second.framebuffer[3, 0]], [green, green])
    }

    func testTightZlibResetBitStartsFreshStream() throws {
        let streams = RFBTightZlibStreams()
        let init4x1 = serverInit(width: 4, height: 1)

        _ = try RFBFramebufferDecoder.decodeUpdate(
            reader: RFBDataReader(tightZlibUpdate(compressed: tightZlibCopyFrame1)),
            serverInit: init4x1,
            previousFramebuffer: RFBRawFramebuffer(width: 4, height: 1, fill: black),
            tightZlibStreams: streams
        )
        let second = try RFBFramebufferDecoder.decodeUpdate(
            reader: RFBDataReader(tightZlibUpdate(control: 0x01, compressed: tightZlibCopyFreshStream)),
            serverInit: init4x1,
            previousFramebuffer: RFBRawFramebuffer(width: 4, height: 1, fill: black),
            tightZlibStreams: streams
        )

        XCTAssertEqual([second.framebuffer[0, 0], second.framebuffer[1, 0]], [green, green])
        XCTAssertEqual([second.framebuffer[2, 0], second.framebuffer[3, 0]], [green, green])
    }

    func testDecodesTightNoZlibPaletteFilterWithOneBitIndices() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 4, height: 1, encoding: RFBEncoding.tight)
        bytes += [0xE0] // no-zlib basic with explicit filter id
        bytes += [0x01] // palette filter
        bytes += [0x01] // palette size minus one: 2 colors
        bytes += tightPixelBytes(red)
        bytes += tightPixelBytes(blue)
        bytes += [0b1010_0000] // most-significant bits are leftmost pixels

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 4, height: 1),
            previousFramebuffer: RFBRawFramebuffer(width: 4, height: 1, fill: black)
        )

        XCTAssertEqual([result.framebuffer[0, 0], result.framebuffer[1, 0]], [blue, red])
        XCTAssertEqual([result.framebuffer[2, 0], result.framebuffer[3, 0]], [blue, red])
    }

    func testDecodesTightNoZlibPaletteFilterWithEightBitIndices() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 4, height: 1, encoding: RFBEncoding.tight)
        bytes += [0xE0] // no-zlib basic with explicit filter id
        bytes += [0x01] // palette filter
        bytes += [0x02] // palette size minus one: 3 colors
        bytes += tightPixelBytes(red)
        bytes += tightPixelBytes(green)
        bytes += tightPixelBytes(blue)
        bytes += [0, 1, 2, 1]

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 4, height: 1),
            previousFramebuffer: RFBRawFramebuffer(width: 4, height: 1, fill: black)
        )

        XCTAssertEqual([result.framebuffer[0, 0], result.framebuffer[1, 0]], [red, green])
        XCTAssertEqual([result.framebuffer[2, 0], result.framebuffer[3, 0]], [blue, green])
    }

    func testDecodesTightZlibPaletteFilter() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 16, height: 8, encoding: RFBEncoding.tight)
        bytes += [0x40] // zlib stream 0, explicit filter id
        bytes += [0x01] // palette filter
        bytes += [0x01] // palette size minus one: 2 colors
        bytes += tightPixelBytes(red)
        bytes += tightPixelBytes(blue)
        bytes += compactLength(tightZlibPaletteOneBitIndices.count)
        bytes += tightZlibPaletteOneBitIndices

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 16, height: 8),
            previousFramebuffer: RFBRawFramebuffer(width: 16, height: 8, fill: black)
        )

        XCTAssertEqual(result.framebuffer[0, 0], blue)
        XCTAssertEqual(result.framebuffer[1, 0], red)
        XCTAssertEqual(result.framebuffer[8, 0], red)
        XCTAssertEqual(result.framebuffer[9, 0], blue)
        XCTAssertEqual(result.framebuffer[15, 7], blue)
    }

    func testDecodesTightNoZlibGradientFilterWithCompactLength() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 3, height: 2, encoding: RFBEncoding.tight)
        bytes += [0xE0] // no-zlib basic with explicit filter id
        bytes += [0x02] // gradient filter
        bytes += compactLength(tightGradientDeltas.count)
        bytes += tightGradientDeltas

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 3, height: 2),
            previousFramebuffer: RFBRawFramebuffer(width: 3, height: 2, fill: black)
        )

        assertGradientFrame(result.framebuffer)
    }

    func testDecodesTightZlibGradientFilter() throws {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 3, height: 2, encoding: RFBEncoding.tight)
        bytes += [0x40] // zlib stream 0, explicit filter id
        bytes += [0x02] // gradient filter
        bytes += compactLength(tightZlibGradientDeltas.count)
        bytes += tightZlibGradientDeltas

        let result = try RFBRawFramebufferDecoder.apply(
            updateData: Data(bytes),
            serverInit: serverInit(width: 3, height: 2),
            previousFramebuffer: RFBRawFramebuffer(width: 3, height: 2, fill: black)
        )

        assertGradientFrame(result.framebuffer)
    }

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

    private func tightPixelBytes(_ color: RFBColor) -> [UInt8] {
        [color.red, color.green, color.blue]
    }

    private func assertGradientFrame(_ framebuffer: RFBRawFramebuffer) {
        XCTAssertEqual([framebuffer[0, 0], framebuffer[1, 0], framebuffer[2, 0]], [red, red, green])
        XCTAssertEqual([framebuffer[0, 1], framebuffer[1, 1], framebuffer[2, 1]], [blue, white, black])
    }

    private var tightZlibCopyFrame1: [UInt8] {
        [120, 156, 250, 207, 192, 192, 240, 31, 132, 129, 0, 0, 0, 0, 255, 255]
    }

    private var tightZlibCopyFrame2: [UInt8] {
        [2, 49, 96, 8, 0, 0, 0, 255, 255]
    }

    private var tightZlibCopyFreshStream: [UInt8] {
        [120, 156, 98, 248, 207, 192, 0, 67, 0, 0, 0, 0, 255, 255]
    }

    private var tightZlibPaletteOneBitIndices: [UInt8] {
        [120, 156, 90, 21, 186, 10, 5, 2, 0, 0, 0, 255, 255]
    }

    private var tightGradientDeltas: [UInt8] {
        [
            255, 0, 0,
            0, 0, 0,
            1, 255, 0,
            1, 0, 255,
            255, 255, 0,
            0, 1, 1
        ]
    }

    private var tightZlibGradientDeltas: [UInt8] {
        [120, 156, 250, 207, 0, 2, 140, 255, 25, 24, 25, 254, 255, 255, 15, 100, 49, 2, 0, 0, 0, 255, 255]
    }

    private func tightZlibUpdate(control: UInt8 = 0x00, compressed: [UInt8]) -> Data {
        var bytes = messageHeader(rectangleCount: 1)
        bytes += rectangleHeader(x: 0, y: 0, width: 4, height: 1, encoding: RFBEncoding.tight)
        bytes += [control]
        bytes += compactLength(compressed.count)
        bytes += compressed
        return Data(bytes)
    }

    private func compactLength(_ value: Int) -> [UInt8] {
        precondition(value >= 0 && value <= 0x3F_FFFF)
        var bytes = [UInt8(value & 0x7F)]
        if value <= 0x7F {
            return bytes
        }
        bytes[0] |= 0x80
        bytes.append(UInt8((value >> 7) & 0x7F))
        if value <= 0x3FFF {
            return bytes
        }
        bytes[1] |= 0x80
        bytes.append(UInt8((value >> 14) & 0xFF))
        return bytes
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
}
