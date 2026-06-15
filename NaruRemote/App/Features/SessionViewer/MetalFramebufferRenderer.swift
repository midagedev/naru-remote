import Foundation
import NaruRemoteCore

#if canImport(Metal) && canImport(MetalKit)
import Metal
import MetalKit

public typealias MetalFramebufferUploadTimingHandler = @MainActor @Sendable (_ milliseconds: Int) -> Void
public typealias MetalFramebufferStagedUploadReadyHandler = @MainActor @Sendable () -> Void

private struct SendableMetalDevice: @unchecked Sendable {
    let device: MTLDevice
}

private struct MetalFramebufferStagedUploadRegion: @unchecked Sendable {
    let rectangle: RFBFrameDamageRect
    let bytesPerRow: Int
    let bytes: Data
}

private enum MetalFramebufferStagedUploadStorage: @unchecked Sendable {
    case full(buffer: MTLBuffer, bytesPerRow: Int)
    case partial([MetalFramebufferStagedUploadRegion])

    var bufferByteCount: Int {
        switch self {
        case .full(let buffer, _):
            return buffer.length
        case .partial(let regions):
            return regions.reduce(0) { $0 + $1.bytes.count }
        }
    }
}

private struct MetalFramebufferStagedUpload: @unchecked Sendable {
    let width: Int
    let height: Int
    let storage: MetalFramebufferStagedUploadStorage
    let preparationMilliseconds: Int

    var bufferByteCount: Int {
        storage.bufferByteCount
    }

