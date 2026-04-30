import NaruRemoteCore

@MainActor
public protocol PiPWatchControlling: AnyObject {
    var isSupported: Bool { get }

    @discardableResult
    func prepare() -> Bool
    func enqueue(_ framebuffer: RFBRawFramebuffer) throws
    @discardableResult
    func start() -> Bool
    func stop()
}

#if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import AVFoundation
import CoreMedia
import CoreVideo
#if os(iOS) && canImport(AVKit) && canImport(UIKit)
import AVKit
import UIKit
#endif

public enum PiPWatchSampleBufferRendererError: Error, Equatable, LocalizedError {
    case unrenderableFramebuffer(width: Int, height: Int)
    case pixelBufferCreationFailed
    case pixelBufferLockFailed(CVReturn)
    case pixelBufferBaseAddressUnavailable
    case formatDescriptionCreationFailed(OSStatus)
    case sampleBufferCreationFailed(OSStatus)
    case displayLayerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unrenderableFramebuffer(let width, let height):
            return "PiP framebuffer cannot be rendered at \(width)x\(height)."
        case .pixelBufferCreationFailed:
            return "PiP pixel buffer could not be created."
        case .pixelBufferLockFailed(let status):
            return "PiP pixel buffer memory could not be locked with status \(status)."
        case .pixelBufferBaseAddressUnavailable:
            return "PiP pixel buffer memory is unavailable."
        case .formatDescriptionCreationFailed(let status):
            return "PiP video format description failed with status \(status)."
        case .sampleBufferCreationFailed(let status):
            return "PiP sample buffer failed with status \(status)."
        case .displayLayerFailed(let message):
            return "PiP display layer failed: \(message)"
        }
    }
}

public final class PiPWatchSampleBufferFactory {
    public init() {}

    public func makePixelBuffer(from framebuffer: RFBRawFramebuffer) throws -> CVPixelBuffer {
        guard framebuffer.width > 0, framebuffer.height > 0 else {
            throw PiPWatchSampleBufferRendererError.unrenderableFramebuffer(
                width: framebuffer.width,
                height: framebuffer.height
            )
        }

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            framebuffer.width,
            framebuffer.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw PiPWatchSampleBufferRendererError.pixelBufferCreationFailed
        }

        try write(framebuffer: framebuffer, into: pixelBuffer)
        return pixelBuffer
    }

    public func makeSampleBuffer(
        from framebuffer: RFBRawFramebuffer,
        presentationTime: CMTime,
        duration: CMTime = CMTime(value: 1, timescale: 12)
    ) throws -> CMSampleBuffer {
        let pixelBuffer = try makePixelBuffer(from: framebuffer)
        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )

        guard formatStatus == noErr, let formatDescription else {
            throw PiPWatchSampleBufferRendererError.formatDescriptionCreationFailed(formatStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sampleBuffer else {
            throw PiPWatchSampleBufferRendererError.sampleBufferCreationFailed(sampleStatus)
        }

        return sampleBuffer
    }

    private func write(framebuffer: RFBRawFramebuffer, into pixelBuffer: CVPixelBuffer) throws {
        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard lockStatus == kCVReturnSuccess else {
            throw PiPWatchSampleBufferRendererError.pixelBufferLockFailed(lockStatus)
        }

        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw PiPWatchSampleBufferRendererError.pixelBufferBaseAddressUnavailable
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<framebuffer.height {
            for x in 0..<framebuffer.width {
                guard let color = framebuffer[x, y] else {
                    continue
                }

                let offset = y * bytesPerRow + x * 4
                pointer[offset] = color.blue
                pointer[offset + 1] = color.green
                pointer[offset + 2] = color.red
                pointer[offset + 3] = color.alpha
            }
        }
    }
}

public final class PiPWatchSampleBufferRenderer {
    public let displayLayer: AVSampleBufferDisplayLayer
    private let factory: PiPWatchSampleBufferFactory
    private var frameIndex: Int64 = 0
    private let timescale: CMTimeScale

    public init(
        displayLayer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer(),
        factory: PiPWatchSampleBufferFactory = PiPWatchSampleBufferFactory(),
        timescale: CMTimeScale = 12
    ) {
        self.displayLayer = displayLayer
        self.factory = factory
        self.timescale = timescale
        self.displayLayer.videoGravity = .resizeAspect
    }

    @discardableResult
    public func enqueue(_ framebuffer: RFBRawFramebuffer) throws -> CMSampleBuffer {
        if displayLayer.status == .failed {
            displayLayer.flushAndRemoveImage()
        }

        let sampleBuffer = try factory.makeSampleBuffer(
            from: framebuffer,
            presentationTime: CMTime(value: frameIndex, timescale: timescale),
            duration: CMTime(value: 1, timescale: timescale)
        )
        frameIndex += 1
        displayLayer.enqueue(sampleBuffer)
        if displayLayer.status == .failed {
            throw PiPWatchSampleBufferRendererError.displayLayerFailed(
                displayLayer.error?.localizedDescription ?? "Unknown display layer error."
            )
        }
        return sampleBuffer
    }

    public func flush() {
        frameIndex = 0
        displayLayer.flush()
    }
}

#if os(iOS) && canImport(AVKit) && canImport(UIKit)
@MainActor
public final class PiPWatchPictureInPictureController: NSObject, PiPWatchControlling {
    public let renderer: PiPWatchSampleBufferRenderer
    public private(set) var pictureInPictureController: AVPictureInPictureController?

    public init(renderer: PiPWatchSampleBufferRenderer = PiPWatchSampleBufferRenderer()) {
        self.renderer = renderer
        super.init()
    }

    public var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    @discardableResult
    public func prepare() -> Bool {
        guard isSupported else {
            pictureInPictureController = nil
            return false
        }

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: renderer.displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = true
        pictureInPictureController = controller
        return true
    }

    public func enqueue(_ framebuffer: RFBRawFramebuffer) throws {
        _ = try renderer.enqueue(framebuffer)
        pictureInPictureController?.invalidatePlaybackState()
    }

    @discardableResult
    public func start() -> Bool {
        if pictureInPictureController == nil {
            _ = prepare()
        }

        guard let pictureInPictureController else {
            return false
        }

        pictureInPictureController.startPictureInPicture()
        return true
    }

    public func stop() {
        pictureInPictureController?.stopPictureInPicture()
    }
}

extension PiPWatchPictureInPictureController: @MainActor AVPictureInPictureControllerDelegate {}

extension PiPWatchPictureInPictureController: @MainActor AVPictureInPictureSampleBufferPlaybackDelegate {
    public func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(
            start: .zero,
            duration: CMTime(value: Int64.max, timescale: 1)
        )
    }

    public func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {}

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
#endif
#endif
