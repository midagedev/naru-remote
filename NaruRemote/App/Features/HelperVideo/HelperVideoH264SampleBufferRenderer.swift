import Foundation
import NaruRemoteCore

#if canImport(AVFoundation) && canImport(CoreMedia)
@preconcurrency import AVFoundation
@preconcurrency import CoreMedia

public struct HelperVideoH264FrameDimensions: Equatable, Sendable {
    public var width: Int32
    public var height: Int32

    public init(width: Int32, height: Int32) {
        self.width = max(width, 0)
        self.height = max(height, 0)
    }
}

public enum HelperVideoH264SampleBufferFactoryError: Error, Equatable, LocalizedError {
    case unexpectedMessageType(HelperVideoMessageType)
    case missingBinaryPayload
    case invalidAnnexBPayload
    case missingParameterSets
    case formatDescriptionCreationFailed(OSStatus)
    case blockBufferCreationFailed(OSStatus)
    case blockBufferCopyFailed(OSStatus)
    case sampleBufferCreationFailed(OSStatus)
    case displayLayerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unexpectedMessageType(let messageType):
            return "Helper video expected access-unit message, received \(messageType.rawValue)."
        case .missingBinaryPayload:
            return "Helper video access unit did not include a binary payload."
        case .invalidAnnexBPayload:
            return "Helper video H.264 payload is not Annex-B start-code framed."
        case .missingParameterSets:
            return "Helper video H.264 stream has no cached SPS/PPS parameter sets."
        case .formatDescriptionCreationFailed(let status):
            return "Helper video H.264 format description failed with status \(status)."
        case .blockBufferCreationFailed(let status):
            return "Helper video H.264 block buffer creation failed with status \(status)."
        case .blockBufferCopyFailed(let status):
            return "Helper video H.264 block buffer copy failed with status \(status)."
        case .sampleBufferCreationFailed(let status):
            return "Helper video H.264 sample buffer creation failed with status \(status)."
        case .displayLayerFailed(let message):
            return "Helper video display layer failed: \(message)"
        }
    }
}

struct HelperVideoH264NALUnit: Equatable, Sendable {
    var type: UInt8
    var payload: Data

    var isParameterSet: Bool {
        type == 7 || type == 8
    }
}

enum HelperVideoH264AnnexBParser {
    static func parse(_ payload: Data) throws -> [HelperVideoH264NALUnit] {
        let bytes = [UInt8](payload)
        let startCodes = startCodeBoundaries(in: bytes)
        guard !startCodes.isEmpty else {
            throw HelperVideoH264SampleBufferFactoryError.invalidAnnexBPayload
        }

        let units = startCodes.enumerated().compactMap { index, boundary -> HelperVideoH264NALUnit? in
            let payloadStart = boundary.nalStart
            let payloadEnd = index + 1 < startCodes.count
                ? startCodes[index + 1].codeStart
                : bytes.count
            guard payloadStart < payloadEnd else {
                return nil
            }

            let nalPayload = Data(bytes[payloadStart..<payloadEnd])
            guard let firstByte = nalPayload.first else {
                return nil
            }
            return HelperVideoH264NALUnit(type: firstByte & 0x1F, payload: nalPayload)
        }

        guard !units.isEmpty else {
            throw HelperVideoH264SampleBufferFactoryError.invalidAnnexBPayload
        }
        return units
    }

    private static func startCodeBoundaries(in bytes: [UInt8]) -> [(codeStart: Int, nalStart: Int)] {
        var boundaries: [(codeStart: Int, nalStart: Int)] = []
        var index = 0

        while index + 2 < bytes.count {
            guard bytes[index] == 0, bytes[index + 1] == 0 else {
                index += 1
                continue
            }

            if bytes[index + 2] == 1 {
                boundaries.append((codeStart: index, nalStart: index + 3))
                index += 3
                continue
            }

            if index + 3 < bytes.count, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                boundaries.append((codeStart: index, nalStart: index + 4))
                index += 4
                continue
            }

            index += 1
        }

        return boundaries
    }
}

public final class HelperVideoH264SampleBufferFactory {
    public private(set) var cachedFormatDimensions: HelperVideoH264FrameDimensions?

    private var cachedFormatDescription: CMVideoFormatDescription?
    private var nextPresentationValue: CMTimeValue = 0
    private let timescale: CMTimeScale

    public init(timescale: CMTimeScale = 30) {
        self.timescale = max(timescale, 1)
    }

    @discardableResult
    public func makeSampleBuffer(
        from decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) throws -> CMSampleBuffer? {
        guard let payload = decoded.binaryPayload else {
            throw HelperVideoH264SampleBufferFactoryError.missingBinaryPayload
        }
        return try makeSampleBuffer(from: decoded.envelope, binaryPayload: payload)
    }

    @discardableResult
    public func makeSampleBuffer(
        from envelope: HelperVideoWireEnvelope<HelperVideoAccessUnitBody>,
        binaryPayload: Data
    ) throws -> CMSampleBuffer? {
        guard envelope.messageType == .videoAccessUnit else {
            throw HelperVideoH264SampleBufferFactoryError.unexpectedMessageType(envelope.messageType)
        }

        if envelope.body.kind == .endOfStream {
            reset()
            return nil
        }

        let nalUnits = try HelperVideoH264AnnexBParser.parse(binaryPayload)
        try updateCachedFormatDescriptionIfPresent(in: nalUnits)

        if envelope.body.kind == .parameterSet {
            return nil
        }

        guard let formatDescription = cachedFormatDescription else {
            throw HelperVideoH264SampleBufferFactoryError.missingParameterSets
        }

        let mediaUnits = nalUnits.filter { !$0.isParameterSet }
        guard !mediaUnits.isEmpty else {
            return nil
        }

        let samplePayload = avccPayload(from: mediaUnits)
        let blockBuffer = try makeBlockBuffer(from: samplePayload)
        let sampleBuffer = try makeReadySampleBuffer(
            blockBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleByteCount: samplePayload.count
        )
        nextPresentationValue += 1
        return sampleBuffer
    }