    static func make(
        device: MTLDevice,
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]?,
        changedPixelCount: Int?,
        requiresTextureRecreation: Bool
    ) -> MetalFramebufferStagedUpload? {
        guard framebuffer.width > 0,
              framebuffer.height > 0,
              framebuffer.width <= Int.max / framebuffer.height
        else {
            return nil
        }
        let pixelCount = framebuffer.width * framebuffer.height
        guard pixelCount <= Int.max / 4,
              framebuffer.pixels.count >= pixelCount
        else {
            return nil
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let byteCount = pixelCount * 4
        let bytesPerRow = framebuffer.width * 4
        let validDirtyRectangles = FramebufferUploadPlan.validDirtyRectangles(
            dirtyRectangles,
            textureWidth: framebuffer.width,
            textureHeight: framebuffer.height
        )
        let uploadPlan = FramebufferUploadPlan.plan(
            framebufferWidth: framebuffer.width,
            framebufferHeight: framebuffer.height,
            dirtyRectangles: validDirtyRectangles,
            requiresTextureRecreation: requiresTextureRecreation,
            changedPixelCount: changedPixelCount
        )

        let storage: MetalFramebufferStagedUploadStorage
        if uploadPlan.strategy == .partial,
           MemoryLayout<RFBColor>.stride == 4,
           let regions = makePartialRegions(
               framebuffer: framebuffer,
               dirtyRectangles: validDirtyRectangles,
               sourceBytesPerRow: bytesPerRow
           ),
           !regions.isEmpty
        {
            storage = .partial(regions)
        } else if let buffer = makeFullBuffer(
            device: device,
            framebuffer: framebuffer,
            pixelCount: pixelCount,
            byteCount: byteCount
        ) {
            storage = .full(buffer: buffer, bytesPerRow: bytesPerRow)
        } else {
            return nil
        }

        return MetalFramebufferStagedUpload(
            width: framebuffer.width,
            height: framebuffer.height,
            storage: storage,
            preparationMilliseconds: Self.elapsedMilliseconds(since: startedAt)
        )
    }

    private static func makeFullBuffer(
        device: MTLDevice,
        framebuffer: RFBRawFramebuffer,
        pixelCount: Int,
        byteCount: Int
    ) -> MTLBuffer? {
        if MemoryLayout<RFBColor>.stride == 4 {
            return framebuffer.pixels.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return nil
                }
                return device.makeBuffer(
                    bytes: baseAddress,
                    length: byteCount,
                    options: .storageModeShared
                )
            }
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(byteCount)
        for pixel in framebuffer.pixels.prefix(pixelCount) {
            bytes.append(pixel.red)
            bytes.append(pixel.green)
            bytes.append(pixel.blue)
            bytes.append(pixel.alpha)
        }
        return bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return nil
            }
            return device.makeBuffer(
                bytes: baseAddress,
                length: byteCount,
                options: .storageModeShared
            )
        }
    }

    private static func makePartialRegions(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect],
        sourceBytesPerRow: Int
    ) -> [MetalFramebufferStagedUploadRegion]? {
        guard !dirtyRectangles.isEmpty else {
            return nil
        }

        let regions = framebuffer.pixels.withUnsafeBytes { rawBuffer
            -> [MetalFramebufferStagedUploadRegion]? in
            guard let sourceBaseAddress = rawBuffer.baseAddress else {
                return nil
            }
            var regions: [MetalFramebufferStagedUploadRegion] = []
            regions.reserveCapacity(dirtyRectangles.count)
            for rect in dirtyRectangles {
                let rectBytesPerRow = rect.width * 4
                let rectByteCount = rectBytesPerRow * rect.height
                var bytes = Data(count: rectByteCount)
                bytes.withUnsafeMutableBytes { destinationRawBuffer in
                    guard let destinationBaseAddress = destinationRawBuffer.baseAddress else {
                        return
                    }
                    for row in 0..<rect.height {
                        let sourceOffset = ((rect.y + row) * sourceBytesPerRow) + (rect.x * 4)
                        let destinationOffset = row * rectBytesPerRow
                        destinationBaseAddress
                            .advanced(by: destinationOffset)
                            .copyMemory(
                                from: sourceBaseAddress.advanced(by: sourceOffset),
                                byteCount: rectBytesPerRow
                            )
                    }
                }
                regions.append(
                    MetalFramebufferStagedUploadRegion(
                        rectangle: rect,
                        bytesPerRow: rectBytesPerRow,
                        bytes: bytes
                    )
                )
            }
            return regions
        }
        return regions
    }

    private static func elapsedMilliseconds(since start: UInt64) -> Int {
        let end = DispatchTime.now().uptimeNanoseconds
        let elapsedNanoseconds = end >= start ? end - start : 0
        return max(0, Int((Double(elapsedNanoseconds) / 1_000_000.0).rounded()))
    }
}

private struct MetalFramebufferStagingRequest: Sendable {
    let generation: Int
    let framebuffer: RFBRawFramebuffer
    let dirtyRectangles: [RFBFrameDamageRect]?
    let changedPixelCount: Int?
    let requiresTextureRecreation: Bool
}

/// GPU-backed renderer for `RFBRawFramebuffer` pixels.
///
/// Maintains a single `MTLTexture` whose dimensions track the most
/// recently presented framebuffer.  Draw-time uploads normally use a
/// staged `MTLBuffer` plus a blit pass so pixel preparation can happen
/// outside the render callback.  The immediate testing/fallback path
/// still uses `texture.replaceRegion(_:mipmapLevel:withBytes:bytesPerRow:)`
/// directly.
///
/// When the caller supplies `dirtyRectangles` for an incremental frame
/// and the texture dimensions still match the incoming buffer, the
/// staged path copies only the dirty bytes into compact region payloads
/// and replaces those regions in the existing texture.  When dirty
/// rectangles are nil or empty (full frame, first frame), or when the
/// texture had to be recreated for a dimension change, the renderer
/// falls back to a single full-frame upload.  The two paths are mutually
/// exclusive on any given frame so we never double-upload pixels.
///
/// Rendering uses an inline Metal Shading Language source (no separate
/// `.metal` file is needed for the fullscreen-quad pass).  The pipeline
/// state is built once at init; aspect-fit is applied at draw time by
/// computing a centered viewport that mirrors the
/// `videoGravity = .resizeAspect` choice used by the PiP path.
@MainActor
public final class MetalFramebufferRenderer: NSObject {
    static let maximumPartialUploadRegionCount = FramebufferUploadPlan.maximumPartialUploadRegionCount
    static let maximumPartialUploadAreaFraction = FramebufferUploadPlan.maximumPartialUploadAreaFraction
    public static let defaultMaximumViewportZoomScale: CGFloat = 4

