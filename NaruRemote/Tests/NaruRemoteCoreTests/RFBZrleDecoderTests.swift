import Foundation
import XCTest
@testable import NaruRemoteCore

/// ZRLE (encoding 16) decode coverage (spec 004 Increment 2). Fixtures
/// are real zlib streams produced by Python `zlib.compressobj` +
/// `Z_SYNC_FLUSH` (see `/tmp/gen_zrle.py` provenance in the PR), one tile
/// per subencoding, so the tile parser + CPIXEL sizing + persistent
/// inflate are all exercised offline. The killer end-to-end check is the
/// live macOS Screen Sharing test, which sends real ZRLE.
final class RFBZrleDecoderTests: XCTestCase {
    private let red = RFBColor(red: 255, green: 0, blue: 0)
    private let green = RFBColor(red: 0, green: 255, blue: 0)
    private let blue = RFBColor(red: 0, green: 0, blue: 255)
    private let white = RFBColor(red: 255, green: 255, blue: 255)

    func testDecodesSolidTile() throws {
        let result = try RFBRawFramebufferDecoder.apply(
            updateData: try fixture("zrle-solid"),
            serverInit: serverInit(width: 2, height: 2)
        )
        for x in 0..<2 {
            for y in 0..<2 {
                XCTAssertEqual(result.framebuffer[x, y], red)
            }
        }
    }

    func testDecodesRawTile() throws {
        let result = try RFBRawFramebufferDecoder.apply(
            updateData: try fixture("zrle-raw"),
            serverInit: serverInit(width: 2, height: 2)
        )
        XCTAssertEqual(result.framebuffer[0, 0], red)
        XCTAssertEqual(result.framebuffer[1, 0], green)
        XCTAssertEqual(result.framebuffer[0, 1], blue)
        XCTAssertEqual(result.framebuffer[1, 1], white)
    }

    func testDecodesPackedPaletteTile() throws {
        let frame = try decode("zrle-packed-palette", width: 4, height: 1)
        XCTAssertEqual([frame[0, 0], frame[1, 0], frame[2, 0], frame[3, 0]], [red, red, red, blue])
    }

    func testDecodesPlainRLETile() throws {
        let frame = try decode("zrle-plain-rle", width: 4, height: 1)
        XCTAssertEqual([frame[0, 0], frame[1, 0], frame[2, 0], frame[3, 0]], [red, red, red, blue])
    }

    func testDecodesPaletteRLETile() throws {
        let frame = try decode("zrle-palette-rle", width: 4, height: 1)
        XCTAssertEqual([frame[0, 0], frame[1, 0], frame[2, 0], frame[3, 0]], [red, red, red, blue])
    }

    func testStreamPersistsAcrossUpdates() throws {
        // The crux of FR-005: one persistent stream decodes two
        // successive ZRLE updates (frame 1 red, frame 2 green).
        let stream = try RFBZlibInflateStream()
        let init1 = serverInit(width: 2, height: 2)

        let first = try RFBFramebufferDecoder.decodeUpdate(
            reader: RFBDataReader(try fixture("zrle-persist1")),
            serverInit: init1,
            previousFramebuffer: nil,
            zlibStream: stream
        )
        XCTAssertEqual(first.framebuffer[0, 0], red)
        XCTAssertEqual(first.framebuffer[1, 1], red)

        let second = try RFBFramebufferDecoder.decodeUpdate(
            reader: RFBDataReader(try fixture("zrle-persist2")),
            serverInit: init1,
            previousFramebuffer: first.framebuffer,
            zlibStream: stream
        )
        XCTAssertEqual(second.framebuffer[0, 0], green)
        XCTAssertEqual(second.framebuffer[1, 1], green)
    }

    func testResettingStreamCorruptsSecondUpdate() throws {
        // Proves the persistence requirement is real: decoding update 2
        // through a FRESH stream (i.e. resetting per update) does NOT
        // reproduce green — it throws or yields wrong pixels, which would
        // corrupt every frame after the first in a live session.
        let streamA = try RFBZlibInflateStream()
        let init1 = serverInit(width: 2, height: 2)
        _ = try RFBFramebufferDecoder.decodeUpdate(
            reader: RFBDataReader(try fixture("zrle-persist1")),
            serverInit: init1,
            previousFramebuffer: nil,
            zlibStream: streamA
        )

        let freshStream = try RFBZlibInflateStream()
        let corrupted = try? RFBFramebufferDecoder.decodeUpdate(
            reader: RFBDataReader(try fixture("zrle-persist2")),
            serverInit: init1,
            previousFramebuffer: nil,
            zlibStream: freshStream
        )
        XCTAssertNotEqual(corrupted?.framebuffer[0, 0], green)
    }

    // MARK: - Helpers

    private func decode(_ name: String, width: Int, height: Int) throws -> RFBRawFramebuffer {
        try RFBRawFramebufferDecoder.apply(
            updateData: try fixture(name),
            serverInit: serverInit(width: width, height: height)
        ).framebuffer
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

    private func fixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            root.deleteLastPathComponent()
        }
        return try Data(contentsOf: root
            .appendingPathComponent("TestFixtures/FakeRFBServer/Fixtures")
            .appendingPathComponent("\(name).bin"))
    }
}
