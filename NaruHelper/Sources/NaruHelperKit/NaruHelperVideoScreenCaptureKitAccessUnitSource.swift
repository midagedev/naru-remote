import Foundation
import NaruRemoteCore

public enum NaruHelperVideoScreenCaptureKitAccessUnitSourceError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case screenRecordingPermissionMissing
    case captureSourceUnavailable
    case captureTimedOut
    case captureFailed
    case capturedFrameMissingImageBuffer
    case noCapturedFrames
}

#if os(macOS) && canImport(CoreGraphics) && canImport(CoreMedia) && canImport(CoreVideo) && canImport(ScreenCaptureKit) && canImport(VideoToolbox)
@preconcurrency import CoreGraphics
@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
@preconcurrency import ScreenCaptureKit
import VideoToolbox

public protocol NaruHelperVideoScreenCaptureKitPixelBufferProvider: Sendable {
    func pixelBuffers(
        frameLimit: Int,
        frameRateBucket: HelperVideoFrameRateBucket
    ) throws -> [CVPixelBuffer]
}

public struct NaruHelperVideoScreenCaptureKitAccessUnitSource: NaruHelperVideoAccessUnitSource {
    public var frameCount: Int
    private let pixelBufferProvider: any NaruHelperVideoScreenCaptureKitPixelBufferProvider

    public init(frameCount: Int = 2) {
        self.init(
            frameCount: frameCount,
            pixelBufferProvider: LiveNaruHelperVideoScreenCaptureKitPixelBufferProvider()
        )
    }

    public init(
        frameCount: Int = 2,
        pixelBufferProvider: any NaruHelperVideoScreenCaptureKitPixelBufferProvider
    ) {
        self.frameCount = max(frameCount, 1)
        self.pixelBufferProvider = pixelBufferProvider
    }

    public func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        let pixelBuffers = try pixelBufferProvider.pixelBuffers(
            frameLimit: frameCount,
            frameRateBucket: request.maxFrameRateBucket
        )
        guard let first = pixelBuffers.first else {
            throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError.noCapturedFrames
        }

        let width = Int32(CVPixelBufferGetWidth(first))
        let height = Int32(CVPixelBufferGetHeight(first))
        guard width > 0, height > 0 else {
            throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError
                .capturedFrameMissingImageBuffer
        }

        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: width,
            height: height,
            frameRateBucket: request.maxFrameRateBucket,
            keyFrameInterval: frameCount,
            encodingMode: .lowLatencyRealtime
        )
        return try encoder.encode(pixelBuffers: pixelBuffers)
    }
}

private struct LiveNaruHelperVideoScreenCaptureKitPixelBufferProvider:
    NaruHelperVideoScreenCaptureKitPixelBufferProvider
{
    func pixelBuffers(
        frameLimit: Int,
        frameRateBucket: HelperVideoFrameRateBucket
    ) throws -> [CVPixelBuffer] {
        guard CGPreflightScreenCaptureAccess() else {
            throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError
                .screenRecordingPermissionMissing
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LiveNaruHelperVideoScreenCaptureKitResultBox<[CapturedPixelBuffer]>()
        Task.detached {
            do {
                let captured = try await LiveNaruHelperVideoScreenCaptureKitFiniteCapture(
                    frameLimit: frameLimit,
                    frameRateBucket: frameRateBucket
                ).capture()
                resultBox.store(.success(captured))
            } catch {
                resultBox.store(.failure(error))
            }
            semaphore.signal()
        }

        let providerTimeout = frameRateBucket.screenCaptureProviderTimeout(
            frameLimit: frameLimit
        )
        guard semaphore.wait(timeout: .now() + providerTimeout) == .success else {
            throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError.captureTimedOut
        }
        return try resultBox.value().get().map(\.pixelBuffer)
    }
}

private struct LiveNaruHelperVideoScreenCaptureKitFiniteCapture {
    var frameLimit: Int
    var frameRateBucket: HelperVideoFrameRateBucket

    func capture() async throws -> [CapturedPixelBuffer] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError
                .captureSourceUnavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = max(display.width, 1)
        configuration.height = max(display.height, 1)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = frameRateBucket.screenCaptureMinimumFrameInterval
        configuration.capturesAudio = false
        configuration.showsCursor = true

        let collector = LiveNaruHelperVideoScreenCaptureKitFrameCollector(
            frameLimit: max(frameLimit, 1)
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: collector)
        try stream.addStreamOutput(
            collector,
            type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "com.naruremote.helper-video-sck-output")
        )
        try await Self.start(stream)

        do {
            let frames = try collector.waitForFrames(
                timeout: frameRateBucket.screenCaptureFrameCollectionTimeout(
                    frameLimit: frameLimit
                )
            )
            try await Self.stop(stream)
            return frames
        } catch {
            try? await Self.stop(stream)
            throw error
        }
    }

    private static func start(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func stop(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private final class LiveNaruHelperVideoScreenCaptureKitFrameCollector:
    NSObject,
    SCStreamOutput,
    SCStreamDelegate,
    @unchecked Sendable
{
    private let frameLimit: Int
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var frames: [CapturedPixelBuffer] = []
    private var stoppedWithError = false

    init(frameLimit: Int) {
        self.frameLimit = max(frameLimit, 1)
    }

    func waitForFrames(timeout: TimeInterval) throws -> [CapturedPixelBuffer] {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError.captureTimedOut
        }
        return try lock.withLock {
            if stoppedWithError {
                throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError.captureFailed
            }
            guard !frames.isEmpty else {
                throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError.noCapturedFrames
            }
            return frames
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              Self.isDisplayableScreenFrame(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        lock.withLock {
            guard frames.count < frameLimit else {
                return
            }
            frames.append(CapturedPixelBuffer(pixelBuffer: imageBuffer))
            if frames.count >= frameLimit {
                semaphore.signal()
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.withLock {
            stoppedWithError = true
        }
        semaphore.signal()
    }

    private static func isDisplayableScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let first = attachments.first,
              let rawStatus = first[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus)
        else {
            return true
        }

        return status == .complete || status == .started
    }
}

private struct CapturedPixelBuffer: @unchecked Sendable {
    var pixelBuffer: CVPixelBuffer
}

private final class LiveNaruHelperVideoScreenCaptureKitResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func store(_ result: Result<T, Error>) {
        lock.withLock {
            self.result = result
        }
    }

    func value() throws -> Result<T, Error> {
        try lock.withLock {
            guard let result else {
                throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError.captureFailed
            }
            return result
        }
    }
}

extension HelperVideoFrameRateBucket {
    var screenCaptureMinimumFrameInterval: CMTime {
        CMTime(value: 1, timescale: nominalFrameRate)
    }

    func screenCaptureFrameCollectionTimeout(frameLimit: Int) -> TimeInterval {
        let expectedFrameSeconds = Double(max(frameLimit, 1)) / Double(nominalFrameRate)
        return min(max(expectedFrameSeconds + 2.0, 3.0), 10.0)
    }

    func screenCaptureProviderTimeout(frameLimit: Int) -> TimeInterval {
        min(screenCaptureFrameCollectionTimeout(frameLimit: frameLimit) + 2.0, 12.0)
    }

    private var nominalFrameRate: CMTimeScale {
        switch self {
        case .unknown:
            return 30
        case .upTo15:
            return 15
        case .upTo30:
            return 30
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
#else
public struct NaruHelperVideoScreenCaptureKitAccessUnitSource: NaruHelperVideoAccessUnitSource {
    public init(frameCount: Int = 2) {}

    public func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError.unsupportedPlatform
    }
}
#endif
