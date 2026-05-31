import CoreGraphics
import NaruRemoteCore

public struct PiPWatchSourceRect: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = max(x, 0)
        self.y = max(y, 0)
        self.width = max(width, 0)
        self.height = max(height, 0)
    }
}

/// Watch-only local focus for PiP video frames.
///
/// `centerX` / `centerY` are normalized framebuffer coordinates in
/// `[0, 1]`, and `zoomScale` is the same local zoom multiplier the
/// session viewport uses.  This type never represents remote input.
public struct PiPWatchViewport: Equatable, Sendable {
    public static let fullFrame = PiPWatchViewport()
    public static let maximumZoomScale: Double = 4

    public let centerX: Double
    public let centerY: Double
    public let zoomScale: Double

    public init(
        centerX: Double = 0.5,
        centerY: Double = 0.5,
        zoomScale: Double = 1
    ) {
        self.centerX = Self.clampedUnit(centerX)
        self.centerY = Self.clampedUnit(centerY)
        self.zoomScale = min(max(zoomScale, 1), Self.maximumZoomScale)
    }

    public init(transform: ViewportTransform) {
        let center = CGPoint(
            x: transform.viewSize.width / 2,
            y: transform.viewSize.height / 2
        )
        let framebufferCenter = transform.framebufferPoint(fromViewPoint: center)
            ?? CGPoint(
                x: max(transform.framebufferSize.width - 1, 0) / 2,
                y: max(transform.framebufferSize.height - 1, 0) / 2
            )
        let widthDenominator = max(Double(transform.framebufferSize.width - 1), 1)
        let heightDenominator = max(Double(transform.framebufferSize.height - 1), 1)
        self.init(
            centerX: Double(framebufferCenter.x) / widthDenominator,
            centerY: Double(framebufferCenter.y) / heightDenominator,
            zoomScale: Double(transform.zoomScale)
        )
    }

    public func sourceRect(framebufferWidth width: Int, height: Int) -> PiPWatchSourceRect {
        guard width > 0, height > 0 else {
            return PiPWatchSourceRect(x: 0, y: 0, width: 0, height: 0)
        }

        let cropWidth = max(1, min(width, Int((Double(width) / zoomScale).rounded())))
        let cropHeight = max(1, min(height, Int((Double(height) / zoomScale).rounded())))
        let centerPixelX = centerX * Double(max(width - 1, 0))
        let centerPixelY = centerY * Double(max(height - 1, 0))
        let rawOriginX = Int(
            (centerPixelX - Double(cropWidth - 1) / 2).rounded(.toNearestOrAwayFromZero)
        )
        let rawOriginY = Int(
            (centerPixelY - Double(cropHeight - 1) / 2).rounded(.toNearestOrAwayFromZero)
        )
        let originX = min(max(rawOriginX, 0), max(width - cropWidth, 0))
        let originY = min(max(rawOriginY, 0), max(height - cropHeight, 0))

        return PiPWatchSourceRect(x: originX, y: originY, width: cropWidth, height: cropHeight)
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0.5
        }
        return min(max(value, 0), 1)
    }
}

@MainActor
public protocol PiPWatchControlling: AnyObject {
    var isSupported: Bool { get }

    @discardableResult
    func prepare() -> Bool
    func enqueue(_ framebuffer: RFBRawFramebuffer) throws
    func enqueue(_ framebuffer: RFBRawFramebuffer, viewport: PiPWatchViewport) throws
    @discardableResult
    func start() -> Bool
    func stop()
}

public extension PiPWatchControlling {
    func enqueue(_ framebuffer: RFBRawFramebuffer, viewport: PiPWatchViewport) throws {
        try enqueue(framebuffer)
    }
}

#if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import AVFoundation
import CoreMedia
import CoreVideo
#if os(iOS) && canImport(AVKit) && canImport(UIKit)
import AVKit
import UIKit
#endif

