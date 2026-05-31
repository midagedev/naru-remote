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

    func testViewportSourceRectCentersAndClampsCrop() {
        XCTAssertEqual(
            PiPWatchViewport(centerX: 0.5, centerY: 0.5, zoomScale: 2)
                .sourceRect(framebufferWidth: 4, height: 4),
            PiPWatchSourceRect(x: 1, y: 1, width: 2, height: 2)
        )
        XCTAssertEqual(
            PiPWatchViewport(centerX: 1, centerY: 1, zoomScale: 2)
                .sourceRect(framebufferWidth: 4, height: 4),
            PiPWatchSourceRect(x: 2, y: 2, width: 2, height: 2)
        )
    }

    func testFactoryRendersZoomedViewportIntoStableFullSizePixelBuffer() throws {
        let framebuffer = try Self.gradientFramebuffer(width: 4, height: 4)

        let pixelBuffer = try PiPWatchSampleBufferFactory().makePixelBuffer(
            from: framebuffer,
            viewport: PiPWatchViewport(centerX: 0.5, centerY: 0.5, zoomScale: 2)
        )

        XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), 4)
        XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), 4)
        XCTAssertEqual(try Self.color(in: pixelBuffer, x: 0, y: 0), Self.gradientColor(x: 1, y: 1))
        XCTAssertEqual(try Self.color(in: pixelBuffer, x: 3, y: 3), Self.gradientColor(x: 2, y: 2))
    }

    func testFactoryRendersPannedViewportFromClampedLowerRightFocus() throws {
        let framebuffer = try Self.gradientFramebuffer(width: 4, height: 4)

        let pixelBuffer = try PiPWatchSampleBufferFactory().makePixelBuffer(
            from: framebuffer,
            viewport: PiPWatchViewport(centerX: 1, centerY: 1, zoomScale: 2)
        )

        XCTAssertEqual(try Self.color(in: pixelBuffer, x: 0, y: 0), Self.gradientColor(x: 2, y: 2))
        XCTAssertEqual(try Self.color(in: pixelBuffer, x: 3, y: 3), Self.gradientColor(x: 3, y: 3))
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

    private struct FramebufferFixture: Encodable {
        let width: Int
        let height: Int
        let pixels: [RFBColor]
    }

    private static func gradientFramebuffer(width: Int, height: Int) throws -> RFBRawFramebuffer {
        let pixels = (0..<height).flatMap { y in
            (0..<width).map { x in
                gradientColor(x: x, y: y)
            }
        }
        let data = try JSONEncoder().encode(
            FramebufferFixture(width: width, height: height, pixels: pixels)
        )
        return try JSONDecoder().decode(RFBRawFramebuffer.self, from: data)
    }

    private static func gradientColor(x: Int, y: Int) -> RFBColor {
        RFBColor(red: UInt8(x * 50), green: UInt8(y * 50), blue: UInt8((x + y) * 20))
    }

    private static func color(in pixelBuffer: CVPixelBuffer, x: Int, y: Int) throws -> RFBColor {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let offset = y * bytesPerRow + x * 4
        return RFBColor(
            red: bytes[offset + 2],
            green: bytes[offset + 1],
            blue: bytes[offset],
            alpha: bytes[offset + 3]
        )
    }
}
#endif
