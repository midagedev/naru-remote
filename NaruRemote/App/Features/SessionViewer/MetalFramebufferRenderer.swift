import Foundation
import NaruRemoteCore

#if canImport(Metal) && canImport(MetalKit)
import Metal
import MetalKit

/// GPU-backed renderer for `RFBRawFramebuffer` pixels.
///
/// Maintains a single `MTLTexture` whose dimensions track the most
/// recently presented framebuffer.  Each new frame is uploaded via
/// `texture.replaceRegion(_:mipmapLevel:withBytes:bytesPerRow:)`; the
/// texture is recreated only when framebuffer dimensions change so
/// steady-state streaming avoids per-frame allocations.
///
/// Rendering uses an inline Metal Shading Language source (no separate
/// `.metal` file is needed for the fullscreen-quad pass).  The pipeline
/// state is built once at init; aspect-fit is applied at draw time by
/// computing a centered viewport that mirrors the
/// `videoGravity = .resizeAspect` choice used by the PiP path.
@MainActor
public final class MetalFramebufferRenderer: NSObject {
    public let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var texture: MTLTexture?
    private var pendingFramebuffer: RFBRawFramebuffer?

    /// Creates a renderer bound to the given device.  Returns `nil`
    /// when the system cannot supply a `MTLCommandQueue` or fails to
    /// compile the inline shader source — callers fall back to the
    /// sampled SwiftUI preview path in that case.
    public init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try Self.makePipelineState(device: device)
        } catch {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        super.init()
    }

    /// Stores the next framebuffer.  Texture allocation/upload happens
    /// during `MTKView` draw callbacks so we never block the RFB stream
    /// on GPU work.
    public func enqueue(_ framebuffer: RFBRawFramebuffer) {
        guard framebuffer.width > 0, framebuffer.height > 0 else {
            return
        }
        pendingFramebuffer = framebuffer
    }

    /// Test/inspection helper.  Reflects the current texture dimensions
    /// after any pending upload has been applied.
    public var currentTextureSize: (width: Int, height: Int)? {
        guard let texture else { return nil }
        return (texture.width, texture.height)
    }

    /// Test helper that performs the upload step that `draw(in:)` would
    /// perform — independent of an `MTKView`/drawable so unit tests can
    /// verify texture state without hitting the display pipeline.
    @discardableResult
    public func uploadPendingFramebufferForTesting() -> Bool {
        applyPendingFramebuffer()
    }

    /// Read-back of texture pixels for unit tests.  The buffer is
    /// returned in the texture's pixel format (RGBA8Unorm), one byte per
    /// channel, row-major.
    public func readbackTextureForTesting() -> [UInt8]? {
        guard let texture else { return nil }
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            texture.getBytes(
                baseAddress,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return bytes
    }

    // MARK: - Private

    @discardableResult
    fileprivate func applyPendingFramebuffer() -> Bool {
        guard let framebuffer = pendingFramebuffer else {
            return false
        }
        pendingFramebuffer = nil

        // Recreate the texture when dimensions change to avoid a
        // partial-overwrite of a stale-sized texture.
        if texture?.width != framebuffer.width || texture?.height != framebuffer.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: framebuffer.width,
                height: framebuffer.height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            guard let newTexture = device.makeTexture(descriptor: descriptor) else {
                return false
            }
            texture = newTexture
        }

        guard let texture else {
            return false
        }

        // RFBColor is laid out as red, green, blue, alpha — RGBA8Unorm
        // matches that ordering byte-for-byte, so we can copy the pixel
        // array directly without per-channel swizzling.
        let bytesPerRow = framebuffer.width * 4
        framebuffer.pixels.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            texture.replace(
                region: MTLRegionMake2D(0, 0, framebuffer.width, framebuffer.height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: bytesPerRow
            )
        }
        return true
    }

    fileprivate func draw(in view: MTKView) {
        applyPendingFramebuffer()

        guard let texture,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            return
        }

        let viewport = Self.aspectFitViewport(
            drawableSize: view.drawableSize,
            textureWidth: texture.width,
            textureHeight: texture.height
        )
        encoder.setViewport(viewport)
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    static func aspectFitViewport(
        drawableSize: CGSize,
        textureWidth: Int,
        textureHeight: Int
    ) -> MTLViewport {
        guard drawableSize.width > 0,
              drawableSize.height > 0,
              textureWidth > 0,
              textureHeight > 0
        else {
            return MTLViewport(originX: 0, originY: 0, width: 0, height: 0, znear: 0, zfar: 1)
        }

        let drawableAspect = drawableSize.width / drawableSize.height
        let textureAspect = Double(textureWidth) / Double(textureHeight)

        let fitWidth: Double
        let fitHeight: Double
        if drawableAspect > textureAspect {
            fitHeight = drawableSize.height
            fitWidth = fitHeight * textureAspect
        } else {
            fitWidth = drawableSize.width
            fitHeight = fitWidth / textureAspect
        }

        let originX = (drawableSize.width - fitWidth) / 2
        let originY = (drawableSize.height - fitHeight) / 2
        return MTLViewport(
            originX: originX,
            originY: originY,
            width: fitWidth,
            height: fitHeight,
            znear: 0,
            zfar: 1
        )
    }

    private static func makePipelineState(device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try device.makeLibrary(source: shaderSource, options: nil)

        guard let vertexFunction = library.makeFunction(name: "naruRemoteFullscreenVertex") else {
            throw MetalFramebufferRendererError.functionUnavailable("naruRemoteFullscreenVertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "naruRemoteFullscreenFragment") else {
            throw MetalFramebufferRendererError.functionUnavailable("naruRemoteFullscreenFragment")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Inline Metal Shading Language source.  The vertex stage emits a
    /// single oversized triangle that covers the viewport; the fragment
    /// stage samples the framebuffer texture using clamped linear
    /// filtering.  Keeping the source inline avoids needing a `.metal`
    /// compile target alongside the SwiftPM module — Metal builds the
    /// library at runtime via `device.makeLibrary(source:options:)`.
    private static let shaderSource: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut naruRemoteFullscreenVertex(uint vertexId [[vertex_id]]) {
        // Oversized triangle covering the [-1,1] clip volume.
        const float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        const float2 uvs[3] = {
            float2(0.0, 1.0),
            float2(2.0, 1.0),
            float2(0.0, -1.0)
        };
        VertexOut out;
        out.position = float4(positions[vertexId], 0.0, 1.0);
        out.uv = uvs[vertexId];
        return out;
    }

    fragment float4 naruRemoteFullscreenFragment(
        VertexOut in [[stage_in]],
        texture2d<float> framebuffer [[texture(0)]]
    ) {
        constexpr sampler textureSampler(
            filter::linear,
            address::clamp_to_edge
        );
        return framebuffer.sample(textureSampler, in.uv);
    }
    """
}

public enum MetalFramebufferRendererError: Error, Equatable {
    case functionUnavailable(String)
}

/// `MTKViewDelegate` adaptor.  The delegate routes Metal callbacks back
/// onto the main actor; `MTKView` defaults to invoking its delegate on
/// the main thread, which matches the renderer's `@MainActor` isolation.
public final class MetalFramebufferViewDelegate: NSObject, MTKViewDelegate {
    private let renderer: MetalFramebufferRenderer

    public init(renderer: MetalFramebufferRenderer) {
        self.renderer = renderer
        super.init()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Aspect-fit is computed per draw call, so a size change does
        // not need extra bookkeeping.  Trigger a redraw so the next
        // frame uses the new drawable dimensions immediately.
        #if canImport(UIKit)
        view.setNeedsDisplay()
        #else
        view.needsDisplay = true
        #endif
    }

    public func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            renderer.draw(in: view)
        }
    }
}
#endif
