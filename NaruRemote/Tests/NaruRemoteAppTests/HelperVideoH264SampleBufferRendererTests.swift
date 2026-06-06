import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(AVFoundation) && canImport(CoreMedia)
import AVFoundation
import CoreMedia

final class HelperVideoH264SampleBufferRendererTests: XCTestCase {
    func testAnnexBParserAcceptsThreeAndFourByteStartCodes() throws {
        let units = try HelperVideoH264AnnexBParser.parse(
            Self.annexB([
                Self.sps,
                Self.pps,
                Self.idr,
                Self.delta
            ])
        )

        XCTAssertEqual(units.map(\.type), [7, 8, 5, 1])
        XCTAssertEqual(units.map(\.payload.count), [
            Self.sps.count,
            Self.pps.count,
            Self.idr.count,
            Self.delta.count
        ])
    }

    func testAnnexBParserRejectsAVCCLengthPrefixedPayload() {
        XCTAssertThrowsError(
            try HelperVideoH264AnnexBParser.parse(Data([0, 0, 0, 4, 0x65, 0x88, 0x84, 0x21]))
        ) { error in
            XCTAssertEqual(
                error as? HelperVideoH264SampleBufferFactoryError,
                .invalidAnnexBPayload
            )
        }
    }

    func testParameterSetAccessUnitCachesFormatWithoutEmittingFrame() throws {
        let factory = HelperVideoH264SampleBufferFactory()

        let sampleBuffer = try factory.makeSampleBuffer(
            from: Self.envelope(kind: .parameterSet),
            binaryPayload: Self.annexB([Self.sps, Self.pps])
        )

        XCTAssertNil(sampleBuffer)
        XCTAssertEqual(
            factory.cachedFormatDimensions,
            HelperVideoH264FrameDimensions(width: 640, height: 352)
        )
    }

