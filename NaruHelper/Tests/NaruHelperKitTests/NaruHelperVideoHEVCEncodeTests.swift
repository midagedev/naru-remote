import Foundation
import XCTest
@testable import NaruHelperKit
import NaruRemoteCore

#if os(macOS) && canImport(VideoToolbox)
import CoreVideo
import VideoToolbox
#endif

final class NaruHelperVideoHEVCEncodeTests: XCTestCase {
    func testHEVCRateControlRowsAreTwoThirdsOfH264AndH264RowsStayUnchanged() {
        let h264Readability15 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .readability,
            frameRateBucket: .upTo15
        )
        let h264Readability30 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .readability,
            frameRateBucket: .upTo30
        )
        let h264Balanced15 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .balanced,
            frameRateBucket: .upTo15
        )
        let h264Balanced30 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .balanced,
            frameRateBucket: .upTo30
        )
        let h264Fidelity15 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .fidelity,
            frameRateBucket: .upTo15
        )
        let h264Fidelity30 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .fidelity,
            frameRateBucket: .upTo30
        )

        XCTAssertEqual(h264Readability15.averageBitRate, 1_200_000)
        XCTAssertEqual(h264Readability30.averageBitRate, 1_800_000)
        XCTAssertEqual(h264Balanced15.averageBitRate, 2_400_000)
        XCTAssertEqual(h264Balanced30.averageBitRate, 3_600_000)
        XCTAssertEqual(h264Fidelity15.averageBitRate, 4_000_000)
        XCTAssertEqual(h264Fidelity30.averageBitRate, 6_000_000)

        let hevcReadability15 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .readability,
            frameRateBucket: .upTo15,
            codec: .hevc
        )
        let hevcReadability30 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .readability,
            frameRateBucket: .upTo30,
            codec: .hevc
        )
        let hevcBalanced15 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .balanced,
            frameRateBucket: .upTo15,
            codec: .hevc
        )
        let hevcBalanced30 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .balanced,
            frameRateBucket: .upTo30,
            codec: .hevc
        )
        let hevcFidelity15 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .fidelity,
            frameRateBucket: .upTo15,
            codec: .hevc
        )
        let hevcFidelity30 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .fidelity,
            frameRateBucket: .upTo30,
            codec: .hevc
        )
        let hevcUnknownFrameRate = NaruHelperVideoRateControlPolicy(
            qualityBucket: .readability,
            frameRateBucket: .unknown,
            codec: .hevc
        )

        XCTAssertEqual(hevcReadability15.averageBitRate, 800_000)
        XCTAssertEqual(hevcReadability30.averageBitRate, 1_200_000)
        XCTAssertEqual(hevcBalanced15.averageBitRate, 1_600_000)
        XCTAssertEqual(hevcBalanced30.averageBitRate, 2_400_000)
        XCTAssertEqual(hevcFidelity15.averageBitRate, 2_700_000)
        XCTAssertEqual(hevcFidelity30.averageBitRate, 4_000_000)
        XCTAssertEqual(hevcUnknownFrameRate.averageBitRate, hevcReadability30.averageBitRate)
    }

    #if os(macOS) && canImport(VideoToolbox)
    func testHEVCParameterSetAccessUnitContainsVPSAndSPSAndPPS() throws {
        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: 64,
            height: 64,
            frameRateBucket: .upTo15,
            keyFrameInterval: 2,
            codec: .hevc
        )
        let accessUnits = try encoder.encode(pixelBuffers: [
            try Self.makePixelBuffer(width: 64, height: 64, frameIndex: 0),
            try Self.makePixelBuffer(width: 64, height: 64, frameIndex: 1)
        ])

        XCTAssertEqual(accessUnits.first?.kind, .parameterSet)
        let types = Set(Self.hevcNALTypes(in: try XCTUnwrap(accessUnits.first?.binaryPayload)))
        XCTAssertTrue(types.contains(32), "HEVC parameter-set AU must include VPS")
        XCTAssertTrue(types.contains(33), "HEVC parameter-set AU must include SPS")
        XCTAssertTrue(types.contains(34), "HEVC parameter-set AU must include PPS")
        XCTAssertTrue(accessUnits.dropFirst().contains { $0.kind == .keyframe })
    }

    func testHEVCKeyframeSignalForcesIDRMidStream() async throws {
        let signal = NaruHelperVideoKeyframeRequestSignal()
        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: 64,
            height: 64,
            frameRateBucket: .upTo15,
            keyFrameInterval: 30,
            codec: .hevc
        )
        let encodedMediaCount = EncodedMediaCounter()
        let pixelBuffers = AsyncThrowingStream<CVPixelBuffer, any Error> { continuation in
            let producer = Task.detached {
                do {
                    let first = try Self.makePixelBuffer(width: 64, height: 64, frameIndex: 0)
                    nonisolated(unsafe) let transferableFirst = first
                    continuation.yield(transferableFirst)
                    var waitAttempts = 0
                    while encodedMediaCount.value < 1, waitAttempts < 250 {
                        waitAttempts += 1
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    signal.request()
                    let second = try Self.makePixelBuffer(width: 64, height: 64, frameIndex: 1)
                    nonisolated(unsafe) let transferableSecond = second
                    continuation.yield(transferableSecond)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                producer.cancel()
            }
        }

        let stream = try encoder.encode(
            pixelBuffers: pixelBuffers,
            keyframeSignal: signal
        )
        var accessUnits: [NaruHelperVideoAccessUnit] = []
        for try await accessUnit in stream {
            accessUnits.append(accessUnit)
            if accessUnit.kind != .parameterSet {
                encodedMediaCount.increment()
            }
        }
        let media = accessUnits.filter { $0.kind != .parameterSet }

        XCTAssertGreaterThanOrEqual(media.count, 2)
        XCTAssertEqual(media[0].kind, .keyframe)
        XCTAssertEqual(
            media[1].kind,
            .keyframe,
            "A latched keyframe request must force the next encoded HEVC AU at an index the interval would emit as delta."
        )
    }

    private final class EncodedMediaCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }
    }

    private static func makePixelBuffer(
        width: Int,
        height: Int,
        frameIndex: Int
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let createStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ] as CFDictionary,
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
        let bytes = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = UInt8((x + frameIndex * 11) & 0xFF)
                bytes[offset + 1] = UInt8((y * 2 + frameIndex * 17) & 0xFF)
                bytes[offset + 2] = UInt8((x + y + frameIndex * 23) & 0xFF)
                bytes[offset + 3] = 0xFF
            }
        }
        return pixelBuffer
    }

    private static func hevcNALTypes(in annexBPayload: Data) -> [UInt8] {
        let bytes = [UInt8](annexBPayload)
        var index = 0
        var types: [UInt8] = []
        while index + 2 < bytes.count {
            guard bytes[index] == 0, bytes[index + 1] == 0 else {
                index += 1
                continue
            }

            if bytes[index + 2] == 1 {
                if index + 3 < bytes.count {
                    types.append((bytes[index + 3] >> 1) & 0x3F)
                }
                index += 3
                continue
            }

            if index + 3 < bytes.count, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                if index + 4 < bytes.count {
                    types.append((bytes[index + 4] >> 1) & 0x3F)
                }
                index += 4
                continue
            }

            index += 1
        }
        return types
    }
    #endif
}
