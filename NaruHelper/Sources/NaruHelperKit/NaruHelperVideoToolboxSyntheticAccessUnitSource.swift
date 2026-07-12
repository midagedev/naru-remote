import Foundation
import NaruRemoteCore

#if os(macOS) && canImport(CoreMedia) && canImport(CoreVideo) && canImport(VideoToolbox)
import CoreMedia
import CoreVideo
import VideoToolbox
#endif

public enum NaruHelperVideoToolboxSyntheticAccessUnitSourceError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case invalidFrameSize
    case pixelBufferCreationFailed
    case compressionSessionCreationFailed(OSStatus)
    case compressionSessionConfigurationFailed(OSStatus)
    case compressionSessionPrepareFailed(OSStatus)
    case compressionFrameEncodeFailed(OSStatus)
    case compressionFlushFailed(OSStatus)
    case encoderOutputFailed(OSStatus)
    case sampleBufferMissingData
    case h264ParameterSetExtractionFailed(OSStatus)
    case h264ParameterSetMissing
    case malformedAVCCPayload
    case noSourceFrames
    case noEncodedAccessUnits
    case encodedAccessUnitBackpressureExceeded
}

enum NaruHelperVideoEncodedAccessUnitStreamPolicy {
    static let defaultCapacity = 8
    private static let minimumCapacity = 2

    static func normalizedCapacity(_ requestedCapacity: Int) -> Int {
        max(requestedCapacity, minimumCapacity)
    }

    static func bufferingPolicy(
        capacity: Int
    ) -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error>.Continuation.BufferingPolicy {
        .bufferingOldest(normalizedCapacity(capacity))
    }

    /// Encoded H.264 access units must remain a contiguous prefix. Dropping the
    /// oldest parameter set, keyframe, or delta would corrupt the decoder's
    /// reference chain, so a full buffer terminates the helper stream and lets
    /// the app fall back to VNC instead.
    @discardableResult
    static func yield(
        _ accessUnit: NaruHelperVideoAccessUnit,
        to continuation: AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error>.Continuation
    ) -> Bool {
        switch continuation.yield(accessUnit) {
        case .enqueued:
            return true
        case .dropped:
            continuation.finish(
                throwing: NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                    .encodedAccessUnitBackpressureExceeded
            )
            return false
        case .terminated:
            return false
        @unknown default:
            continuation.finish(
                throwing: NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                    .encodedAccessUnitBackpressureExceeded
            )
            return false
        }
    }
}

public enum NaruHelperVideoToolboxEncodingMode: Equatable, Sendable {
    case lowLatencyRealtime
    case completeFrameBatch
}

public struct NaruHelperVideoToolboxSyntheticAccessUnitSource: NaruHelperVideoAccessUnitSource {
    /// A value of `0` means an unbounded stream for `accessUnitStream(...)`.
    /// The legacy finite `accessUnits(...)` API still encodes at least one
    /// frame so benchmark and fixture callers never allocate an infinite batch.
    public var frameCount: Int
    public var width: Int32
    public var height: Int32
    public var encodingMode: NaruHelperVideoToolboxEncodingMode

    public init(
        frameCount: Int = 2,
        width: Int32 = 64,
        height: Int32 = 64,
        encodingMode: NaruHelperVideoToolboxEncodingMode = .completeFrameBatch
    ) {
        self.frameCount = max(frameCount, 0)
        self.width = width
        self.height = height
        self.encodingMode = encodingMode
    }

