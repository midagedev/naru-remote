import Foundation
import NaruRemoteCore

public enum NaruHelperVideoScreenCaptureKitAccessUnitSourceError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case screenRecordingPermissionMissing
    case captureSourceUnavailable
    case captureTimedOut
    case captureNoOutputCallbacks
    case captureNonScreenOutputCallbacks
    case captureNonDisplayableScreenFrames
    case captureInsufficientDisplayableFrames
    case captureFailed
    case capturedFrameMissingImageBuffer
    case noCapturedFrames
}

#if os(macOS) && canImport(CoreGraphics) && canImport(CoreMedia) && canImport(CoreVideo) && canImport(ScreenCaptureKit) && canImport(VideoToolbox)
@preconcurrency import AppKit
@preconcurrency import CoreGraphics
@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
@preconcurrency import ScreenCaptureKit
import IOKit.pwr_mgt
import VideoToolbox

public protocol NaruHelperVideoScreenCaptureKitPixelBufferProvider: Sendable {
    func pixelBuffers(
        frameLimit: Int,
        frameRateBucket: HelperVideoFrameRateBucket,
        qualityBucket: HelperVideoQualityBucket
    ) throws -> [CVPixelBuffer]
}

public protocol NaruHelperVideoScreenCaptureKitPixelBufferStreamProvider:
    NaruHelperVideoScreenCaptureKitPixelBufferProvider
{
    func pixelBufferStream(
        frameLimit: Int?,
        frameRateBucket: HelperVideoFrameRateBucket,
        qualityBucket: HelperVideoQualityBucket
    ) throws -> AsyncThrowingStream<CVPixelBuffer, any Error>
}

public struct NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy:
    Equatable,
    Sendable
{
    public var outputWidth: Int
    public var outputHeight: Int
    public var queueDepth: Int

    public init(
        outputWidth: Int,
        outputHeight: Int,
        queueDepth: Int
    ) {
        self.outputWidth = max(outputWidth, 2)
        self.outputHeight = max(outputHeight, 2)
        self.queueDepth = min(max(queueDepth, 1), 8)
    }

    public static func make(
        displayWidth: Int,
        displayHeight: Int,
        frameLimit: Int?,
        qualityBucket: HelperVideoQualityBucket
    ) -> Self {
        let sourceWidth = max(displayWidth, 2)
        let sourceHeight = max(displayHeight, 2)
        let maxLongEdge = maxLongEdge(for: qualityBucket)
        let scaledSize = scaledEvenSize(
            width: sourceWidth,
            height: sourceHeight,
            maxLongEdge: maxLongEdge
        )
        return Self(
            outputWidth: scaledSize.width,
            outputHeight: scaledSize.height,
            queueDepth: frameLimit == nil ? 3 : 5
        )
    }

    private static func maxLongEdge(for qualityBucket: HelperVideoQualityBucket) -> Int {
        switch qualityBucket {
        case .readability:
            return 960
        case .balanced:
            return 1_920
        case .fidelity:
            return Int.max
        }
    }

    private static func scaledEvenSize(
        width: Int,
        height: Int,
        maxLongEdge: Int
    ) -> (width: Int, height: Int) {
        let longEdge = max(width, height)
        guard longEdge > maxLongEdge else {
            return (evenDimension(width), evenDimension(height))
        }

        let scale = Double(maxLongEdge) / Double(longEdge)
        return (
            evenDimension(Int((Double(width) * scale).rounded())),
            evenDimension(Int((Double(height) * scale).rounded()))
        )
    }

    private static func evenDimension(_ value: Int) -> Int {
        let clamped = max(value, 2)
        return clamped.isMultiple(of: 2) ? clamped : clamped - 1
    }
}