    func testKeyframeAccessUnitCreatesReadyCompressedSampleBuffer() throws {
        let factory = HelperVideoH264SampleBufferFactory(timescale: 30)

        let sampleBuffer = try XCTUnwrap(
            factory.makeSampleBuffer(
                from: Self.envelope(kind: .keyframe),
                binaryPayload: Self.annexB([Self.sps, Self.pps, Self.idr])
            )
        )

        XCTAssertTrue(CMSampleBufferDataIsReady(sampleBuffer))
        XCTAssertNil(CMSampleBufferGetImageBuffer(sampleBuffer))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), CMTime(value: 0, timescale: 30))
        let formatDescription = try XCTUnwrap(CMSampleBufferGetFormatDescription(sampleBuffer))
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(formatDescription), kCMVideoCodecType_H264)

        let samplePayload = try Self.samplePayloadBytes(from: sampleBuffer)
        XCTAssertEqual(samplePayload.prefix(4), Data([0, 0, 0, UInt8(Self.idr.count)]))
        XCTAssertEqual(samplePayload.dropFirst(4).first, Self.idr.first)
    }

    func testDeltaAccessUnitRequiresCachedParameterSets() {
        let factory = HelperVideoH264SampleBufferFactory()

        XCTAssertThrowsError(
            try factory.makeSampleBuffer(
                from: Self.envelope(kind: .delta),
                binaryPayload: Self.annexB([Self.delta])
            )
        ) { error in
            XCTAssertEqual(
                error as? HelperVideoH264SampleBufferFactoryError,
                .missingParameterSets
            )
        }
    }

    func testDeltaAccessUnitAdvancesPresentationTimeAfterCachedParameterSets() throws {
        let factory = HelperVideoH264SampleBufferFactory(timescale: 15)
        XCTAssertNil(
            try factory.makeSampleBuffer(
                from: Self.envelope(kind: .parameterSet, sequence: 0),
                binaryPayload: Self.annexB([Self.sps, Self.pps])
            )
        )

        let keyframe = try XCTUnwrap(
            factory.makeSampleBuffer(
                from: Self.envelope(kind: .keyframe, sequence: 1),
                binaryPayload: Self.annexB([Self.idr])
            )
        )
        let delta = try XCTUnwrap(
            factory.makeSampleBuffer(
                from: Self.envelope(kind: .delta, sequence: 2),
                binaryPayload: Self.annexB([Self.delta])
            )
        )

        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(keyframe), CMTime(value: 0, timescale: 15))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(delta), CMTime(value: 1, timescale: 15))
    }

    func testEndOfStreamResetsCachedFormat() throws {
        let factory = HelperVideoH264SampleBufferFactory()
        XCTAssertNil(
            try factory.makeSampleBuffer(
                from: Self.envelope(kind: .parameterSet),
                binaryPayload: Self.annexB([Self.sps, Self.pps])
            )
        )
        XCTAssertNotNil(factory.cachedFormatDimensions)

        let end = try factory.makeSampleBuffer(
            from: Self.envelope(kind: .endOfStream),
            binaryPayload: Self.annexB([Self.delta])
        )

        XCTAssertNil(end)
        XCTAssertNil(factory.cachedFormatDimensions)
    }

    func testDecodedFrameConvenienceRequiresBinaryPayload() {
        let factory = HelperVideoH264SampleBufferFactory()
        let decoded = HelperVideoDecodedFrame(
            envelope: Self.envelope(kind: .keyframe),
            binaryPayload: nil
        )

        XCTAssertThrowsError(try factory.makeSampleBuffer(from: decoded)) { error in
            XCTAssertEqual(
                error as? HelperVideoH264SampleBufferFactoryError,
                .missingBinaryPayload
            )
        }
    }

    func testRendererUsesAspectResizeAndIgnoresParameterSetOnlyAccessUnit() throws {
        let renderer = HelperVideoH264SampleBufferRenderer()
        let decoded = HelperVideoDecodedFrame(
            envelope: Self.envelope(kind: .parameterSet),
            binaryPayload: Self.annexB([Self.sps, Self.pps])
        )

        XCTAssertEqual(renderer.displayLayer.videoGravity, .resizeAspect)
        XCTAssertNil(try renderer.enqueue(decoded))
    }

    private static let sps = Data([
        0x67, 0x42, 0xC0, 0x1E, 0xDA, 0x02, 0x80, 0xB7,
        0xFE, 0x5C, 0x05, 0xA8, 0x30, 0x30, 0x32, 0x00,
        0x00, 0x03, 0x00, 0x02, 0x00, 0x00, 0x03, 0x00,
        0x65, 0x1E, 0x30, 0x60, 0x54
    ])
    private static let pps = Data([0x68, 0xCE, 0x06, 0xE2])
    private static let idr = Data([0x65, 0x88, 0x84, 0x21])
    private static let delta = Data([0x41, 0x9A, 0x22])

    private static func envelope(
        kind: HelperVideoAccessUnitKind,
        sequence: Int = 1
    ) -> HelperVideoWireEnvelope<HelperVideoAccessUnitBody> {
        HelperVideoWireEnvelope(
            messageType: .videoAccessUnit,
            profileFingerprint: "sha256:test-profile",
            body: HelperVideoAccessUnitBody(sequence: sequence, kind: kind)
        )
    }

    private static func annexB(_ units: [Data]) -> Data {
        units.enumerated().reduce(into: Data()) { payload, item in
            payload.append(item.offset.isMultiple(of: 2)
                ? Data([0x00, 0x00, 0x00, 0x01])
                : Data([0x00, 0x00, 0x01]))
            payload.append(item.element)
        }
    }

    private static func samplePayloadBytes(from sampleBuffer: CMSampleBuffer) throws -> Data {
        let blockBuffer = try XCTUnwrap(CMSampleBufferGetDataBuffer(sampleBuffer))
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var bytes = [UInt8](repeating: 0, count: length)
        let status = bytes.withUnsafeMutableBytes { buffer in
            CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: length,
                destination: buffer.baseAddress!
            )
        }
        XCTAssertEqual(status, noErr)
        return Data(bytes)
    }
}
#endif