    public func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        #if os(macOS) && canImport(VideoToolbox)
        let finiteFrameCount = max(frameCount, 1)
        let pixelBuffers = try (0..<finiteFrameCount).map { frameIndex in
            try Self.makePixelBuffer(
                width: width,
                height: height,
                frameIndex: frameIndex
            )
        }
        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: width,
            height: height,
            frameRateBucket: request.maxFrameRateBucket,
            qualityBucket: request.qualityBucket,
            keyFrameInterval: finiteFrameCount,
            encodingMode: encodingMode
        )
        return try encoder.encode(pixelBuffers: pixelBuffers)
        #else
        throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.unsupportedPlatform
        #endif
    }

    public func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        #if os(macOS) && canImport(VideoToolbox)
        let frameLimit = frameCount > 0 ? frameCount : nil
        let pixelBuffers = try syntheticPixelBufferStream(
            frameLimit: frameLimit,
            frameRateBucket: request.maxFrameRateBucket
        )
        let keyFrameInterval = frameLimit
            ?? max(Int(request.maxFrameRateBucket.nominalTimescale) * 2, 30)
        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: width,
            height: height,
            frameRateBucket: request.maxFrameRateBucket,
            qualityBucket: request.qualityBucket,
            keyFrameInterval: keyFrameInterval,
            encodingMode: .lowLatencyRealtime
        )
        return try encoder.encode(pixelBuffers: pixelBuffers)
        #else
        throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.unsupportedPlatform
        #endif
    }
}

#if os(macOS) && canImport(CoreMedia) && canImport(CoreVideo) && canImport(VideoToolbox)
public struct NaruHelperVideoToolboxPixelBufferAccessUnitEncoder: Sendable {
    private let width: Int32
    private let height: Int32
    private let frameRateBucket: HelperVideoFrameRateBucket
    public let rateControlPolicy: NaruHelperVideoRateControlPolicy
    private let keyFrameInterval: Int
    private let encodingMode: NaruHelperVideoToolboxEncodingMode
    private let encodedAccessUnitBufferCapacity: Int

    public init(
        width: Int32,
        height: Int32,
        frameRateBucket: HelperVideoFrameRateBucket,
        qualityBucket: HelperVideoQualityBucket = .readability,
        keyFrameInterval: Int,
        encodingMode: NaruHelperVideoToolboxEncodingMode = .lowLatencyRealtime
    ) {
        self.init(
            width: width,
            height: height,
            frameRateBucket: frameRateBucket,
            qualityBucket: qualityBucket,
            keyFrameInterval: keyFrameInterval,
            encodingMode: encodingMode,
            encodedAccessUnitBufferCapacity: NaruHelperVideoEncodedAccessUnitStreamPolicy
                .defaultCapacity
        )
    }

    init(
        width: Int32,
        height: Int32,
        frameRateBucket: HelperVideoFrameRateBucket,
        qualityBucket: HelperVideoQualityBucket = .readability,
        keyFrameInterval: Int,
        encodingMode: NaruHelperVideoToolboxEncodingMode = .lowLatencyRealtime,
        encodedAccessUnitBufferCapacity: Int
    ) {
        self.width = width
        self.height = height
        self.frameRateBucket = frameRateBucket
        self.rateControlPolicy = NaruHelperVideoRateControlPolicy(
            qualityBucket: qualityBucket,
            frameRateBucket: frameRateBucket
        )
        self.keyFrameInterval = max(keyFrameInterval, 1)
        self.encodingMode = encodingMode
        self.encodedAccessUnitBufferCapacity = NaruHelperVideoEncodedAccessUnitStreamPolicy
            .normalizedCapacity(encodedAccessUnitBufferCapacity)
    }

