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
        XCTAssertFalse(list.contains(RFBEncoding.xCursor))
    }

    func testFullPreferenceOrdersZrleAndTightFirst() {
        let list = RFBEncodingPreference(zrle: true, tight: true, hextile: true, copyRect: true)
            .encodingList()
        XCTAssertEqual(list.first, RFBEncoding.zrle)
        XCTAssertEqual(list[1], RFBEncoding.tight)
    }

    func testLocalLowLatencyPrefersHextileAndOmitsZrleForMacResponsiveness() {
        let list = RFBEncodingPreference.localLowLatency.encodingList()

        XCTAssertEqual(list.first, RFBEncoding.hextile)
        XCTAssertFalse(list.contains(RFBEncoding.zrle))
        XCTAssertTrue(list.contains(RFBEncoding.raw))
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

    func testAdaptivePreferenceLowersQualityAndRaisesCompressionOnPoorBucket() {
        let good = RFBEncodingPreference.adaptive(
            supported: .full,
            requestedPseudoEncodings: .withServerCursor,
            connectionQuality: .good
        ).encodingList()
        let poor = RFBEncodingPreference.adaptive(
            supported: .full,
            requestedPseudoEncodings: .withServerCursor,
            connectionQuality: .poor
        ).encodingList()

        XCTAssertTrue(good.contains(RFBEncoding.tightQualityLevel(8)))
        XCTAssertTrue(good.contains(RFBEncoding.tightCompressionLevel(1)))
        XCTAssertTrue(poor.contains(RFBEncoding.tightQualityLevel(2)))
        XCTAssertTrue(poor.contains(RFBEncoding.tightCompressionLevel(8)))
        XCTAssertTrue(good.contains(RFBEncoding.cursor))
        XCTAssertTrue(good.contains(RFBEncoding.xCursor))
        XCTAssertTrue(poor.contains(RFBEncoding.cursor))
        XCTAssertTrue(poor.contains(RFBEncoding.xCursor))
    }

    func testAdaptivePreferenceDoesNotAdvertiseUnsupportedHintsOrCursor() {
        let list = RFBEncodingPreference.adaptive(
            supported: .increment1,
            requestedPseudoEncodings: .withServerCursor,
            connectionQuality: .poor
        ).encodingList()

        XCTAssertFalse(list.contains(RFBEncoding.zrle))
        XCTAssertFalse(list.contains(RFBEncoding.tight))
        XCTAssertFalse(list.contains(RFBEncoding.cursor))
        XCTAssertFalse(list.contains(RFBEncoding.xCursor))
        XCTAssertFalse(list.contains(RFBEncoding.tightQualityLevel(2)))
        XCTAssertFalse(list.contains(RFBEncoding.tightCompressionLevel(8)))
        XCTAssertTrue(list.contains(RFBEncoding.hextile))
        XCTAssertTrue(list.contains(RFBEncoding.raw))
    }

    func testAdaptivePreferenceUsesLatencyOrderingForGoodAndBandwidthOrderingForPoor() {
        let good = RFBEncodingPreference.adaptive(
            supported: .increment2,
            connectionQuality: .good
        ).encodingList()
        let poor = RFBEncodingPreference.adaptive(
            supported: .increment2,
            connectionQuality: .poor
        ).encodingList()

        XCTAssertEqual(good.first, RFBEncoding.hextile)
        XCTAssertEqual(poor.first, RFBEncoding.zrle)
    }

    func testAdaptivePreferenceOnlyAdvertisesPacingExtensionsWhenSupportedAndRequested() {
        let requestedOnly = RFBEncodingPreference.adaptive(
            supported: .increment2,
            requestedPseudoEncodings: .withPacingExtensions,
            connectionQuality: .fair
        ).encodingList()
        XCTAssertFalse(requestedOnly.contains(RFBEncoding.fence))
        XCTAssertFalse(requestedOnly.contains(RFBEncoding.continuousUpdates))

        let supportedAndRequested = RFBEncodingPreference.adaptive(
            supported: RFBEncodingSupport(zrle: true, fence: true, continuousUpdates: true),
            requestedPseudoEncodings: .withPacingExtensions,
            connectionQuality: .fair
        ).encodingList()
        XCTAssertTrue(supportedAndRequested.contains(RFBEncoding.fence))
        XCTAssertTrue(supportedAndRequested.contains(RFBEncoding.continuousUpdates))
    }

    func testAdaptivePreferenceCanRequestCursorAndPacingTogetherForFullSupport() {
        let list = RFBEncodingPreference.adaptive(
            supported: .full,
            requestedPseudoEncodings: .withServerCursorAndPacingExtensions,
            connectionQuality: .good
        ).encodingList()

        XCTAssertTrue(list.contains(RFBEncoding.cursor))
        XCTAssertTrue(list.contains(RFBEncoding.xCursor))
        XCTAssertTrue(list.contains(RFBEncoding.fence))
        XCTAssertTrue(list.contains(RFBEncoding.continuousUpdates))
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