    public let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var texture: MTLTexture?
    private var pendingFramebuffer: RFBRawFramebuffer?
    private var pendingDirtyRectangles: [RFBFrameDamageRect]?
    private var pendingChangedPixelCount: Int?
    private var pendingStagedUpload: MetalFramebufferStagedUpload?
    private var latestStagingRequest: MetalFramebufferStagingRequest?
    private var stagedUploadPreparationTask: Task<Void, Never>?
    private var stagedUploadGeneration = 0
    private var stagedUploadWorkerID = 0
    private var viewportZoomScale: CGFloat = 1
    private var viewportPanOffset: CGSize = .zero
    private var viewportMaxZoomScale: CGFloat = defaultMaximumViewportZoomScale
    private var isPendingFramebufferUploadSuspended = false
    private var pendingFramebufferUploadSuspensionBypassCount = 0

    private struct ViewportRenderUniforms {
        var left: Float
        var right: Float
        var top: Float
        var bottom: Float
    }

    /// Test/inspection helper.  Counts the number of `replaceRegion`
    /// calls (full or partial) issued during the most recent
    /// `applyPendingFramebuffer` invocation.  Reset at the start of
    /// every upload attempt so tests can assert per-frame upload
    /// arithmetic without keeping their own running tally.
    public private(set) var lastUploadRegionCount: Int = 0

    /// Test/inspection helper.  Captures the elapsed wall-clock time
    /// around the most recent successful texture allocation/upload
    /// path, rounded to milliseconds.  Raw timing never leaves memory;
    /// callers export only coarse timing buckets.
    public private(set) var lastUploadMilliseconds: Int?

    var uploadTimingHandler: MetalFramebufferUploadTimingHandler?
    var stagedUploadReadyHandler: MetalFramebufferStagedUploadReadyHandler?

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

    deinit {
        stagedUploadPreparationTask?.cancel()
    }

