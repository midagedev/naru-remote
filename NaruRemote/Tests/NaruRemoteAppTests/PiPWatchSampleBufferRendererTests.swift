import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import AVFoundation
import CoreMedia
import CoreVideo

final class PiPWatchSampleBufferRendererTests: XCTestCase {
    func testFactoryCreatesBGRAThirtyTwoBitPixelBuffer() throws {
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 255, green: 32, blue: 16, alpha: 200)
        )

        let pixelBuffer = try PiPWatchSampleBufferFactory().makePixelBuffer(from: framebuffer)

        XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), 2)
        XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), 1)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixelBuffer), kCVPixelFormatType_32BGRA)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(bytes[0], 16)
        XCTAssertEqual(bytes[1], 32)
        XCTAssertEqual(bytes[2], 255)
        XCTAssertEqual(bytes[3], 200)
    }

    func testFactoryRejectsZeroSizedFramebuffer() {
        let framebuffer = RFBRawFramebuffer(width: 0, height: 1)

        XCTAssertThrowsError(
            try PiPWatchSampleBufferFactory().makePixelBuffer(from: framebuffer)
        ) { error in
            XCTAssertEqual(
                error as? PiPWatchSampleBufferRendererError,
                .unrenderableFramebuffer(width: 0, height: 1)
            )
        }
    }

    func testFactoryCreatesReadySampleBufferWithImageBuffer() throws {
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )

        let sampleBuffer = try PiPWatchSampleBufferFactory().makeSampleBuffer(
            from: framebuffer,
            presentationTime: CMTime(value: 4, timescale: 12)
        )

        XCTAssertTrue(CMSampleBufferDataIsReady(sampleBuffer))
        let imageBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))
        XCTAssertEqual(CVPixelBufferGetWidth(imageBuffer), 2)
        XCTAssertEqual(CVPixelBufferGetHeight(imageBuffer), 1)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), CMTime(value: 4, timescale: 12))
    }

    func testRendererUsesAspectResizeAndAdvancesPresentationTime() throws {
        let renderer = PiPWatchSampleBufferRenderer(timescale: 12)
        let framebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )

        let first = try renderer.enqueue(framebuffer)
        let second = try renderer.enqueue(framebuffer)

        XCTAssertEqual(renderer.displayLayer.videoGravity, .resizeAspect)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(first), CMTime(value: 0, timescale: 12))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(second), CMTime(value: 1, timescale: 12))
    }
}
#endif