public struct NaruHelperVideoScreenCaptureKitWindowFallbackPolicy:
    Equatable,
    Sendable
{
    public var minimumWidth: Int
    public var minimumHeight: Int
    public var maximumLongEdge: Int
    public var maximumArea: Int
    public var excludedApplicationNames: Set<String>

    public init(
        minimumWidth: Int = 160,
        minimumHeight: Int = 120,
        maximumLongEdge: Int = 8_192,
        maximumArea: Int = 33_554_432,
        excludedApplicationNames: Set<String> = Self.defaultExcludedApplicationNames
    ) {
        self.minimumWidth = max(minimumWidth, 1)
        self.minimumHeight = max(minimumHeight, 1)
        self.maximumLongEdge = max(maximumLongEdge, 1)
        self.maximumArea = max(maximumArea, 1)
        self.excludedApplicationNames = excludedApplicationNames
    }

    public static let live = NaruHelperVideoScreenCaptureKitWindowFallbackPolicy()

    public static let defaultExcludedApplicationNames: Set<String> = [
        "Control Center",
        "Dock",
        "loginwindow",
        "Notification Center",
        "Spotlight",
        "SystemUIServer",
        "Window Server",
        "WindowManager",
        "제어 센터"
    ]

    public func isUsable(
        width: Int,
        height: Int,
        applicationName: String?
    ) -> Bool {
        guard width >= minimumWidth,
              height >= minimumHeight,
              width <= maximumLongEdge,
              height <= maximumLongEdge,
              width * height <= maximumArea
        else {
            return false
        }

        guard let applicationName else {
            return true
        }
        return !excludedApplicationNames.contains(applicationName)
    }

    public func isUsable(
        _ descriptor: NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor
    ) -> Bool {
        isUsable(
            width: descriptor.width,
            height: descriptor.height,
            applicationName: descriptor.applicationName
        )
    }

    public func preferredDescriptor(
        screenCaptureKitOrder: [NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor],
        coreGraphicsFrontToBackOrder: [NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor],
        frontmostApplicationName: String?
    ) -> NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor? {
        let usableScreenCaptureKitOrder = screenCaptureKitOrder.filter(isUsable)
        for descriptor in coreGraphicsFrontToBackOrder where isUsable(descriptor) {
            if let matchingDescriptor = usableScreenCaptureKitOrder.first(where: {
                matches($0, descriptor)
            }) {
                return matchingDescriptor
            }
        }

        if let frontmostApplicationName,
           let frontmostDescriptor = usableScreenCaptureKitOrder.first(where: {
               $0.applicationName == frontmostApplicationName
           })
        {
            return frontmostDescriptor
        }

        return usableScreenCaptureKitOrder.first
    }

    public func matches(
        _ lhs: NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor,
        _ rhs: NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor
    ) -> Bool {
        lhs.applicationName == rhs.applicationName
            && (lhs.title ?? "") == (rhs.title ?? "")
            && abs(lhs.width - rhs.width) <= 4
            && abs(lhs.height - rhs.height) <= 40
    }
}

