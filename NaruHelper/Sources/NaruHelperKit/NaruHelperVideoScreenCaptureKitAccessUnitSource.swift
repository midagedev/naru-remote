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

public protocol NaruHelperVideoScreenCaptureKitPixelBufferStreamProvider:
    NaruHelperVideoScreenCaptureKitPixelBufferProvider
{
    func pixelBufferStream(
        frameLimit: Int?,
        frameRateBucket: HelperVideoFrameRateBucket
    ) throws -> AsyncThrowingStream<CVPixelBuffer, any Error>
}

public struct NaruHelperVideoScreenCaptureKitAccessUnitSource: NaruHelperVideoAccessUnitSource {
    /// A value of `0` means an unbounded stream for `accessUnitStream(...)`.
    /// The legacy finite `accessUnits(...)` API still captures at least one
    /// frame for smoke tests and fixture callers.
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
        self.frameCount = max(frameCount, 0)
        self.pixelBufferProvider = pixelBufferProvider
    }

    public func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        let finiteFrameCount = max(frameCount, 1)
        let pixelBuffers = try pixelBufferProvider.pixelBuffers(
            frameLimit: finiteFrameCount,
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
            qualityBucket: request.qualityBucket,
            keyFrameInterval: finiteFrameCount,
            encodingMode: .lowLatencyRealtime
        )
        return try encoder.encode(pixelBuffers: pixelBuffers)
    }

    public func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        guard let streamProvider = pixelBufferProvider
            as? any NaruHelperVideoScreenCaptureKitPixelBufferStreamProvider
        else {
            return try NaruHelperVideoAccessUnitSourceDefaultStreamAdapter
                .stream(source: self, request: request)
        }

        let pixelBufferStream = try streamProvider.pixelBufferStream(
            frameLimit: frameCount > 0 ? frameCount : nil,
            frameRateBucket: request.maxFrameRateBucket
        )
        let pixelBufferStreamBox = LiveNaruHelperVideoScreenCaptureKitPixelBufferStreamBox(
            stream: pixelBufferStream
        )
        return AsyncThrowingStream { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                do {
                    let iteratorBox = LiveNaruHelperVideoScreenCaptureKitPixelBufferIteratorBox(
                        stream: pixelBufferStreamBox.stream
                    )
                    guard let first = try await iteratorBox.next() else {
                        continuation.finish(
                            throwing: NaruHelperVideoScreenCaptureKitAccessUnitSourceError
                                .noCapturedFrames
                        )
                        return
                    }

                    let width = Int32(CVPixelBufferGetWidth(first))
                    let height = Int32(CVPixelBufferGetHeight(first))
                    guard width > 0, height > 0 else {
                        throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError
                            .capturedFrameMissingImageBuffer
                    }
                    let firstBox = LiveNaruHelperVideoScreenCaptureKitPixelBufferBox(
                        pixelBuffer: first
                    )

                    let replayedPixelBuffers: AsyncThrowingStream<CVPixelBuffer, any Error>
                    if frameCount > 0 {
                        replayedPixelBuffers = AsyncThrowingStream { replayContinuation in
                            Self.startReplay(
                                firstBox: firstBox,
                                iteratorBox: iteratorBox,
                                replayContinuation: replayContinuation
                            )
                        }
                    } else {
                        replayedPixelBuffers = AsyncThrowingStream(
                            bufferingPolicy: .bufferingNewest(1)
                        ) { replayContinuation in
                            Self.startReplay(
                                firstBox: firstBox,
                                iteratorBox: iteratorBox,
                                replayContinuation: replayContinuation
                            )
                        }
                    }

                    let keyFrameInterval = frameCount > 0
                        ? frameCount
                        : max(Int(request.maxFrameRateBucket.nominalFrameRate) * 2, 30)
                    let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
                        width: width,
                        height: height,
                        frameRateBucket: request.maxFrameRateBucket,
                        qualityBucket: request.qualityBucket,
                        keyFrameInterval: keyFrameInterval,
                        encodingMode: .lowLatencyRealtime
                    )
                    let accessUnits = try encoder.encode(pixelBuffers: replayedPixelBuffers)
                    for try await accessUnit in accessUnits {
                        try Task.checkCancellation()
                        continuation.yield(accessUnit)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
    }

    private static func startReplay(
        firstBox: LiveNaruHelperVideoScreenCaptureKitPixelBufferBox,
        iteratorBox: LiveNaruHelperVideoScreenCaptureKitPixelBufferIteratorBox,
        replayContinuation: AsyncThrowingStream<CVPixelBuffer, any Error>.Continuation
    ) {
        let replayProducer = Task.detached(priority: .userInitiated) {
            do {
                nonisolated(unsafe) let transferableFirst = firstBox.pixelBuffer
                replayContinuation.yield(transferableFirst)
                while let next = try await iteratorBox.next() {
                    try Task.checkCancellation()
                    nonisolated(unsafe) let transferableNext = next
                    replayContinuation.yield(transferableNext)
                }
                replayContinuation.finish()
            } catch is CancellationError {
                replayContinuation.finish()
            } catch {
                replayContinuation.finish(throwing: error)
            }
        }
        replayContinuation.onTermination = { _ in
            replayProducer.cancel()
        }
    }
}