    /// Stores the next framebuffer.  Texture allocation/upload happens
    /// during `MTKView` draw callbacks so we never block the RFB stream
    /// on GPU work.
    ///
    /// `dirtyRectangles` (when non-empty) lets the renderer skip
    /// untouched regions on the GPU upload.  Pass `nil` (or omit) to
    /// force a full-frame upload — appropriate for first frames or any
    /// path that does not have damage tracking from the RFB pump.
    public func enqueue(
        _ framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]? = nil,
        changedPixelCount: Int? = nil
    ) {
        guard framebuffer.width > 0, framebuffer.height > 0 else {
            return
        }
        pendingFramebuffer = framebuffer
        pendingDirtyRectangles = dirtyRectangles
        pendingChangedPixelCount = changedPixelCount.map { max($0, 0) }
        scheduleStagedUploadPreparation(
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount
        )
    }

    /// Clears any visible or pending framebuffer state. Used when the
    /// session frame store emits a disconnect/profile-change clear event so
    /// the imperative Metal host cannot display stale pixels while SwiftUI
    /// is rebuilding back to the placeholder.
    public func clearFramebuffers() {
        cancelStagedUploadPreparation()
        texture = nil
        pendingFramebuffer = nil
        pendingDirtyRectangles = nil
        pendingChangedPixelCount = nil
        pendingStagedUpload = nil
        lastUploadRegionCount = 0
        lastUploadMilliseconds = nil
    }

    /// Updates the local viewport transform used for drawing the
    /// current texture. The main iPhone host keeps this at the stable
    /// aspect-fit baseline and applies touch navigation with a layer
    /// transform, but the renderer path remains available for tests and
    /// fallback projection.
    public func updateViewportTransform(
        zoomScale: CGFloat,
        panOffset: CGSize,
        maxZoomScale: CGFloat = defaultMaximumViewportZoomScale
    ) {
        viewportZoomScale = min(max(zoomScale, 1), max(maxZoomScale, 1))
        viewportMaxZoomScale = max(maxZoomScale, 1)
        viewportPanOffset = panOffset
    }

    /// While the user is pinching or panning, redraws should reproject
    /// the already-uploaded texture only. New incoming VNC frames stay
    /// pending and are uploaded when the gesture settles.
    public func setPendingFramebufferUploadSuspended(_ suspended: Bool) {
        isPendingFramebufferUploadSuspended = suspended
        if !suspended {
            pendingFramebufferUploadSuspensionBypassCount = 0
        }
    }

    /// Allows one pending framebuffer upload to pass through even while
    /// gesture-time upload suspension is active. The viewport host uses this
    /// with its redraw throttle so a long pinch/pan can still sample fresh
    /// VNC frames occasionally instead of freezing until the user lifts.
    public func allowNextPendingFramebufferUploadWhileSuspended() {
        pendingFramebufferUploadSuspensionBypassCount += 1
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
        cancelStagedUploadPreparation()
        return applyPendingFramebuffer()
    }

    @discardableResult
    public func uploadPendingFramebufferRespectingSuspensionForTesting() -> Bool {
        cancelStagedUploadPreparation()
        return applyPendingFramebufferIfAllowed()
    }

    public func stagedUploadByteCountForTesting(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]?,
        changedPixelCount: Int?
    ) -> Int? {
        MetalFramebufferStagedUpload.make(
            device: device,
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount,
            requiresTextureRecreation: texture?.width != framebuffer.width
                || texture?.height != framebuffer.height
        )?.bufferByteCount
    }

    @discardableResult
    public func preparePendingStagedUploadForTesting(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]?,
        changedPixelCount: Int?
    ) -> Bool {
        pendingStagedUpload = MetalFramebufferStagedUpload.make(
            device: device,
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount,
            requiresTextureRecreation: texture?.width != framebuffer.width
                || texture?.height != framebuffer.height
        )
        return pendingStagedUpload != nil
    }

    @discardableResult
    public func applyPendingStagedUploadForTesting() -> Bool {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return false
        }
        let applied = applyPendingStagedUpload(commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return applied
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

    private func scheduleStagedUploadPreparation(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]?,
        changedPixelCount: Int?
    ) {
        stagedUploadGeneration += 1
        latestStagingRequest = MetalFramebufferStagingRequest(
            generation: stagedUploadGeneration,
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount,
            requiresTextureRecreation: texture?.width != framebuffer.width
                || texture?.height != framebuffer.height
        )
        pendingStagedUpload = nil
        guard stagedUploadPreparationTask == nil else {
            return
        }

        let device = SendableMetalDevice(device: device)
        stagedUploadWorkerID += 1
        let workerID = stagedUploadWorkerID
        stagedUploadPreparationTask = Task.detached(priority: .userInitiated) { [weak self, device, workerID] in
            while !Task.isCancelled {
                guard let request = await MainActor.run(body: { [weak self] in
                    self?.takeLatestStagingRequest()
                }) else {
                    let shouldContinue = await MainActor.run { [weak self] in
                        guard let self,
                              self.stagedUploadWorkerID == workerID
                        else {
                            return false
                        }
                        guard self.latestStagingRequest == nil else {
                            return true
                        }
                        self.stagedUploadPreparationTask = nil
                        return false
                    }
                    if shouldContinue {
                        continue
                    }
                    return
                }

                guard let stagedUpload = MetalFramebufferStagedUpload.make(
                    device: device.device,
                    framebuffer: request.framebuffer,
                    dirtyRectangles: request.dirtyRectangles,
                    changedPixelCount: request.changedPixelCount,
                    requiresTextureRecreation: request.requiresTextureRecreation
                ), !Task.isCancelled else {
                    continue
                }

                await MainActor.run { [weak self] in
                    guard !Task.isCancelled,
                          let self,
                          self.stagedUploadWorkerID == workerID,
                          self.stagedUploadGeneration == request.generation
                    else {
                        return
                    }
                    self.pendingStagedUpload = stagedUpload
                    self.stagedUploadReadyHandler?()
                }
            }
        }
    }

    private func cancelStagedUploadPreparation() {
        stagedUploadGeneration += 1
        stagedUploadWorkerID += 1
        stagedUploadPreparationTask?.cancel()
        stagedUploadPreparationTask = nil
        latestStagingRequest = nil
        pendingStagedUpload = nil
    }

    private func takeLatestStagingRequest() -> MetalFramebufferStagingRequest? {
        let request = latestStagingRequest
        latestStagingRequest = nil
        return request
    }

    @discardableResult
    fileprivate func applyPendingFramebuffer() -> Bool {
        guard let framebuffer = pendingFramebuffer else {
            lastUploadMilliseconds = nil
            return false
        }
        let uploadStart = DispatchTime.now().uptimeNanoseconds
        let dirtyRectangles = pendingDirtyRectangles
        let changedPixelCount = pendingChangedPixelCount
        pendingFramebuffer = nil
        pendingDirtyRectangles = nil
        pendingChangedPixelCount = nil
        lastUploadRegionCount = 0
        lastUploadMilliseconds = nil

        // Recreate the texture when dimensions change to avoid a
        // partial-overwrite of a stale-sized texture.  A recreate
        // forces the full-upload path because every pixel of the
        // freshly allocated texture is uninitialized — partial
        // dirty-rect uploads would leave the rest of the texture
        // black.
        let textureWasRecreated: Bool
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
            textureWasRecreated = true
        } else {
            textureWasRecreated = false
        }

        guard let texture else {
            return false
        }

        // RFBColor is laid out as red, green, blue, alpha — RGBA8Unorm
        // matches that ordering byte-for-byte, so we can copy the pixel
        // array directly without per-channel swizzling.
        let bytesPerRow = framebuffer.width * 4

        let validDirtyRectangles = FramebufferUploadPlan.validDirtyRectangles(
            dirtyRectangles,
            textureWidth: texture.width,
            textureHeight: texture.height
        )

        // Decide between the partial dirty-rect path and the full
        // upload path. Many tiny `replaceRegion` calls can cost more
        // driver work than one linear full-frame upload, and a high
        // damage area is effectively a repaint anyway. The threshold is
        // deliberately conservative: use partial uploads for small,
        // localized damage; fall back to one full upload for scattered
        // or mostly-screen updates.
        let uploadPlan = FramebufferUploadPlan.plan(
            framebufferWidth: framebuffer.width,
            framebufferHeight: framebuffer.height,
            dirtyRectangles: validDirtyRectangles,
            requiresTextureRecreation: textureWasRecreated
                || texture.width != framebuffer.width
                || texture.height != framebuffer.height,
            changedPixelCount: changedPixelCount
        )

        framebuffer.pixels.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            let basePointer = baseAddress.assumingMemoryBound(to: UInt8.self)

            if uploadPlan.strategy == .partial {
                for rect in validDirtyRectangles {
                    let sourceOffset = (rect.y * bytesPerRow) + (rect.x * 4)
                    let sourcePointer = basePointer.advanced(by: sourceOffset)
                    texture.replace(
                        region: MTLRegionMake2D(rect.x, rect.y, rect.width, rect.height),
                        mipmapLevel: 0,
                        withBytes: sourcePointer,
                        bytesPerRow: bytesPerRow
                    )
                    lastUploadRegionCount += 1
                }
            } else {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, framebuffer.width, framebuffer.height),
                    mipmapLevel: 0,
                    withBytes: basePointer,
                    bytesPerRow: bytesPerRow
                )
                lastUploadRegionCount = 1
            }
        }
        recordSuccessfulUploadTiming(startedAt: uploadStart)
        return true
    }

    private func recordSuccessfulUploadTiming(
        startedAt start: UInt64,
        additionalMilliseconds: Int = 0
    ) {
        let end = DispatchTime.now().uptimeNanoseconds
        let elapsedNanoseconds = end >= start ? end - start : 0
        let milliseconds = max(
            0,
            additionalMilliseconds + Int((Double(elapsedNanoseconds) / 1_000_000.0).rounded())
        )
        lastUploadMilliseconds = milliseconds
        uploadTimingHandler?(milliseconds)
    }

    fileprivate func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }
        applyPendingStagedUploadIfAllowed(commandBuffer: commandBuffer)

        guard let texture,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            commandBuffer.commit()
            return
        }

        let fullViewport = MTLViewport(
            originX: 0,
            originY: 0,
            width: view.drawableSize.width,
            height: view.drawableSize.height,
            znear: 0,
            zfar: 1
        )
        let contentViewport = Self.transformedViewport(
            drawableSize: view.drawableSize,
            viewSize: view.bounds.size,
            textureWidth: texture.width,
            textureHeight: texture.height,
            zoomScale: viewportZoomScale,
            panOffset: viewportPanOffset,
            maxZoomScale: viewportMaxZoomScale
        )
        var uniforms = Self.renderUniforms(
            contentViewport: contentViewport,
            drawableSize: view.drawableSize
        )
        encoder.setViewport(fullViewport)
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<ViewportRenderUniforms>.stride,
            index: 0
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    @discardableResult
    private func applyPendingFramebufferIfAllowed() -> Bool {
        if isPendingFramebufferUploadSuspended {
            guard pendingFramebufferUploadSuspensionBypassCount > 0 else {
                lastUploadMilliseconds = nil
                return false
            }
            pendingFramebufferUploadSuspensionBypassCount -= 1
        }
        return applyPendingFramebuffer()
    }

    @discardableResult
    private func applyPendingStagedUploadIfAllowed(commandBuffer: MTLCommandBuffer) -> Bool {
        if isPendingFramebufferUploadSuspended {
            guard pendingFramebufferUploadSuspensionBypassCount > 0 else {
                lastUploadMilliseconds = nil
                return false
            }
            pendingFramebufferUploadSuspensionBypassCount -= 1
        }
        return applyPendingStagedUpload(commandBuffer: commandBuffer)
    }

    @discardableResult
    private func applyPendingStagedUpload(commandBuffer: MTLCommandBuffer) -> Bool {
        guard let stagedUpload = pendingStagedUpload else {
            lastUploadMilliseconds = nil
            return false
        }
        let uploadStart = DispatchTime.now().uptimeNanoseconds
        pendingStagedUpload = nil
        pendingFramebuffer = nil
        pendingDirtyRectangles = nil
        pendingChangedPixelCount = nil
        lastUploadRegionCount = 0
        lastUploadMilliseconds = nil

        if case .partial = stagedUpload.storage,
           (texture?.width != stagedUpload.width || texture?.height != stagedUpload.height) {
            return false
        }

        if texture?.width != stagedUpload.width || texture?.height != stagedUpload.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: stagedUpload.width,
                height: stagedUpload.height,
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

        switch stagedUpload.storage {
        case .partial(let regions):
            for region in regions {
                let rect = region.rectangle
                region.bytes.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress else {
                        return
                    }
                    texture.replace(
                        region: MTLRegionMake2D(rect.x, rect.y, rect.width, rect.height),
                        mipmapLevel: 0,
                        withBytes: baseAddress,
                        bytesPerRow: region.bytesPerRow
                    )
                }
                lastUploadRegionCount += 1
            }
        case .full(let buffer, let bytesPerRow):
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                return false
            }
            blitEncoder.copy(
                from: buffer,
                sourceOffset: 0,
                sourceBytesPerRow: bytesPerRow,
                sourceBytesPerImage: bytesPerRow * stagedUpload.height,
                sourceSize: MTLSize(width: stagedUpload.width, height: stagedUpload.height, depth: 1),
                to: texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
            lastUploadRegionCount = 1
        }
        recordSuccessfulUploadTiming(
            startedAt: uploadStart,
            additionalMilliseconds: stagedUpload.preparationMilliseconds
        )
        return true
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

    static func transformedViewport(
        drawableSize: CGSize,
        viewSize: CGSize,
        textureWidth: Int,
        textureHeight: Int,
        zoomScale: CGFloat,
        panOffset: CGSize,
        maxZoomScale: CGFloat = defaultMaximumViewportZoomScale
    ) -> MTLViewport {
        guard drawableSize.width > 0,
              drawableSize.height > 0,
              viewSize.width > 0,
              viewSize.height > 0,
              textureWidth > 0,
              textureHeight > 0
        else {
            return MTLViewport(originX: 0, originY: 0, width: 0, height: 0, znear: 0, zfar: 1)
        }

        let transform = ViewportTransform(
            framebufferSize: CGSize(width: textureWidth, height: textureHeight),
            viewSize: viewSize,
            zoomScale: zoomScale,
            panOffset: panOffset,
            maxZoomScale: maxZoomScale
        )
        let scaleX = drawableSize.width / viewSize.width
        let scaleY = drawableSize.height / viewSize.height
        let origin = transform.contentOrigin
        let size = transform.contentSize
        return MTLViewport(
            originX: origin.x * scaleX,
            originY: origin.y * scaleY,
            width: size.width * scaleX,
            height: size.height * scaleY,
            znear: 0,
            zfar: 1
        )
    }

    private static func renderUniforms(
        contentViewport: MTLViewport,
        drawableSize: CGSize
    ) -> ViewportRenderUniforms {
        guard drawableSize.width > 0,
              drawableSize.height > 0,
              contentViewport.width > 0,
              contentViewport.height > 0
        else {
            return ViewportRenderUniforms(left: 0, right: 0, top: 0, bottom: 0)
        }

        let left = (contentViewport.originX / drawableSize.width) * 2 - 1
        let right = ((contentViewport.originX + contentViewport.width) / drawableSize.width) * 2 - 1
        let top = 1 - (contentViewport.originY / drawableSize.height) * 2
        let bottom = 1 - ((contentViewport.originY + contentViewport.height) / drawableSize.height) * 2
        return ViewportRenderUniforms(
            left: Float(left),
            right: Float(right),
            top: Float(top),
            bottom: Float(bottom)
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

    struct ViewportUniforms {
        float left;
        float right;
        float top;
        float bottom;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut naruRemoteFullscreenVertex(
        uint vertexId [[vertex_id]],
        constant ViewportUniforms& viewport [[buffer(0)]]
    ) {
        const ushort corners[6] = {
            0, 2, 1,
            1, 2, 3
        };
        const ushort corner = corners[vertexId];
        const float2 positions[4] = {
            float2(viewport.left,  viewport.top),
            float2(viewport.right, viewport.top),
            float2(viewport.left,  viewport.bottom),
            float2(viewport.right, viewport.bottom)
        };
        const float2 uvs[4] = {
            float2(0.0, 0.0),
            float2(1.0, 0.0),
            float2(0.0, 1.0),
            float2(1.0, 1.0)
        };
        VertexOut out;
        out.position = float4(positions[corner], 0.0, 1.0);
        out.uv = uvs[corner];
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