public struct NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor:
    Equatable,
    Sendable
{
    public var applicationName: String?
    public var title: String?
    public var width: Int
    public var height: Int

    public init(
        applicationName: String?,
        title: String?,
        width: Int,
        height: Int
    ) {
        self.applicationName = applicationName
        self.title = title
        self.width = width
        self.height = height
    }
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
            frameRateBucket: request.maxFrameRateBucket,
            qualityBucket: request.qualityBucket
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
            frameRateBucket: request.maxFrameRateBucket,
            qualityBucket: request.qualityBucket
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
        frameRateBucket: HelperVideoFrameRateBucket,
        qualityBucket: HelperVideoQualityBucket
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
                    frameRateBucket: frameRateBucket,
                    qualityBucket: qualityBucket
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
        frameRateBucket: HelperVideoFrameRateBucket,
        qualityBucket: HelperVideoQualityBucket
    ) throws -> AsyncThrowingStream<CVPixelBuffer, any Error> {
        guard CGPreflightScreenCaptureAccess() else {
            throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError
                .screenRecordingPermissionMissing
        }

        let bufferingPolicy: AsyncThrowingStream<CVPixelBuffer, any Error>
            .Continuation.BufferingPolicy = frameLimit == nil ? .bufferingNewest(1) : .unbounded
        return AsyncThrowingStream(bufferingPolicy: bufferingPolicy) { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                do {
                    let capture = LiveNaruHelperVideoScreenCaptureKitStreamingCapture(
                        frameLimit: frameLimit,
                        frameRateBucket: frameRateBucket,
                        qualityBucket: qualityBucket,
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

private final class LiveNaruHelperVideoScreenCaptureKitDisplayWakeAssertion:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var assertionIDs: [IOPMAssertionID] = []

    init() {
        let reason = "Naru Remote helper video capture" as CFString
        var userActivityAssertionID = IOPMAssertionID(0)
        if IOPMAssertionDeclareUserActivity(
            reason,
            kIOPMUserActiveLocal,
            &userActivityAssertionID
        ) == kIOReturnSuccess,
            userActivityAssertionID != 0
        {
            assertionIDs.append(userActivityAssertionID)
        }

        var noDisplaySleepAssertionID = IOPMAssertionID(0)
        if IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &noDisplaySleepAssertionID
        ) == kIOReturnSuccess,
            noDisplaySleepAssertionID != 0
        {
            assertionIDs.append(noDisplaySleepAssertionID)
        }
    }

    deinit {
        release()
    }

    func release() {
        let ids = lock.withLock {
            let ids = assertionIDs
            assertionIDs.removeAll()
            return ids
        }
        for id in ids {
            IOPMAssertionRelease(id)
        }
    }
}

private struct LiveNaruHelperVideoScreenCaptureKitFiniteCapture {
    var frameLimit: Int
    var frameRateBucket: HelperVideoFrameRateBucket
    var qualityBucket: HelperVideoQualityBucket

    func capture() async throws -> [CapturedPixelBuffer] {
        let displayWakeAssertion = LiveNaruHelperVideoScreenCaptureKitDisplayWakeAssertion()
        defer {
            displayWakeAssertion.release()
        }
        let content = try await Self.shareableContentAfterDisplayWake()
        guard let target = Self.captureTarget(from: content) else {
            throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError
                .captureSourceUnavailable
        }

        await target.prepareForCapture()
        let filter = target.filter
        let configuration = SCStreamConfiguration()
        let policy = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy.make(
            displayWidth: target.width,
            displayHeight: target.height,
            frameLimit: frameLimit,
            qualityBucket: qualityBucket
        )
        configuration.width = policy.outputWidth
        configuration.height = policy.outputHeight
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = policy.queueDepth
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

    fileprivate static func shareableContentAfterDisplayWake() async throws -> SCShareableContent {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard content.displays.isEmpty else {
            return content
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        return try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
    }

    fileprivate static func captureDisplay(from content: SCShareableContent) -> SCDisplay? {
        let mainDisplayID = CGMainDisplayID()
        return content.displays.first { $0.displayID == mainDisplayID }
            ?? content.displays.first
    }

    fileprivate static func captureTarget(from content: SCShareableContent) -> ScreenCaptureTarget? {
        if let display = captureDisplay(from: content) {
            return .display(display)
        }

        return captureWindow(from: content).map(ScreenCaptureTarget.window)
    }

    fileprivate static func captureWindow(from content: SCShareableContent) -> SCWindow? {
        let policy = NaruHelperVideoScreenCaptureKitWindowFallbackPolicy.live
        let screenCaptureKitDescriptors = content.windows.map(descriptor)
        let frontmostApplicationName = NSWorkspace.shared
            .frontmostApplication?
            .localizedName

        guard let preferredDescriptor = policy.preferredDescriptor(
            screenCaptureKitOrder: screenCaptureKitDescriptors,
            coreGraphicsFrontToBackOrder: coreGraphicsWindowDescriptors(),
            frontmostApplicationName: frontmostApplicationName
        ) else {
            return nil
        }

        return content.windows.first { window in
            policy.matches(descriptor(window), preferredDescriptor)
        }
    }

    private static func coreGraphicsWindowDescriptors()
        -> [NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor]
    {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowInfoList.map { windowInfo in
            let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any]
            return NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor(
                applicationName: windowInfo[kCGWindowOwnerName as String] as? String,
                title: windowInfo[kCGWindowName as String] as? String,
                width: Int((bounds?["Width"] as? Double) ?? 0),
                height: Int((bounds?["Height"] as? Double) ?? 0)
            )
        }
    }

    private static func descriptor(
        _ window: SCWindow
    ) -> NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor {
        NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor(
            applicationName: window.owningApplication?.applicationName,
            title: window.title,
            width: Int(window.frame.width.rounded(.down)),
            height: Int(window.frame.height.rounded(.down))
        )
    }
}

private enum ScreenCaptureTarget {
    case display(SCDisplay)
    case window(SCWindow)

    var width: Int {
        switch self {
        case .display(let display):
            return display.width
        case .window(let window):
            return max(Int(window.frame.width.rounded(.down)), 2)
        }
    }

    var height: Int {
        switch self {
        case .display(let display):
            return display.height
        case .window(let window):
            return max(Int(window.frame.height.rounded(.down)), 2)
        }
    }

    var filter: SCContentFilter {
        switch self {
        case .display(let display):
            return SCContentFilter(display: display, excludingWindows: [])
        case .window(let window):
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    func prepareForCapture() async {
        switch self {
        case .display:
            return
        case .window:
            await Self.prepareAppKitForWindowCapture()
        }
    }

    @MainActor
    private static func prepareAppKitForWindowCapture() {
        _ = NSApplication.shared
    }
}

private struct LiveNaruHelperVideoScreenCaptureKitStreamingCapture {
    var frameLimit: Int?
    var frameRateBucket: HelperVideoFrameRateBucket
    var qualityBucket: HelperVideoQualityBucket
    let continuation: AsyncThrowingStream<CVPixelBuffer, any Error>.Continuation

    func captureUntilFinished() async throws {
        let displayWakeAssertion = LiveNaruHelperVideoScreenCaptureKitDisplayWakeAssertion()
        defer { displayWakeAssertion.release() }
        let content = try await LiveNaruHelperVideoScreenCaptureKitFiniteCapture
            .shareableContentAfterDisplayWake()
        guard let target = LiveNaruHelperVideoScreenCaptureKitFiniteCapture
            .captureTarget(from: content)
        else {
            throw NaruHelperVideoScreenCaptureKitAccessUnitSourceError
                .captureSourceUnavailable
        }

        await target.prepareForCapture()
        let filter = target.filter
        let configuration = SCStreamConfiguration()
        let policy = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy.make(
            displayWidth: target.width,
            displayHeight: target.height,
            frameLimit: frameLimit,
            qualityBucket: qualityBucket
        )
        configuration.width = policy.outputWidth
        configuration.height = policy.outputHeight
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = policy.queueDepth
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
            if let frameLimit {
                try await withTaskCancellationHandler {
                    try await collector.waitUntilFinished(
                        timeout: frameRateBucket.screenCaptureFrameCollectionTimeout(
                            frameLimit: frameLimit
                        )
                    )
                } onCancel: {
                    collector.cancelWait()
                }
            } else {
                try await withTaskCancellationHandler {
                    try await collector.waitForFirstFrame(
                        timeout: frameRateBucket.screenCaptureFirstFrameTimeout
                    )
                    try await collector.waitUntilFinished()
                } onCancel: {
                    collector.cancelWait()
                }
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
    private var noFrameDiagnostics = LiveNaruHelperVideoScreenCaptureKitNoFrameDiagnostics()

    init(frameLimit: Int) {
        self.frameLimit = max(frameLimit, 1)
    }

    func waitForFrames(timeout: TimeInterval) throws -> [CapturedPixelBuffer] {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw lock.withLock {
                noFrameDiagnostics.timeoutError
            }
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
        let isScreenOutput = type == .screen
        let imageBuffer = isScreenOutput ? CMSampleBufferGetImageBuffer(sampleBuffer) : nil
        let isDisplayable = isScreenOutput && Self.isDisplayableScreenFrame(
            sampleBuffer,
            hasImageBuffer: imageBuffer != nil
        )
        lock.withLock {
            noFrameDiagnostics.record(
                isScreenOutput: isScreenOutput,
                isDisplayableScreenFrame: isDisplayable,
                hasImageBuffer: imageBuffer != nil
            )
        }

        guard isScreenOutput, isDisplayable, let imageBuffer else {
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

    fileprivate static func isDisplayableScreenFrame(
        _ sampleBuffer: CMSampleBuffer,
        hasImageBuffer: Bool
    ) -> Bool {
        NaruHelperVideoScreenCaptureKitFrameSamplePolicy.isDisplayableScreenFrame(
            rawStatus: NaruHelperVideoScreenCaptureKitFrameSamplePolicy.rawStatus(
                from: sampleBuffer
            ),
            hasImageBuffer: hasImageBuffer
        )
    }
}

struct NaruHelperVideoScreenCaptureKitFrameSamplePolicy {
    static func rawStatus(from sampleBuffer: CMSampleBuffer) -> Int? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let first = attachments.first
        else {
            return nil
        }

        return first[SCStreamFrameInfo.status] as? Int
    }

    static func isDisplayableScreenFrame(rawStatus: Int?, hasImageBuffer: Bool) -> Bool {
        guard let rawStatus,
              let status = SCFrameStatus(rawValue: rawStatus)
        else {
            return true
        }

        return status == .complete || (status == .started && hasImageBuffer)
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
    private var noFrameDiagnostics = LiveNaruHelperVideoScreenCaptureKitNoFrameDiagnostics()
    private var firstFrameContinuation: CheckedContinuation<Void, any Error>?
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
        try await waitUntilFinishedWithoutTimeout()
    }

    func waitUntilFinished(timeout: TimeInterval) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.waitUntilFinishedWithoutTimeout()
            }
            group.addTask {
                try await Self.sleep(seconds: timeout)
                let error = self.noFrameTimeoutError()
                self.cancelWait(error)
                throw error
            }

            defer {
                group.cancelAll()
            }
            guard let result = try await group.next() else {
                return
            }
            return result
        }
    }

    func waitForFirstFrame(timeout: TimeInterval) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.waitForFirstFrameWithoutTimeout()
            }
            group.addTask {
                try await Self.sleep(seconds: timeout)
                let error = self.noFrameTimeoutError()
                self.cancelWait(error)
                throw error
            }

            defer {
                group.cancelAll()
            }
            guard let result = try await group.next() else {
                return
            }
            return result
        }
    }

    private func waitForFirstFrameWithoutTimeout() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let resultToResume: Result<Void, any Error>? = lock.withLock {
                if emittedFrameCount > 0 {
                    return .success(())
                }
                if let completion {
                    return completion
                }
                firstFrameContinuation = continuation
                return nil
            }
            if let resultToResume {
                continuation.resume(with: resultToResume)
            }
        }
    }

    private func waitUntilFinishedWithoutTimeout() async throws {
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

    private func noFrameTimeoutError() -> NaruHelperVideoScreenCaptureKitAccessUnitSourceError {
        lock.withLock {
            noFrameDiagnostics.timeoutError
        }
    }

    private static func sleep(seconds: TimeInterval) async throws {
        let clampedSeconds = max(seconds, 0)
        let nanoseconds = UInt64(clampedSeconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    func cancelWait(_ error: any Error = CancellationError()) {
        complete(.failure(error))
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        let isScreenOutput = type == .screen
        let imageBuffer = isScreenOutput ? CMSampleBufferGetImageBuffer(sampleBuffer) : nil
        let isDisplayable = isScreenOutput
            && LiveNaruHelperVideoScreenCaptureKitFrameCollector
                .isDisplayableScreenFrame(
                    sampleBuffer,
                    hasImageBuffer: imageBuffer != nil
                )
        lock.withLock {
            noFrameDiagnostics.record(
                isScreenOutput: isScreenOutput,
                isDisplayableScreenFrame: isDisplayable,
                hasImageBuffer: imageBuffer != nil
            )
        }

        guard isScreenOutput, isDisplayable, let imageBuffer else {
            return
        }

        let firstFrameContinuationToResume: CheckedContinuation<Void, any Error>?
        let shouldFinish: Bool
        (firstFrameContinuationToResume, shouldFinish) = lock.withLock {
            guard completion == nil else {
                return (nil, false)
            }
            emittedFrameCount += 1
            let firstFrameContinuation = emittedFrameCount == 1
                ? self.firstFrameContinuation
                : nil
            self.firstFrameContinuation = nil
            return (
                firstFrameContinuation,
                frameLimit.map { emittedFrameCount >= $0 } ?? false
            )
        }
        firstFrameContinuationToResume?.resume()
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
        let continuationsToResume:
            (
                firstFrame: CheckedContinuation<Void, any Error>?,
                wait: CheckedContinuation<Void, any Error>?
            ) = lock.withLock {
            guard completion == nil else {
                return (nil, nil)
            }
            completion = result
            let firstFrameContinuation = self.firstFrameContinuation
            self.firstFrameContinuation = nil
            let continuation = waitContinuation
            waitContinuation = nil
            return (firstFrameContinuation, continuation)
        }
        continuationsToResume.firstFrame?.resume(with: result)
        continuationsToResume.wait?.resume(with: result)
    }
}

struct LiveNaruHelperVideoScreenCaptureKitNoFrameDiagnostics {
    private var observedOutputCallback = false
    private var observedScreenOutputCallback = false
    private var observedDisplayableScreenFrame = false
    private var observedMissingImageBuffer = false

    mutating func record(
        isScreenOutput: Bool,
        isDisplayableScreenFrame: Bool,
        hasImageBuffer: Bool
    ) {
        observedOutputCallback = true
        if isScreenOutput {
            observedScreenOutputCallback = true
        }
        if isDisplayableScreenFrame {
            observedDisplayableScreenFrame = true
            if !hasImageBuffer {
                observedMissingImageBuffer = true
            }
        }
    }

    var timeoutError: NaruHelperVideoScreenCaptureKitAccessUnitSourceError {
        guard observedOutputCallback else {
            return .captureNoOutputCallbacks
        }
        guard observedScreenOutputCallback else {
            return .captureNonScreenOutputCallbacks
        }
        if observedMissingImageBuffer {
            return .capturedFrameMissingImageBuffer
        }
        guard observedDisplayableScreenFrame else {
            return .captureNonDisplayableScreenFrames
        }
        return .captureInsufficientDisplayableFrames
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

    var screenCaptureFirstFrameTimeout: TimeInterval {
        screenCaptureFrameCollectionTimeout(frameLimit: 1)
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
