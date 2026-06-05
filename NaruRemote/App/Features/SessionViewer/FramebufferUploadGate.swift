import NaruRemoteCore

struct FramebufferUploadGate {
    private var lastUploadSignature: FramebufferUploadSignature?

    mutating func reset() {
        lastUploadSignature = nil
    }

    mutating func shouldEnqueue(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]? = nil,
        changedPixelCount: Int? = nil
    ) -> Bool {
        let signature = FramebufferUploadSignature(
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount
        )
        guard signature != lastUploadSignature else {
            return false
        }
        lastUploadSignature = signature
        return true
    }
}

private struct FramebufferUploadSignature: Equatable {
    let width: Int
    let height: Int
    let pixelCount: Int
    let pixelStorageAddress: UInt
    let dirtyRectangles: [RFBFrameDamageRect]?
    let changedPixelCount: Int?

    init(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]?,
        changedPixelCount: Int?
    ) {
        self.width = framebuffer.width
        self.height = framebuffer.height
        self.pixelCount = framebuffer.pixels.count
        self.pixelStorageAddress = framebuffer.pixels.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return 0
            }
            return UInt(bitPattern: baseAddress)
        }
        self.dirtyRectangles = dirtyRectangles
        self.changedPixelCount = changedPixelCount.map { max($0, 0) }
    }
}
