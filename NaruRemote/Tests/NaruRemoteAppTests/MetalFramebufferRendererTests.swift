import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(Metal) && canImport(MetalKit)
import Metal
import MetalKit

@MainActor
final class MetalFramebufferRendererTests: XCTestCase {
    private func requireDevice() throws -> MTLDevice {
        try XCTSkipUnless(
            MTLCreateSystemDefaultDevice() != nil,
            "Metal device unavailable on this CI host."
        )
        return MTLCreateSystemDefaultDevice()!
    }

    // MARK: - Texture lifecycle

    func testRendererCreatesTextureMatchingFramebufferDimensions() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        let framebuffer = RFBRawFramebuffer(
            width: 4,
            height: 3,
            fill: RFBColor(red: 10, green: 20, blue: 30, alpha: 255)
        )

        renderer.enqueue(framebuffer)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        let size = try XCTUnwrap(renderer.currentTextureSize)
        XCTAssertEqual(size.width, 4)
        XCTAssertEqual(size.height, 3)
    }

    func testRendererPreservesRGBAByteOrder() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 200, green: 100, blue: 50, alpha: 240)
        )

        renderer.enqueue(framebuffer)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        XCTAssertEqual(bytes.count, 8)
        // RGBA8Unorm stores red, green, blue, alpha in that byte order
        // — round-trip a known pattern so we catch any accidental
        // swizzle in the upload path.
        XCTAssertEqual(bytes[0], 200, "red byte 0")
        XCTAssertEqual(bytes[1], 100, "green byte 1")
        XCTAssertEqual(bytes[2], 50, "blue byte 2")
        XCTAssertEqual(bytes[3], 240, "alpha byte 3")
        XCTAssertEqual(bytes[4], 200, "red byte 4 (second pixel)")
        XCTAssertEqual(bytes[5], 100)
        XCTAssertEqual(bytes[6], 50)
        XCTAssertEqual(bytes[7], 240)
    }

    func testRendererRecreatesTextureWhenDimensionsChange() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 10, green: 0, blue: 0))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        let firstSize = try XCTUnwrap(renderer.currentTextureSize)
        XCTAssertEqual(firstSize.width, 4)
        XCTAssertEqual(firstSize.height, 4)

        renderer.enqueue(
            RFBRawFramebuffer(width: 8, height: 2, fill: RFBColor(red: 0, green: 30, blue: 0))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        let secondSize = try XCTUnwrap(renderer.currentTextureSize)
        XCTAssertEqual(secondSize.width, 8)
        XCTAssertEqual(secondSize.height, 2)

        // The full readback must reflect the new dimensions — a partial
        // overwrite of a stale 4x4 texture would leave residue.
        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        XCTAssertEqual(bytes.count, 8 * 2 * 4)
        XCTAssertEqual(bytes[1], 30, "every pixel should be the new green fill")
        XCTAssertEqual(bytes[bytes.count - 3], 30)
    }

    func testRendererIgnoresZeroSizedFramebuffers() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        renderer.enqueue(RFBRawFramebuffer(width: 0, height: 0))
        XCTAssertFalse(
            renderer.uploadPendingFramebufferForTesting(),
            "Zero-size framebuffers must not allocate a texture."
        )
        XCTAssertNil(renderer.currentTextureSize)
    }

    // MARK: - Aspect-fit viewport

    func testAspectFitCenteredHorizontalLetterboxing() {
        // 16:9 drawable, 1:1 texture — texture should fit on the
        // shorter axis (height) and be centered horizontally.
        let viewport = MetalFramebufferRenderer.aspectFitViewport(
            drawableSize: CGSize(width: 1600, height: 900),
            textureWidth: 100,
            textureHeight: 100
        )
        XCTAssertEqual(viewport.width, 900, accuracy: 0.001)
        XCTAssertEqual(viewport.height, 900, accuracy: 0.001)
        XCTAssertEqual(viewport.originX, 350, accuracy: 0.001)
        XCTAssertEqual(viewport.originY, 0, accuracy: 0.001)
    }

    func testAspectFitCenteredVerticalLetterboxing() {
        // 1:1 drawable, 4:3 texture — texture is wider than the
        // drawable per unit height, so it fits on width and is
        // centered vertically.
        let viewport = MetalFramebufferRenderer.aspectFitViewport(
            drawableSize: CGSize(width: 1000, height: 1000),
            textureWidth: 4,
            textureHeight: 3
        )
        XCTAssertEqual(viewport.width, 1000, accuracy: 0.001)
        XCTAssertEqual(viewport.height, 750, accuracy: 0.001)
        XCTAssertEqual(viewport.originX, 0, accuracy: 0.001)
        XCTAssertEqual(viewport.originY, 125, accuracy: 0.001)
    }

    func testAspectFitClampsToZeroForEmptyDrawable() {
        let viewport = MetalFramebufferRenderer.aspectFitViewport(
            drawableSize: .zero,
            textureWidth: 100,
            textureHeight: 100
        )
        XCTAssertEqual(viewport.width, 0)
        XCTAssertEqual(viewport.height, 0)
    }
}
#endif