    public func encode(pixelBuffers: [CVPixelBuffer]) throws -> [NaruHelperVideoAccessUnit] {
        guard width > 0, height > 0 else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.invalidFrameSize
        }
        guard !pixelBuffers.isEmpty else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.noSourceFrames
        }

        let collector = LiveNaruHelperVideoToolboxOutputCollector()
        var session: VTCompressionSession?
        let encoderSpecification = encodingMode.encoderSpecification
        let imageBufferAttributes: CFDictionary = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey: Int(width),
            kCVPixelBufferHeightKey: Int(height)
        ] as CFDictionary

        let createStatus = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpecification,
            imageBufferAttributes: imageBufferAttributes,
            compressedDataAllocator: nil,
            outputCallback: Self.outputCallback,
            refcon: Unmanaged.passUnretained(collector).toOpaque(),
            compressionSessionOut: &session
        )
        guard createStatus == noErr, let session else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                .compressionSessionCreationFailed(createStatus)
        }
        defer {
            VTCompressionSessionInvalidate(session)
        }

        try configure(session)
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepareStatus == noErr else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                .compressionSessionPrepareFailed(prepareStatus)
        }

        let timescale = frameRateBucket.nominalTimescale
        for (index, pixelBuffer) in pixelBuffers.enumerated() {
            guard CVPixelBufferGetWidth(pixelBuffer) == Int(width),
                  CVPixelBufferGetHeight(pixelBuffer) == Int(height)
            else {
                throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.invalidFrameSize
            }
            let presentationTime = CMTime(value: CMTimeValue(index), timescale: timescale)
            let status = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: presentationTime,
                duration: CMTime(value: 1, timescale: timescale),
                frameProperties: index == 0 ? Self.forceKeyframeProperties() : nil,
                sourceFrameRefcon: nil,
                infoFlagsOut: nil
            )
            guard status == noErr else {
                throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                    .compressionFrameEncodeFailed(status)
            }
        }

        let flushStatus = VTCompressionSessionCompleteFrames(
            session,
            untilPresentationTimeStamp: .invalid
        )
        guard flushStatus == noErr else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                .compressionFlushFailed(flushStatus)
        }

        return try collector.accessUnits()
    }

    public func encode(
        pixelBuffers: AsyncThrowingStream<CVPixelBuffer, any Error>
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        guard width > 0, height > 0 else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.invalidFrameSize
        }

        return AsyncThrowingStream(
            bufferingPolicy: NaruHelperVideoEncodedAccessUnitStreamPolicy.bufferingPolicy(
                capacity: encodedAccessUnitBufferCapacity
            )
        ) { continuation in
            let emitter = LiveNaruHelperVideoToolboxStreamEmitter(continuation: continuation)
            var session: VTCompressionSession?
            let encoderSpecification = encodingMode.encoderSpecification
            let imageBufferAttributes: CFDictionary = [
                kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey: Int(width),
                kCVPixelBufferHeightKey: Int(height)
            ] as CFDictionary
            let createStatus = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: width,
                height: height,
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: encoderSpecification,
                imageBufferAttributes: imageBufferAttributes,
                compressedDataAllocator: nil,
                outputCallback: Self.streamOutputCallback,
                refcon: Unmanaged.passUnretained(emitter).toOpaque(),
                compressionSessionOut: &session
            )
            guard createStatus == noErr, let session else {
                continuation.finish(
                    throwing: NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                        .compressionSessionCreationFailed(createStatus)
                )
                return
            }

            let sessionBox = LiveNaruHelperVideoToolboxCompressionSessionBox(session: session)
            let pixelBufferStreamBox = LiveNaruHelperVideoPixelBufferStreamBox(
                stream: pixelBuffers
            )
            let producer = Task.detached(priority: .userInitiated) {
                defer {
                    sessionBox.invalidate()
                }

                do {
                    try configure(sessionBox.session)
                    let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(
                        sessionBox.session
                    )
                    guard prepareStatus == noErr else {
                        throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                            .compressionSessionPrepareFailed(prepareStatus)
                    }

                    let timescale = frameRateBucket.nominalTimescale
                    var index = 0
                    for try await pixelBuffer in pixelBufferStreamBox.stream {
                        try Task.checkCancellation()
                        guard CVPixelBufferGetWidth(pixelBuffer) == Int(width),
                              CVPixelBufferGetHeight(pixelBuffer) == Int(height)
                        else {
                            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                                .invalidFrameSize
                        }

                        let presentationTime = CMTime(
                            value: CMTimeValue(index),
                            timescale: timescale
                        )
                        let shouldForceKeyframe = index == 0
                            || index.isMultiple(of: keyFrameInterval)
                        let status = VTCompressionSessionEncodeFrame(
                            sessionBox.session,
                            imageBuffer: pixelBuffer,
                            presentationTimeStamp: presentationTime,
                            duration: CMTime(value: 1, timescale: timescale),
                            frameProperties: shouldForceKeyframe
                                ? Self.forceKeyframeProperties()
                                : nil,
                            sourceFrameRefcon: nil,
                            infoFlagsOut: nil
                        )
                        guard status == noErr else {
                            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                                .compressionFrameEncodeFailed(status)
                        }
                        index += 1
                    }

                    let flushStatus = VTCompressionSessionCompleteFrames(
                        sessionBox.session,
                        untilPresentationTimeStamp: .invalid
                    )
                    guard flushStatus == noErr else {
                        throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                            .compressionFlushFailed(flushStatus)
                    }
                    emitter.finish()
                } catch is CancellationError {
                    emitter.finish()
                } catch {
                    emitter.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
    }

    private static let outputCallback: VTCompressionOutputCallback = {
        refcon,
        _,
        status,
        infoFlags,
        sampleBuffer
    in
        guard let refcon else {
            return
        }
        let collector = Unmanaged<LiveNaruHelperVideoToolboxOutputCollector>
            .fromOpaque(refcon)
            .takeUnretainedValue()
        collector.record(status: status, infoFlags: infoFlags, sampleBuffer: sampleBuffer)
    }

    private static let streamOutputCallback: VTCompressionOutputCallback = {
        refcon,
        _,
        status,
        infoFlags,
        sampleBuffer
    in
        guard let refcon else {
            return
        }
        let emitter = Unmanaged<LiveNaruHelperVideoToolboxStreamEmitter>
            .fromOpaque(refcon)
            .takeUnretainedValue()
        emitter.record(status: status, infoFlags: infoFlags, sampleBuffer: sampleBuffer)
    }

    private static func forceKeyframeProperties() -> CFDictionary {
        [
            kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue as Any
        ] as CFDictionary
    }

    private func configure(_ session: VTCompressionSession) throws {
        let properties: [(CFString, CFTypeRef)] = [
            (kVTCompressionPropertyKey_RealTime, encodingMode.realTimePropertyValue),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),
            (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel),
            (kVTCompressionPropertyKey_MaxKeyFrameInterval, keyFrameInterval as CFNumber),
            (kVTCompressionPropertyKey_ExpectedFrameRate, frameRateBucket.nominalTimescale as CFNumber)
        ] + rateControlPolicy.videoToolboxCompressionProperties()

        for (key, value) in properties {
            let status = VTSessionSetProperty(session, key: key, value: value)
            guard status == noErr else {
                throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                    .compressionSessionConfigurationFailed(status)
            }
        }
    }
}

