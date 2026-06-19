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

    func testFullFrameRawFastPathMatchesSplitGenericRawDecode() throws {
        let colors = [
            RFBColor(red: 255, green: 0, blue: 0),
            RFBColor(red: 0, green: 255, blue: 0),
            RFBColor(red: 0, green: 0, blue: 255),
            RFBColor(red: 0, green: 0, blue: 0),
            RFBColor(red: 64, green: 128, blue: 192),
            RFBColor(red: 255, green: 255, blue: 255)
        ]
        let serverInit = Self.serverInit(width: 3, height: 2)

        let fastPathResult = try RFBRawFramebufferDecoder.apply(
            updateData: Self.rawUpdateData(rectangles: [
                RawRectangle(x: 0, y: 0, width: 3, height: 2, colors: colors)
            ]),
            serverInit: serverInit
        )
        let splitGenericResult = try RFBRawFramebufferDecoder.apply(
            updateData: Self.rawUpdateData(rectangles: [
                RawRectangle(x: 0, y: 0, width: 3, height: 1, colors: Array(colors[0..<3])),
                RawRectangle(x: 0, y: 1, width: 3, height: 1, colors: Array(colors[3..<6]))
            ]),
            serverInit: serverInit
        )

        XCTAssertEqual(fastPathResult.framebuffer, splitGenericResult.framebuffer)
        XCTAssertEqual(fastPathResult.changedPixelCount, splitGenericResult.changedPixelCount)
        XCTAssertEqual(fastPathResult.changedPixelCount, 5)
        XCTAssertEqual(fastPathResult.dirtyRectangles, [
            RFBFrameDamageRect(x: 0, y: 0, width: 3, height: 2)
        ])
        XCTAssertEqual(splitGenericResult.dirtyRectangles, [
            RFBFrameDamageRect(x: 0, y: 0, width: 3, height: 1),
            RFBFrameDamageRect(x: 0, y: 1, width: 3, height: 1)
        ])
    }

    func testFastPixelDecodeHandlesCommonLittleEndianRGB888Layout() {
        let format = Self.rgb888Format(isBigEndian: false, redShift: 16, greenShift: 8, blueShift: 0)
        let bytes: [UInt8] = [0x33, 0x22, 0x11, 0x00]

        XCTAssertEqual(format.decodeColor(bytes, at: 0), RFBColor(red: 0x11, green: 0x22, blue: 0x33))
        XCTAssertEqual(format.decodeCPixel(bytes, at: 0, size: 3), RFBColor(red: 0x11, green: 0x22, blue: 0x33))
    }

    func testFastPixelDecodeHandlesCommonBigEndianRGB888Layout() {
        let format = Self.rgb888Format(isBigEndian: true, redShift: 16, greenShift: 8, blueShift: 0)
        let bytes: [UInt8] = [0x00, 0x11, 0x22, 0x33]
        let cpixelBytes: [UInt8] = [0x11, 0x22, 0x33]

        XCTAssertEqual(format.decodeColor(bytes, at: 0), RFBColor(red: 0x11, green: 0x22, blue: 0x33))
        XCTAssertEqual(format.decodeCPixel(cpixelBytes, at: 0, size: 3), RFBColor(red: 0x11, green: 0x22, blue: 0x33))
    }

    func testPixelDecodeFallsBackForNonByteAlignedChannels() {
        let format = RFBPixelFormat.rgb565In32LittleEndian
        let value: UInt32 = (31 << 11) | (63 << 5) | 31
        let bytes: [UInt8] = [
            UInt8(value & 0x000000ff),
            UInt8((value >> 8) & 0x000000ff),
            UInt8((value >> 16) & 0x000000ff),
            UInt8((value >> 24) & 0x000000ff)
        ]

        XCTAssertEqual(format.decodeColor(bytes, at: 0), RFBColor(red: 255, green: 255, blue: 255))
    }

    func testRasterRunFillTracksChangedBoundsAcrossRows() {
        let red = RFBColor(red: 255, green: 0, blue: 0)
        let blue = RFBColor(red: 0, green: 0, blue: 255)
        var framebuffer = RFBRawFramebuffer(width: 6, height: 4, fill: red)

        let result = framebuffer.fillRasterRunTrackingChange(
            originX: 1,
            originY: 1,
            tileWidth: 4,
            tileHeight: 2,
            startRaster: 2,
            runLength: 5,
            color: blue
        )

        XCTAssertEqual(result.changedPixelCount, 5)
        XCTAssertEqual(result.rectangle, RFBFrameDamageRect(x: 1, y: 1, width: 4, height: 2))
        XCTAssertEqual(framebuffer[3, 1], blue)
        XCTAssertEqual(framebuffer[4, 1], blue)
        XCTAssertEqual(framebuffer[1, 2], blue)
        XCTAssertEqual(framebuffer[2, 2], blue)
        XCTAssertEqual(framebuffer[3, 2], blue)
        XCTAssertEqual(framebuffer[1, 1], red)
        XCTAssertEqual(framebuffer[4, 2], red)

        let identical = framebuffer.fillRasterRunTrackingChange(
            originX: 1,
            originY: 1,
            tileWidth: 4,
            tileHeight: 2,
            startRaster: 2,
            runLength: 5,
            color: blue
        )
        XCTAssertEqual(identical.changedPixelCount, 0)
        XCTAssertNil(identical.rectangle)
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

    func testFramebufferUpdateTimingClampsAndDerivesClientProcessing() {
        let timing = RFBFramebufferUpdateTiming(
            totalMilliseconds: 18,
            networkReadMilliseconds: 11,
            firstByteWaitMilliseconds: 8
        )
        let clamped = RFBFramebufferUpdateTiming(
            totalMilliseconds: -5,
            networkReadMilliseconds: 20,
            firstByteWaitMilliseconds: 25
        )

        XCTAssertEqual(timing.totalMilliseconds, 18)
        XCTAssertEqual(timing.networkReadMilliseconds, 11)
        XCTAssertEqual(timing.firstByteWaitMilliseconds, 8)
        XCTAssertEqual(timing.payloadReadMilliseconds, 3)
        XCTAssertEqual(timing.clientProcessingMilliseconds, 7)
        XCTAssertEqual(clamped.totalMilliseconds, 0)
        XCTAssertEqual(clamped.networkReadMilliseconds, 20)
        XCTAssertEqual(clamped.firstByteWaitMilliseconds, 20)
        XCTAssertEqual(clamped.payloadReadMilliseconds, 0)
        XCTAssertEqual(clamped.clientProcessingMilliseconds, 0)
    }

    func testFramebufferDecodeMetricsClampSafeAggregates() {
        let metrics = RFBFramebufferDecodeMetrics(
            zrleInflateMilliseconds: 12,
            zrleTileApplyMilliseconds: 34
        )
        let clamped = RFBFramebufferDecodeMetrics(
            zrleInflateMilliseconds: -1,
            zrleTileApplyMilliseconds: -2
        )

        XCTAssertEqual(metrics.zrleInflateMilliseconds, 12)
        XCTAssertEqual(metrics.zrleTileApplyMilliseconds, 34)
        XCTAssertTrue(metrics.hasMeasurements)
        XCTAssertEqual(clamped.zrleInflateMilliseconds, 0)
        XCTAssertEqual(clamped.zrleTileApplyMilliseconds, 0)
        XCTAssertFalse(clamped.hasMeasurements)
    }

    func testFramebufferEncodingMixClampsAndAggregatesSafeCounts() {
        let mix = RFBFramebufferEncodingMix(
            rawRectangles: -1,
            hextileRectangles: 2,
            cursorRectangles: 1
        )
        let updated = mix
            .recordingRectangle(encoding: RFBEncoding.raw)
            .recordingRectangle(encoding: RFBEncoding.copyRect)
            .adding(RFBFramebufferEncodingMix(endOfContinuousUpdatesEvents: 1))

        XCTAssertEqual(mix.rawRectangles, 0)
        XCTAssertEqual(mix.hextileRectangles, 2)
        XCTAssertEqual(mix.cursorRectangles, 1)
        XCTAssertEqual(updated.rawRectangles, 1)
        XCTAssertEqual(updated.copyRectRectangles, 1)
        XCTAssertEqual(updated.hextileRectangles, 2)
        XCTAssertEqual(updated.cursorRectangles, 1)
        XCTAssertEqual(updated.endOfContinuousUpdatesEvents, 1)
        XCTAssertEqual(updated.totalRectangles, 5)
    }

    func testFramebufferUpdateResultDecodesLegacyPayloadWithoutContinuousEndFlag() throws {
        let original = RFBFramebufferUpdateResult(
            framebuffer: RFBRawFramebuffer(width: 1, height: 1),
            dirtyRectangles: [],
            changedPixelCount: 0,
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "endedContinuousUpdates")
        object.removeValue(forKey: "transportIdleTimedOut")
        object.removeValue(forKey: "timing")
        object.removeValue(forKey: "decodeMetrics")
        object.removeValue(forKey: "encodingMix")
        let legacyPayload = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(RFBFramebufferUpdateResult.self, from: legacyPayload)

        XCTAssertFalse(decoded.endedContinuousUpdates)
        XCTAssertFalse(decoded.transportIdleTimedOut)
        XCTAssertNil(decoded.timing)
        XCTAssertEqual(decoded.decodeMetrics, RFBFramebufferDecodeMetrics())
        XCTAssertEqual(decoded.encodingMix, RFBFramebufferEncodingMix())
        XCTAssertEqual(decoded.framebuffer, original.framebuffer)
        XCTAssertEqual(decoded.dirtyRectangles, original.dirtyRectangles)
        XCTAssertEqual(decoded.changedPixelCount, original.changedPixelCount)
    }

    func testFramebufferUpdateResultRoundTripsContinuousEndFlag() throws {
        let original = RFBFramebufferUpdateResult(
            framebuffer: RFBRawFramebuffer(width: 1, height: 1),
            dirtyRectangles: [],
            changedPixelCount: 0,
            endedContinuousUpdates: true,
            encodingMix: RFBFramebufferEncodingMix(endOfContinuousUpdatesEvents: 1)
        )

        let decoded = try JSONDecoder().decode(
            RFBFramebufferUpdateResult.self,
            from: try JSONEncoder().encode(original)
        )

        XCTAssertTrue(decoded.endedContinuousUpdates)
        XCTAssertEqual(decoded.encodingMix.endOfContinuousUpdatesEvents, 1)
    }

    func testFramebufferUpdateResultRoundTripsTransportIdleTimeoutFlag() throws {
        let original = RFBFramebufferUpdateResult(
            framebuffer: RFBRawFramebuffer(width: 1, height: 1),
            dirtyRectangles: [],
            changedPixelCount: 0,
            transportIdleTimedOut: true
        )

        let decoded = try JSONDecoder().decode(
            RFBFramebufferUpdateResult.self,
            from: try JSONEncoder().encode(original)
        )

        XCTAssertTrue(decoded.transportIdleTimedOut)
    }

    func testFramebufferUpdateResultRoundTripsReceiveTiming() throws {
        let original = RFBFramebufferUpdateResult(
            framebuffer: RFBRawFramebuffer(width: 1, height: 1),
            dirtyRectangles: [],
            changedPixelCount: 0,
            timing: RFBFramebufferUpdateTiming(
                totalMilliseconds: 42,
                networkReadMilliseconds: 40,
                firstByteWaitMilliseconds: 31
            )
        )

        let decoded = try JSONDecoder().decode(
            RFBFramebufferUpdateResult.self,
            from: try JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded.timing?.totalMilliseconds, 42)
        XCTAssertEqual(decoded.timing?.networkReadMilliseconds, 40)
        XCTAssertEqual(decoded.timing?.firstByteWaitMilliseconds, 31)
        XCTAssertEqual(decoded.timing?.payloadReadMilliseconds, 9)
        XCTAssertEqual(decoded.timing?.clientProcessingMilliseconds, 2)
    }

    func testFramebufferUpdateResultRoundTripsDecodeMetrics() throws {
        let original = RFBFramebufferUpdateResult(
            framebuffer: RFBRawFramebuffer(width: 1, height: 1),
            dirtyRectangles: [],
            changedPixelCount: 0,
            decodeMetrics: RFBFramebufferDecodeMetrics(
                zrleInflateMilliseconds: 11,
                zrleTileApplyMilliseconds: 22
            )
        )

        let decoded = try JSONDecoder().decode(
            RFBFramebufferUpdateResult.self,
            from: try JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded.decodeMetrics.zrleInflateMilliseconds, 11)
        XCTAssertEqual(decoded.decodeMetrics.zrleTileApplyMilliseconds, 22)
    }

    func testWithTimingPreservesDecodeMetrics() {
        let original = RFBFramebufferUpdateResult(
            framebuffer: RFBRawFramebuffer(width: 1, height: 1),
            dirtyRectangles: [],
            changedPixelCount: 0,
            decodeMetrics: RFBFramebufferDecodeMetrics(
                zrleInflateMilliseconds: 3,
                zrleTileApplyMilliseconds: 5
            )
        )

        let updated = original.withTiming(
            RFBFramebufferUpdateTiming(totalMilliseconds: 20, networkReadMilliseconds: 7)
        )

        XCTAssertEqual(updated.timing?.clientProcessingMilliseconds, 13)
        XCTAssertEqual(updated.decodeMetrics.zrleInflateMilliseconds, 3)
        XCTAssertEqual(updated.decodeMetrics.zrleTileApplyMilliseconds, 5)
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

    private static func rawUpdateData(rectangles: [RawRectangle]) -> Data {
        var data = Data([0, 0])
        appendUInt16(UInt16(rectangles.count), to: &data)
        for rectangle in rectangles {
            appendUInt16(rectangle.x, to: &data)
            appendUInt16(rectangle.y, to: &data)
            appendUInt16(rectangle.width, to: &data)
            appendUInt16(rectangle.height, to: &data)
            appendInt32(RFBEncoding.raw, to: &data)
            for color in rectangle.colors {
                data.append(color.blue)
                data.append(color.green)
                data.append(color.red)
                data.append(0)
            }
        }
        return data
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0x00ff))
        data.append(UInt8(value & 0x00ff))
    }

    private static func appendInt32(_ value: Int32, to data: inout Data) {
        let rawValue = UInt32(bitPattern: value)
        data.append(UInt8((rawValue >> 24) & 0x000000ff))
        data.append(UInt8((rawValue >> 16) & 0x000000ff))
        data.append(UInt8((rawValue >> 8) & 0x000000ff))
        data.append(UInt8(rawValue & 0x000000ff))
    }

    private static func serverInit(width: Int, height: Int) -> RFBServerInit {
        RFBServerInit(
            width: width,
            height: height,
            pixelFormat: rgb888Format(isBigEndian: false, redShift: 16, greenShift: 8, blueShift: 0),
            name: "Test"
        )
    }

    private static func rgb888Format(
        isBigEndian: Bool,
        redShift: UInt8,
        greenShift: UInt8,
        blueShift: UInt8
    ) -> RFBPixelFormat {
        RFBPixelFormat(
            bitsPerPixel: 32,
            depth: 24,
            isBigEndian: isBigEndian,
            isTrueColor: true,
            redMax: 255,
            greenMax: 255,
            blueMax: 255,
            redShift: redShift,
            greenShift: greenShift,
            blueShift: blueShift
        )
    }
}

private struct RawRectangle {
    let x: UInt16
    let y: UInt16
    let width: UInt16
    let height: UInt16
    let colors: [RFBColor]
}