private struct LiveNaruHelperVideoScreenCaptureKitPixelBufferProvider:
    NaruHelperVideoScreenCaptureKitPixelBufferStreamProvider
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

    func pixelBufferStream(
        frameLimit: Int?,
        frameRateBucket: HelperVideoFrameRateBucket
    ) throws -> AsyncThrowingStream<CVPixelBuffer, any Error> {
        guard CGPreflightScreenCaptureAccess() else {
            throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError
                .screenRecordingPermissionMissing
        }

        return AsyncThrowingStream { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                do {
                    let capture = LiveNaruHelperVideoScreenCaptureKitStreamingCapture(
                        frameLimit: frameLimit,
                        frameRateBucket: frameRateBucket,
                        continuation: continuation
                    )
                    try await capture.captureUntilFinished()
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
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

    fileprivate static func start(_ stream: SCStream) async throws {
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

    fileprivate static func stop(_ stream: SCStream) async throws {
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

private struct LiveNaruHelperVideoScreenCaptureKitStreamingCapture {
    var frameLimit: Int?
    var frameRateBucket: HelperVideoFrameRateBucket
    let continuation: AsyncThrowingStream<CVPixelBuffer, any Error>.Continuation

    func captureUntilFinished() async throws {
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

        let collector = LiveNaruHelperVideoScreenCaptureKitStreamingFrameCollector(
            frameLimit: frameLimit,
            continuation: continuation
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: collector)
        try stream.addStreamOutput(
            collector,
            type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "com.naruremote.helper-video-sck-stream-output")
        )
        try await LiveNaruHelperVideoScreenCaptureKitFiniteCapture.start(stream)

        do {
            try await withTaskCancellationHandler {
                try await collector.waitUntilFinished()
            } onCancel: {
                collector.cancelWait()
            }
            try await LiveNaruHelperVideoScreenCaptureKitFiniteCapture.stop(stream)
        } catch {
            try? await LiveNaruHelperVideoScreenCaptureKitFiniteCapture.stop(stream)
            throw error
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

    fileprivate static func isDisplayableScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
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

private final class LiveNaruHelperVideoScreenCaptureKitStreamingFrameCollector:
    NSObject,
    SCStreamOutput,
    SCStreamDelegate,
    @unchecked Sendable
{
    private let frameLimit: Int?
    private let continuation: AsyncThrowingStream<CVPixelBuffer, any Error>.Continuation
    private let lock = NSLock()
    private var emittedFrameCount = 0
    private var waitContinuation: CheckedContinuation<Void, any Error>?
    private var completion: Result<Void, any Error>?

    init(
        frameLimit: Int?,
        continuation: AsyncThrowingStream<CVPixelBuffer, any Error>.Continuation
    ) {
        self.frameLimit = frameLimit.map { max($0, 1) }
        self.continuation = continuation
    }

    func waitUntilFinished() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let resultToResume: Result<Void, any Error>? = lock.withLock {
                if let completion {
                    return completion
                }
                waitContinuation = continuation
                return nil
            }
            if let resultToResume {
                continuation.resume(with: resultToResume)
            }
        }
    }

    func cancelWait() {
        complete(.failure(CancellationError()))
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              LiveNaruHelperVideoScreenCaptureKitFrameCollector
                  .isDisplayableScreenFrame(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        let shouldFinish: Bool = lock.withLock {
            guard completion == nil else {
                return false
            }
            emittedFrameCount += 1
            return frameLimit.map { emittedFrameCount >= $0 } ?? false
        }
        nonisolated(unsafe) let transferableImageBuffer = imageBuffer
        continuation.yield(transferableImageBuffer)
        if shouldFinish {
            complete(.success(()))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        complete(
            .failure(NaruHelperVideoScreenCaptureKitAccessUnitSourceError.captureFailed)
        )
    }

    private func complete(_ result: Result<Void, any Error>) {
        let continuationToResume: CheckedContinuation<Void, any Error>? = lock.withLock {
            guard completion == nil else {
                return nil
            }
            completion = result
            let continuation = waitContinuation
            waitContinuation = nil
            return continuation
        }
        continuationToResume?.resume(with: result)
    }
}

private struct CapturedPixelBuffer: @unchecked Sendable {
    var pixelBuffer: CVPixelBuffer
}

private struct LiveNaruHelperVideoScreenCaptureKitPixelBufferStreamBox: @unchecked Sendable {
    let stream: AsyncThrowingStream<CVPixelBuffer, any Error>
}

private struct LiveNaruHelperVideoScreenCaptureKitPixelBufferBox: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
}

private final class LiveNaruHelperVideoScreenCaptureKitPixelBufferIteratorBox:
    @unchecked Sendable
{
    private var iterator: AsyncThrowingStream<CVPixelBuffer, any Error>.Iterator

    init(stream: AsyncThrowingStream<CVPixelBuffer, any Error>) {
        self.iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> CVPixelBuffer? {
        try await iterator.next()
    }
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

    var nominalFrameRate: CMTimeScale {
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

private enum NaruHelperVideoAccessUnitSourceDefaultStreamAdapter {
    static func stream(
        source: NaruHelperVideoScreenCaptureKitAccessUnitSource,
        request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        let accessUnits = try source.accessUnits(for: request)
        return AsyncThrowingStream { continuation in
            for accessUnit in accessUnits {
                continuation.yield(accessUnit)
            }
            continuation.finish()
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
