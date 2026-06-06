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
    case noEncodedAccessUnits
}

public struct NaruHelperVideoToolboxSyntheticAccessUnitSource: NaruHelperVideoAccessUnitSource {
    public var frameCount: Int
    public var width: Int32
    public var height: Int32

    public init(
        frameCount: Int = 2,
        width: Int32 = 64,
        height: Int32 = 64
    ) {
        self.frameCount = max(frameCount, 1)
        self.width = width
        self.height = height
    }

    public func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        #if os(macOS) && canImport(VideoToolbox)
        let encoder = LiveNaruHelperVideoToolboxSyntheticAccessUnitEncoder(
            frameCount: frameCount,
            width: width,
            height: height,
            frameRateBucket: request.maxFrameRateBucket
        )
        return try encoder.encode()
        #else
        throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.unsupportedPlatform
        #endif
    }
}

#if os(macOS) && canImport(CoreMedia) && canImport(CoreVideo) && canImport(VideoToolbox)
private final class LiveNaruHelperVideoToolboxSyntheticAccessUnitEncoder {
    private let frameCount: Int
    private let width: Int32
    private let height: Int32
    private let frameRateBucket: HelperVideoFrameRateBucket

    init(
        frameCount: Int,
        width: Int32,
        height: Int32,
        frameRateBucket: HelperVideoFrameRateBucket
    ) {
        self.frameCount = max(frameCount, 1)
        self.width = width
        self.height = height
        self.frameRateBucket = frameRateBucket
    }

    func encode() throws -> [NaruHelperVideoAccessUnit] {
        guard width > 0, height > 0 else {
            throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError.invalidFrameSize
        }

        let collector = LiveNaruHelperVideoToolboxOutputCollector()
        var session: VTCompressionSession?
        let encoderSpecification: CFDictionary = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any,
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: kCFBooleanTrue as Any
        ] as CFDictionary
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
        for index in 0..<frameCount {
            let pixelBuffer = try Self.makePixelBuffer(
                width: width,
                height: height,
                frameIndex: index
            )
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

    private static let outputCallback: VTCompressionOutputCallback = {
        refcon,
        _,
        status,
        _,
        sampleBuffer
    in
        guard let refcon else {
            return
        }
        let collector = Unmanaged<LiveNaruHelperVideoToolboxOutputCollector>
            .fromOpaque(refcon)
            .takeUnretainedValue()
        collector.record(status: status, sampleBuffer: sampleBuffer)
    }

    private static func forceKeyframeProperties() -> CFDictionary {
        [
            kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue as Any
        ] as CFDictionary
    }

    private func configure(_ session: VTCompressionSession) throws {
        let properties: [(CFString, CFTypeRef)] = [
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),
            (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel),
            (kVTCompressionPropertyKey_MaxKeyFrameInterval, frameCount as CFNumber),
            (kVTCompressionPropertyKey_ExpectedFrameRate, frameRateBucket.nominalTimescale as CFNumber)
        ]

        for (key, value) in properties {
            let status = VTSessionSetProperty(session, key: key, value: value)
            guard status == noErr else {
                throw NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                    .compressionSessionConfigurationFailed(status)
            }
        }
    }

    private static func makePixelBuffer(
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

    func record(status: OSStatus, sampleBuffer: CMSampleBuffer?) {
        lock.withLock {
            guard status == noErr else {
                statusError = status
                return
            }
            guard let sampleBuffer else {
                statusError = NaruHelperVideoToolboxSyntheticStatus.sampleBufferMissing
                return
            }

            do {
                if parameterSetPayload == nil {
                    parameterSetPayload = try Self.parameterSetAnnexBPayload(from: sampleBuffer)
                }
                let payload = try Self.mediaAnnexBPayload(from: sampleBuffer)
                guard !payload.isEmpty else {
                    return
                }
                encodedSamples.append((
                    kind: Self.accessUnitKind(from: sampleBuffer),
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

    private static func parameterSetAnnexBPayload(from sampleBuffer: CMSampleBuffer) throws -> Data {
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

    private static func mediaAnnexBPayload(from sampleBuffer: CMSampleBuffer) throws -> Data {
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

    private static func accessUnitKind(from sampleBuffer: CMSampleBuffer) -> HelperVideoAccessUnitKind {
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
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
#endif