private extension NaruHelperVideoToolboxEncodingMode {
    var encoderSpecification: CFDictionary {
        switch self {
        case .lowLatencyRealtime:
            return [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any,
                kVTVideoEncoderSpecification_EnableLowLatencyRateControl: kCFBooleanTrue as Any
            ] as CFDictionary
        case .completeFrameBatch:
            return [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any
            ] as CFDictionary
        }
    }

    var realTimePropertyValue: CFBoolean {
        switch self {
        case .lowLatencyRealtime:
            return kCFBooleanTrue
        case .completeFrameBatch:
            return kCFBooleanFalse
        }
    }
}

private extension NaruHelperVideoToolboxSyntheticAccessUnitSource {
    func syntheticPixelBufferStream(
        frameLimit: Int?,
        frameRateBucket: HelperVideoFrameRateBucket
    ) throws -> AsyncThrowingStream<CVPixelBuffer, any Error> {
        guard width > 0, height > 0 else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.invalidFrameSize
        }

        if frameLimit == nil {
            return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                Self.startSyntheticPixelBufferProducer(
                    continuation: continuation,
                    frameLimit: frameLimit,
                    frameRateBucket: frameRateBucket,
                    width: width,
                    height: height
                )
            }
        }

        return AsyncThrowingStream { continuation in
            Self.startSyntheticPixelBufferProducer(
                continuation: continuation,
                frameLimit: frameLimit,
                frameRateBucket: frameRateBucket,
                width: width,
                height: height
            )
        }
    }

    static func startSyntheticPixelBufferProducer(
        continuation: AsyncThrowingStream<CVPixelBuffer, any Error>.Continuation,
        frameLimit: Int?,
        frameRateBucket: HelperVideoFrameRateBucket,
        width: Int32,
        height: Int32
    ) {
        let producer = Task.detached(priority: .userInitiated) {
            var frameIndex = 0
            do {
                while frameLimit.map({ frameIndex < $0 }) ?? true {
                    try Task.checkCancellation()
                    let yieldResult = continuation.yield(
                        try Self.makePixelBuffer(
                            width: width,
                            height: height,
                            frameIndex: frameIndex
                        )
                    )
                    switch yieldResult {
                    case .enqueued, .dropped:
                        break
                    case .terminated:
                        return
                    @unknown default:
                        return
                    }
                    frameIndex += 1
                    try await Task.sleep(
                        for: frameRateBucket.syntheticFrameIntervalDuration
                    )
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

    static func makePixelBuffer(
        width: Int32,
        height: Int32,
        frameIndex: Int
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: CFDictionary = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey: Int(width),
            kCVPixelBufferHeightKey: Int(height),
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary
        let createStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(width),
            Int(height),
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        guard createStatus == kCVReturnSuccess, let pixelBuffer else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.pixelBufferCreationFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let rowCount = CVPixelBufferGetHeight(pixelBuffer)
        let columnCount = CVPixelBufferGetWidth(pixelBuffer)
        let bytes = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * rowCount)
        for y in 0..<rowCount {
            for x in 0..<columnCount {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = UInt8((x * 3 + frameIndex * 17) & 0xFF)
                bytes[offset + 1] = UInt8((y * 5 + frameIndex * 29) & 0xFF)
                bytes[offset + 2] = UInt8(((x + y) * 2 + frameIndex * 41) & 0xFF)
                bytes[offset + 3] = 0xFF
            }
        }
        return pixelBuffer
    }
}

private final class LiveNaruHelperVideoToolboxOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var statusError: OSStatus?
    private var parameterSetPayload: Data?
    private var encodedSamples: [(kind: HelperVideoAccessUnitKind, payload: Data)] = []

    func record(
        status: OSStatus,
        infoFlags: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?
    ) {
        lock.withLock {
            guard status == noErr else {
                statusError = status
                return
            }
            guard !infoFlags.contains(.frameDropped) else {
                return
            }
            guard let sampleBuffer else {
                statusError = NaruHelperVideoToolboxSyntheticStatus.sampleBufferMissing
                return
            }

            do {
                if parameterSetPayload == nil {
                    parameterSetPayload = try NaruHelperVideoToolboxSampleBufferPayloads
                        .parameterSetAnnexBPayload(from: sampleBuffer)
                }
                let payload = try NaruHelperVideoToolboxSampleBufferPayloads
                    .mediaAnnexBPayload(from: sampleBuffer)
                guard !payload.isEmpty else {
                    return
                }
                encodedSamples.append((
                    kind: NaruHelperVideoToolboxSampleBufferPayloads
                        .accessUnitKind(from: sampleBuffer),
                    payload: payload
                ))
            } catch {
                statusError = NaruHelperVideoToolboxSyntheticStatus.encoderPayloadExtractionFailed
            }
        }
    }

    func accessUnits() throws -> [NaruHelperVideoAccessUnit] {
        try lock.withLock {
            if let statusError {
                switch statusError {
                case NaruHelperVideoToolboxSyntheticStatus.sampleBufferMissing:
                    throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.sampleBufferMissingData
                case NaruHelperVideoToolboxSyntheticStatus.encoderPayloadExtractionFailed:
                    throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.malformedAVCCPayload
                default:
                    throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                        .encoderOutputFailed(statusError)
                }
            }

            guard let parameterSetPayload, !parameterSetPayload.isEmpty else {
                throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.h264ParameterSetMissing
            }
            guard !encodedSamples.isEmpty else {
                throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.noEncodedAccessUnits
            }

            var sequence = 0
            var accessUnits = [
                NaruHelperVideoAccessUnit(
                    sequence: sequence,
                    kind: .parameterSet,
                    binaryPayload: parameterSetPayload
                )
            ]
            sequence += 1
            accessUnits.append(contentsOf: encodedSamples.map { sample in
                defer {
                    sequence += 1
                }
                return NaruHelperVideoAccessUnit(
                    sequence: sequence,
                    kind: sample.kind,
                    binaryPayload: sample.payload
                )
            })
            return accessUnits
        }
    }
}

private final class LiveNaruHelperVideoToolboxStreamEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error>
        .Continuation
    private var didEmitParameterSet = false
    private var sequence = 0
    private var isFinished = false

    init(
        continuation: AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error>
            .Continuation
    ) {
        self.continuation = continuation
    }

    func record(
        status: OSStatus,
        infoFlags: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?
    ) {
        if status != noErr {
            finish(
                throwing: NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                    .encoderOutputFailed(status)
            )
            return
        }
        guard !infoFlags.contains(.frameDropped) else {
            return
        }
        guard let sampleBuffer else {
            finish(
                throwing: NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                    .sampleBufferMissingData
            )
            return
        }

        do {
            let accessUnits = try makeAccessUnits(from: sampleBuffer)
            for accessUnit in accessUnits {
                guard NaruHelperVideoEncodedAccessUnitStreamPolicy.yield(
                    accessUnit,
                    to: continuation
                ) else {
                    markTerminated()
                    return
                }
            }
        } catch {
            finish(throwing: error)
        }
    }

    func finish() {
        let shouldFinish: Bool = lock.withLock {
            guard !isFinished else {
                return false
            }
            isFinished = true
            return true
        }
        guard shouldFinish else {
            return
        }
        continuation.finish()
    }

    func finish(throwing error: any Error) {
        let shouldFinish: Bool = lock.withLock {
            guard !isFinished else {
                return false
            }
            isFinished = true
            return true
        }
        guard shouldFinish else {
            return
        }
        continuation.finish(throwing: error)
    }

    private func markTerminated() {
        lock.withLock {
            isFinished = true
        }
    }

    private func makeAccessUnits(
        from sampleBuffer: CMSampleBuffer
    ) throws -> [NaruHelperVideoAccessUnit] {
        try lock.withLock {
            guard !isFinished else {
                return []
            }

            var accessUnits: [NaruHelperVideoAccessUnit] = []
            if !didEmitParameterSet {
                let payload = try NaruHelperVideoToolboxSampleBufferPayloads
                    .parameterSetAnnexBPayload(from: sampleBuffer)
                if !payload.isEmpty {
                    accessUnits.append(nextAccessUnit(kind: .parameterSet, payload: payload))
                    didEmitParameterSet = true
                }
            }

            let payload = try NaruHelperVideoToolboxSampleBufferPayloads
                .mediaAnnexBPayload(from: sampleBuffer)
            if !payload.isEmpty {
                accessUnits.append(nextAccessUnit(
                    kind: NaruHelperVideoToolboxSampleBufferPayloads
                        .accessUnitKind(from: sampleBuffer),
                    payload: payload
                ))
            }
            return accessUnits
        }
    }

    private func nextAccessUnit(
        kind: HelperVideoAccessUnitKind,
        payload: Data
    ) -> NaruHelperVideoAccessUnit {
        defer {
            sequence += 1
        }
        return NaruHelperVideoAccessUnit(
            sequence: sequence,
            kind: kind,
            binaryPayload: payload
        )
    }
}

