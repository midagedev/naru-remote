import Foundation
import XCTest
@testable import NaruRemoteCore

final class RFBEncodingTests: XCTestCase {
    // MARK: - Preference ordering

    func testIncrement1PreferenceOrdersHextileAndCopyRectAheadOfRaw() {
        let list = RFBEncodingPreference.increment1.encodingList()

        // Hextile and CopyRect precede Raw; Raw is present as the floor.
        let hextileIndex = list.firstIndex(of: RFBEncoding.hextile)
        let copyRectIndex = list.firstIndex(of: RFBEncoding.copyRect)
        let rawIndex = list.firstIndex(of: RFBEncoding.raw)

        XCTAssertNotNil(hextileIndex)
        XCTAssertNotNil(copyRectIndex)
        XCTAssertNotNil(rawIndex)
        XCTAssertLessThan(hextileIndex!, rawIndex!)
        XCTAssertLessThan(copyRectIndex!, rawIndex!)
    }

    func testRawIsAlwaysLastAmongRealEncodings() {
        // No real encoding (>= 0) may appear after Raw — Raw is the
        // universal fallback (RFC 6143 §7.7.1).
        let list = RFBEncodingPreference(zrle: true, tight: true).encodingList()
        let rawIndex = list.firstIndex(of: RFBEncoding.raw)!
        let realEncodingsAfterRaw = list[(rawIndex + 1)...].filter { $0 >= 0 }
        XCTAssertTrue(realEncodingsAfterRaw.isEmpty)
    }

    func testIncrement1PreferenceIncludesStreamingPseudoEncodings() {
        let list = RFBEncodingPreference.increment1.encodingList()
        XCTAssertTrue(list.contains(RFBEncoding.lastRect))
        XCTAssertTrue(list.contains(RFBEncoding.desktopSize))
        XCTAssertTrue(list.contains(RFBEncoding.extendedDesktopSize))
        // Increment 1 does not yet decode ZRLE / Tight / Cursor, so they
        // must NOT be advertised (we can only advertise what we consume).
        XCTAssertFalse(list.contains(RFBEncoding.zrle))
        XCTAssertFalse(list.contains(RFBEncoding.tight))
        XCTAssertFalse(list.contains(RFBEncoding.cursor))
    }

    func testFullPreferenceOrdersZrleAndTightFirst() {
        let list = RFBEncodingPreference(zrle: true, tight: true, hextile: true, copyRect: true)
            .encodingList()
        XCTAssertEqual(list.first, RFBEncoding.zrle)
        XCTAssertEqual(list[1], RFBEncoding.tight)
    }

    func testQualityAndCompressionHintsRideOnlyOnTheirEncodings() {
        // Tight quality hint only when Tight is advertised.
        let withoutTight = RFBEncodingPreference(tight: false, tightQualityLevel: 5).encodingList()
        XCTAssertFalse(withoutTight.contains(RFBEncoding.tightQualityLevel(5)))

        let withTight = RFBEncodingPreference(tight: true, tightQualityLevel: 5).encodingList()
        XCTAssertTrue(withTight.contains(RFBEncoding.tightQualityLevel(5)))

        // Compression hint only when a zlib-using encoding is advertised.
        let noZlib = RFBEncodingPreference(zrle: false, tight: false, compressionLevel: 9).encodingList()
        XCTAssertFalse(noZlib.contains(RFBEncoding.tightCompressionLevel(9)))

        let withZlib = RFBEncodingPreference(zrle: true, compressionLevel: 9).encodingList()
        XCTAssertTrue(withZlib.contains(RFBEncoding.tightCompressionLevel(9)))
    }

    func testTightQualityAndCompressionCodes() {
        // Community RFB codes: qualityLevel0 = -32 … qualityLevel9 = -23.
        XCTAssertEqual(RFBEncoding.tightQualityLevel(0), -32)
        XCTAssertEqual(RFBEncoding.tightQualityLevel(9), -23)
        // compressLevel0 = -256 … compressLevel9 = -247.
        XCTAssertEqual(RFBEncoding.tightCompressionLevel(0), -256)
        XCTAssertEqual(RFBEncoding.tightCompressionLevel(9), -247)
        // Out-of-range clamps.
        XCTAssertEqual(RFBEncoding.tightQualityLevel(99), -23)
        XCTAssertEqual(RFBEncoding.tightCompressionLevel(-5), -256)
    }

    // MARK: - SetEncodings wire bytes

    func testSetEncodingsProducesExactWireBytes() {
        let message = RFBClientMessageEncoder.setEncodings([RFBEncoding.hextile, RFBEncoding.raw, RFBEncoding.desktopSize])
        XCTAssertEqual([UInt8](message), [
            2,          // message type
            0,          // padding
            0, 3,       // number-of-encodings = 3
            0, 0, 0, 5, // Hextile
            0, 0, 0, 0, // Raw
            0xFF, 0xFF, 0xFF, 0x21 // DesktopSize (-223)
        ])
    }

    func testSetEncodingsEmptyList() {
        let message = RFBClientMessageEncoder.setEncodings([])
        XCTAssertEqual([UInt8](message), [2, 0, 0, 0])
    }

    // MARK: - SetPixelFormat wire bytes

    func testSetPixelFormatProducesTwentyByteMessage() {
        let format = RFBPixelFormat(
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
        )
        let message = RFBClientMessageEncoder.setPixelFormat(format)
        XCTAssertEqual([UInt8](message), [
            0, 0, 0, 0,          // type + 3 padding
            32, 24, 0, 1,        // bpp, depth, big-endian flag, true-colour flag
            0, 255, 0, 255, 0, 255, // r/g/b max (u16 each)
            16, 8, 0,            // r/g/b shift
            0, 0, 0              // padding
        ])
    }
}