    public func reset() {
        cachedFormatDescription = nil
        cachedFormatDimensions = nil
        nextPresentationValue = 0
    }

    private func updateCachedFormatDescriptionIfPresent(in nalUnits: [HelperVideoH264NALUnit]) throws {
        guard let sps = nalUnits.last(where: { $0.type == 7 })?.payload,
              let pps = nalUnits.last(where: { $0.type == 8 })?.payload else {
            return
        }

        try sps.withUnsafeBytes { spsBytes in
            try pps.withUnsafeBytes { ppsBytes in
                guard let spsBase = spsBytes.bindMemory(to: UInt8.self).baseAddress,
                      let ppsBase = ppsBytes.bindMemory(to: UInt8.self).baseAddress else {
                    throw HelperVideoH264SampleBufferFactoryError.missingParameterSets
                }

                var parameterSetPointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                var parameterSetSizes: [Int] = [sps.count, pps.count]
                var formatDescription: CMVideoFormatDescription?
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: parameterSetPointers.count,
                    parameterSetPointers: &parameterSetPointers,
                    parameterSetSizes: &parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDescription
                )

                guard status == noErr, let formatDescription else {
                    throw HelperVideoH264SampleBufferFactoryError
                        .formatDescriptionCreationFailed(status)
                }

                cachedFormatDescription = formatDescription
                let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                cachedFormatDimensions = HelperVideoH264FrameDimensions(
                    width: dimensions.width,
                    height: dimensions.height
                )
            }
        }
    }

    private func avccPayload(from nalUnits: [HelperVideoH264NALUnit]) -> Data {
        nalUnits.reduce(into: Data()) { data, nalUnit in
            var length = UInt32(nalUnit.payload.count).bigEndian
            data.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
            data.append(nalUnit.payload)
        }
    }

    private func makeBlockBuffer(from samplePayload: Data) throws -> CMBlockBuffer {
        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: samplePayload.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: samplePayload.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard createStatus == noErr, let blockBuffer else {
            throw HelperVideoH264SampleBufferFactoryError.blockBufferCreationFailed(createStatus)
        }

        let copyStatus = samplePayload.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return kCMBlockBufferBadPointerParameterErr
            }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: samplePayload.count
            )
        }

        guard copyStatus == noErr else {
            throw HelperVideoH264SampleBufferFactoryError.blockBufferCopyFailed(copyStatus)
        }

        return blockBuffer
    }

    private func makeReadySampleBuffer(
        blockBuffer: CMBlockBuffer,
        formatDescription: CMVideoFormatDescription,
        sampleByteCount: Int
    ) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: timescale),
            presentationTimeStamp: CMTime(value: nextPresentationValue, timescale: timescale),
            decodeTimeStamp: .invalid
        )
        var sampleSize = sampleByteCount
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sampleBuffer else {
            throw HelperVideoH264SampleBufferFactoryError.sampleBufferCreationFailed(status)
        }

        return sampleBuffer
    }
}

private struct HelperVideoPreparedSampleBuffer: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
}

private actor HelperVideoH264SampleBufferPreparationPipeline {
    private let factory: HelperVideoH264SampleBufferFactory

    init(factory: HelperVideoH264SampleBufferFactory) {
        self.factory = factory
    }

    func makeSampleBuffer(
        from decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) throws -> HelperVideoPreparedSampleBuffer? {
        try factory.makeSampleBuffer(from: decoded)
            .map { HelperVideoPreparedSampleBuffer(sampleBuffer: $0) }
    }

    func reset() {
        factory.reset()
    }
}

public final class HelperVideoH264SampleBufferRenderer {
    public let displayLayer: AVSampleBufferDisplayLayer

    private let preparationPipeline: HelperVideoH264SampleBufferPreparationPipeline

    public init(
        displayLayer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer(),
        factory: sending HelperVideoH264SampleBufferFactory = HelperVideoH264SampleBufferFactory()
    ) {
        self.displayLayer = displayLayer
        self.preparationPipeline = HelperVideoH264SampleBufferPreparationPipeline(factory: factory)
        self.displayLayer.videoGravity = .resizeAspect
    }

    @discardableResult
    @MainActor
    public func enqueue(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) async throws -> CMSampleBuffer? {
        guard let prepared = try await preparationPipeline.makeSampleBuffer(from: decoded) else {
            return nil
        }
        let sampleBuffer = prepared.sampleBuffer

        if displayLayer.status == .failed {
            displayLayer.flushAndRemoveImage()
        }

        displayLayer.enqueue(sampleBuffer)
        if displayLayer.status == .failed {
            throw HelperVideoH264SampleBufferFactoryError.displayLayerFailed(
                displayLayer.error?.localizedDescription ?? "Unknown display layer error."
            )
        }
        return sampleBuffer
    }

    @MainActor
    public func flush() async {
        await preparationPipeline.reset()
        displayLayer.flush()
    }
}

extension HelperVideoH264SampleBufferRenderer: HelperVideoAccessUnitRendering {
    @discardableResult
    public func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) async throws -> Bool {
        try await enqueue(decoded) != nil
    }
}
#endif