private final class LiveNaruHelperVideoToolboxCompressionSessionBox: @unchecked Sendable {
    let session: VTCompressionSession

    init(session: VTCompressionSession) {
        self.session = session
    }

    func invalidate() {
        VTCompressionSessionInvalidate(session)
    }
}

private struct LiveNaruHelperVideoPixelBufferStreamBox: @unchecked Sendable {
    let stream: AsyncThrowingStream<CVPixelBuffer, any Error>
}

private enum NaruHelperVideoToolboxSampleBufferPayloads {
    static func parameterSetAnnexBPayload(from sampleBuffer: CMSampleBuffer) throws -> Data {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.sampleBufferMissingData
        }

        var parameterSetCount = 0
        var nalUnitHeaderLength: Int32 = 0
        let countStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength
        )
        guard countStatus == noErr, parameterSetCount > 0 else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                .h264ParameterSetExtractionFailed(countStatus)
        }

        var payload = Data()
        for index in 0..<parameterSetCount {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            guard status == noErr, let pointer, size > 0 else {
                throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                    .h264ParameterSetExtractionFailed(status)
            }
            appendAnnexBStartCode(to: &payload)
            payload.append(pointer, count: size)
        }
        return payload
    }

    static func mediaAnnexBPayload(from sampleBuffer: CMSampleBuffer) throws -> Data {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.sampleBufferMissingData
        }

        let length = CMBlockBufferGetDataLength(dataBuffer)
        guard length > 0 else {
            return Data()
        }
        var avccPayload = Data(count: length)
        let copyStatus = avccPayload.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return kCMBlockBufferBadPointerParameterErr
            }
            return CMBlockBufferCopyDataBytes(
                dataBuffer,
                atOffset: 0,
                dataLength: length,
                destination: baseAddress
            )
        }
        guard copyStatus == noErr else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.sampleBufferMissingData
        }
        return try annexBPayload(fromAVCCPayload: avccPayload)
    }

    private static func annexBPayload(fromAVCCPayload avccPayload: Data) throws -> Data {
        let bytes = [UInt8](avccPayload)
        var index = 0
        var payload = Data()
        while index < bytes.count {
            guard index + 4 <= bytes.count else {
                throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.malformedAVCCPayload
            }
            let nalLength = Int(bytes[index]) << 24
                | Int(bytes[index + 1]) << 16
                | Int(bytes[index + 2]) << 8
                | Int(bytes[index + 3])
            index += 4
            guard nalLength > 0, index + nalLength <= bytes.count else {
                throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.malformedAVCCPayload
            }
            appendAnnexBStartCode(to: &payload)
            payload.append(contentsOf: bytes[index..<(index + nalLength)])
            index += nalLength
        }
        return payload
    }

    private static func appendAnnexBStartCode(to payload: inout Data) {
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
    }

    static func accessUnitKind(from sampleBuffer: CMSampleBuffer) -> HelperVideoAccessUnitKind {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[CFString: Any]],
              let first = attachments.first,
              let isNotSync = first[kCMSampleAttachmentKey_NotSync] as? Bool
        else {
            return .keyframe
        }
        return isNotSync ? .delta : .keyframe
    }
}

private enum NaruHelperVideoToolboxSyntheticStatus {
    static let sampleBufferMissing: OSStatus = -1_700_001
    static let encoderPayloadExtractionFailed: OSStatus = -1_700_002
}

private extension HelperVideoFrameRateBucket {
    var nominalTimescale: CMTimeScale {
        switch self {
        case .unknown:
            return 30
        case .upTo15:
            return 15
        case .upTo30:
            return 30
        }
    }

    var syntheticFrameIntervalDuration: Duration {
        let milliseconds = max(1, 1_000 / Int(nominalTimescale))
        return .milliseconds(milliseconds)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
#endif