/// Capability protocol for `PiPWatchControlling` implementations that
/// support being attached to a long-lived `PiPLayerHost`.  The host's
/// `AVSampleBufferDisplayLayer` is mounted in the SwiftUI view tree and
/// becomes the single shared sink for streaming frames; both the
/// hosted view and the system PiP controller render from the same
/// layer instance to avoid double rendering.
@MainActor
public protocol PiPWatchLayerHostAttaching: PiPWatchControlling {
    @discardableResult
    func prepare(layerHost: PiPLayerHost) -> Bool
}

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

    public func makePixelBuffer(
        from framebuffer: RFBRawFramebuffer,
        viewport: PiPWatchViewport = .fullFrame
    ) throws -> CVPixelBuffer {
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

        try write(framebuffer: framebuffer, viewport: viewport, into: pixelBuffer)
        return pixelBuffer
    }

    public func makeSampleBuffer(
        from framebuffer: RFBRawFramebuffer,
        viewport: PiPWatchViewport = .fullFrame,
        presentationTime: CMTime,
        duration: CMTime = CMTime(value: 1, timescale: 12)
    ) throws -> CMSampleBuffer {
        let pixelBuffer = try makePixelBuffer(from: framebuffer, viewport: viewport)
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

    private func write(
        framebuffer: RFBRawFramebuffer,
        viewport: PiPWatchViewport,
        into pixelBuffer: CVPixelBuffer
    ) throws {
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
        let sourceRect = viewport.sourceRect(framebufferWidth: framebuffer.width, height: framebuffer.height)
        let sourceColumns = (0..<framebuffer.width).map { x in
            sourceRect.x + min(
                sourceRect.width - 1,
                Int(Double(x) * Double(sourceRect.width) / Double(framebuffer.width))
            )
        }
        let sourceRows = (0..<framebuffer.height).map { y in
            sourceRect.y + min(
                sourceRect.height - 1,
                Int(Double(y) * Double(sourceRect.height) / Double(framebuffer.height))
            )
        }

        for y in 0..<framebuffer.height {
            let sourceY = sourceRows[y]
            let sourceRowBase = sourceY * framebuffer.width
            for x in 0..<framebuffer.width {
                let color = framebuffer.pixels[sourceRowBase + sourceColumns[x]]

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
    public func enqueue(
        _ framebuffer: RFBRawFramebuffer,
        viewport: PiPWatchViewport = .fullFrame
    ) throws -> CMSampleBuffer {
        if displayLayer.status == .failed {
            displayLayer.flushAndRemoveImage()
        }

        let sampleBuffer = try factory.makeSampleBuffer(
            from: framebuffer,
            viewport: viewport,
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
public final class PiPWatchPictureInPictureController: NSObject, PiPWatchControlling, PiPWatchLayerHostAttaching {
    public private(set) var layerHost: PiPLayerHost?
    public private(set) var pictureInPictureController: AVPictureInPictureController?
    private let fallbackRenderer: PiPWatchSampleBufferRenderer

    public init(renderer: PiPWatchSampleBufferRenderer = PiPWatchSampleBufferRenderer()) {
        self.fallbackRenderer = renderer
        super.init()
    }

    public var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// Backwards-compatible no-host preparation.  Builds the controller
    /// against the fallback renderer's display layer; the host-aware
    /// overload `prepare(layerHost:)` should be preferred so the shared
    /// in-app layer is the single source.
    @discardableResult
    public func prepare() -> Bool {
        guard isSupported else {
            pictureInPictureController = nil
            return false
        }

        activateAudioSessionForPiP()

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: fallbackRenderer.displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = true
        pictureInPictureController = controller
        return true
    }

    /// Attach the controller to a live `PiPLayerHost`.  The hosted
    /// layer is mounted in the SwiftUI view tree by
    /// `PiPSampleBufferDisplayLayerView`, which is the lifecycle PiP
    /// requires.  Frames are written through `layerHost.enqueue(_:)`,
    /// so the controller does not own a separate renderer.
    @discardableResult
    public func prepare(layerHost: PiPLayerHost) -> Bool {
        self.layerHost = layerHost

        guard isSupported else {
            pictureInPictureController = nil
            return false
        }

        activateAudioSessionForPiP()

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layerHost.layer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = true
        pictureInPictureController = controller
        return true
    }

    public func enqueue(_ framebuffer: RFBRawFramebuffer) throws {
        try enqueue(framebuffer, viewport: .fullFrame)
    }

    public func enqueue(_ framebuffer: RFBRawFramebuffer, viewport: PiPWatchViewport) throws {
        // When an in-app `PiPLayerHost` is attached the model writes
        // streamed frames into the host directly so the SwiftUI viewport
        // and the AVPictureInPictureController content source share a
        // single sink — skipping the redundant render here is what
        // prevents double encoding.  Without an attached host, retain
        // the legacy behavior of rendering through the fallback renderer.
        if layerHost == nil {
            _ = try fallbackRenderer.enqueue(framebuffer, viewport: viewport)
        }
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
        deactivateAudioSessionAfterPiP()
    }

    /// Best-effort audio-session activation so PiP keeps streaming
    /// frames after the app moves to the background.  Naru does not
    /// produce audio, so `mixWithOthers` ensures we never duck or
    /// stomp on whatever the user is already playing.  Failures are
    /// swallowed: PiP still works in the foreground without an
    /// active session, and a backgrounded device that refused
    /// activation would surface as the existing PiP-stops behavior.
    private func activateAudioSessionForPiP() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }

    private func deactivateAudioSessionAfterPiP() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
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
