import Foundation
import XCTest
@testable import NaruHelperKit
import NaruRemoteCore

#if os(macOS) && canImport(VideoToolbox)
import CoreVideo
import VideoToolbox
#endif

final class NaruHelperVideoKeyframeRequestTests: XCTestCase {
    private let pairingSecret = "test-pairing-secret"
    private let profileFingerprint = "sha256:test-profile"

    func testTwoRequestsBeforeConsumeCoalesceIntoOnePendingFlag() {
        let signal = NaruHelperVideoKeyframeRequestSignal()

        signal.request()
        signal.request()

        XCTAssertTrue(signal.consumePending())
        XCTAssertFalse(signal.consumePending())
    }

    #if canImport(Network)
    func testSignedRequestKeyframeFrameAuthorizesAndUnsignedDoesNot() throws {
        let handler = NaruHelperVideoTransportRequestHandler(
            expectedPairingSecret: pairingSecret,
            expectedProfileFingerprint: profileFingerprint,
            capabilityProvider: {
                HelperVideoCapabilityResponseBody(
                    availability: .available,
                    screenRecordingPermission: .granted,
                    codecSupport: .h264,
                    latencyModes: [.lowLatency]
                )
            }
        )
        let frame = try HelperVideoStreamNetworkClient.makeRequestKeyframeFrame(
            reason: .decoderRecovery,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret
        )
        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoKeyframeRequestBody>.self,
            from: frame
        )

        XCTAssertEqual(decoded.envelope.messageType, .requestKeyframe)
        XCTAssertEqual(decoded.envelope.body.reason, .decoderRecovery)
        XCTAssertEqual(handler.authorize(decoded.envelope), .accepted)

        var unsigned = decoded.envelope
        unsigned.authProof = nil
        XCTAssertEqual(handler.authorize(unsigned).status, .rejected)
        XCTAssertEqual(handler.authorize(unsigned).safeFailureCode, .authFailed)
    }

    func testOpenedStreamInboundAuthAcceptsSignedKeyframeRequestOnly() throws {
        let pipeline = NaruHelperVideoStreamFramePipeline(
            requestHandler: NaruHelperVideoTransportRequestHandler(
                expectedPairingSecret: pairingSecret,
                expectedProfileFingerprint: profileFingerprint,
                capabilityProvider: {
                    HelperVideoCapabilityResponseBody(
                        availability: .available,
                        screenRecordingPermission: .granted,
                        codecSupport: .h264,
                        latencyModes: [.lowLatency]
                    )
                }
            ),
            accessUnitSource: NaruHelperVideoStaticAccessUnitSource(accessUnits: [
                NaruHelperVideoAccessUnit(
                    sequence: 0,
                    kind: .keyframe,
                    binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
                )
            ])
        )
        let start = NaruHelperVideoTransportRequestHandler.signedEnvelope(
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            body: HelperVideoStartStreamRequestBody()
        )
        let opened = try pipeline.openFrameStream(
            forStartStreamFrame: try HelperVideoWireCodec.frame(start)
        )

        XCTAssertTrue(opened.isAccepted)
        XCTAssertFalse(opened.keyframeRequestSignal.consumePending())

        let unsigned = HelperVideoWireEnvelope(
            messageType: .requestKeyframe,
            profileFingerprint: profileFingerprint,
            body: HelperVideoKeyframeRequestBody(reason: .decoderRecovery)
        )
        opened.considerInboundControlFrame(try HelperVideoWireCodec.frame(unsigned))
        XCTAssertFalse(opened.keyframeRequestSignal.consumePending())

        opened.considerInboundControlFrame(
            try HelperVideoStreamNetworkClient.makeRequestKeyframeFrame(
                reason: .decoderRecovery,
                profileFingerprint: profileFingerprint,
                pairingSecret: "wrong-secret"
            )
        )
        XCTAssertFalse(opened.keyframeRequestSignal.consumePending())

        opened.considerInboundControlFrame(try HelperVideoWireCodec.frame(start))
        XCTAssertFalse(opened.keyframeRequestSignal.consumePending())

        opened.considerInboundControlFrame(
            try HelperVideoStreamNetworkClient.makeRequestKeyframeFrame(
                reason: .decoderRecovery,
                profileFingerprint: profileFingerprint,
                pairingSecret: pairingSecret
            )
        )
        XCTAssertTrue(opened.keyframeRequestSignal.consumePending())
        XCTAssertFalse(opened.keyframeRequestSignal.consumePending())
    }
    #endif

    #if os(macOS) && canImport(VideoToolbox)
    func testSignalBetweenFramesForcesKeyframeWhereIntervalWouldEmitDelta() async throws {
        let signal = NaruHelperVideoKeyframeRequestSignal()
        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: 64,
            height: 64,
            frameRateBucket: .upTo15,
            keyFrameInterval: 30
        )
        let pixelBuffers = AsyncThrowingStream<CVPixelBuffer, any Error> { continuation in
            let producer = Task.detached {
                do {
                    let first = try Self.makePixelBuffer(width: 64, height: 64, frameIndex: 0)
                    nonisolated(unsafe) let transferableFirst = first
                    continuation.yield(transferableFirst)
                    try await Task.sleep(for: .milliseconds(80))
                    signal.request()
                    let second = try Self.makePixelBuffer(width: 64, height: 64, frameIndex: 1)
                    nonisolated(unsafe) let transferableSecond = second
                    continuation.yield(transferableSecond)
                    let third = try Self.makePixelBuffer(width: 64, height: 64, frameIndex: 2)
                    nonisolated(unsafe) let transferableThird = third
                    continuation.yield(transferableThird)
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
        let accessUnits = try await Self.collectAccessUnits(from: stream)
        let media = accessUnits.filter { $0.kind != .parameterSet }

        XCTAssertGreaterThanOrEqual(media.count, 2)
        XCTAssertEqual(media[0].kind, .keyframe)
        XCTAssertEqual(
            media[1].kind,
            .keyframe,
            "A latched keyframe request must force the next encoded AU at an index the interval would emit as delta."
        )
    }

    func testTwoRequestsBeforeNextFrameForceExactlyOneKeyframe() async throws {
        let signal = NaruHelperVideoKeyframeRequestSignal()
        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: 64,
            height: 64,
            frameRateBucket: .upTo15,
            keyFrameInterval: 30
        )
        let pixelBuffers = AsyncThrowingStream<CVPixelBuffer, any Error> { continuation in
            let producer = Task.detached {
                do {
                    let first = try Self.makePixelBuffer(width: 64, height: 64, frameIndex: 0)
                    nonisolated(unsafe) let transferableFirst = first
                    continuation.yield(transferableFirst)
                    try await Task.sleep(for: .milliseconds(80))
                    signal.request()
                    signal.request()
                    let second = try Self.makePixelBuffer(width: 64, height: 64, frameIndex: 1)
                    nonisolated(unsafe) let transferableSecond = second
                    continuation.yield(transferableSecond)
                    let third = try Self.makePixelBuffer(width: 64, height: 64, frameIndex: 2)
                    nonisolated(unsafe) let transferableThird = third
                    continuation.yield(transferableThird)
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
        let accessUnits = try await Self.collectAccessUnits(from: stream)
        let media = accessUnits.filter { $0.kind != .parameterSet }

        XCTAssertGreaterThanOrEqual(media.count, 3)
        XCTAssertEqual(media[0].kind, .keyframe)
        XCTAssertEqual(media[1].kind, .keyframe)
        XCTAssertEqual(media[2].kind, .delta)
        XCTAssertFalse(signal.consumePending())
    }
    #endif

    #if os(macOS) && canImport(VideoToolbox)
    func testRequestCoincidingWithIntervalKeyframeDoesNotLeakIntoNextFrame() async throws {
        // Lead review 2026-08-20: with short-circuit evaluation the latch was
        // only consumed when the interval did NOT already force a keyframe, so
        // a request landing on an interval tick leaked into the next frame as
        // a redundant IDR. The latch must be consumed every frame.
        let signal = NaruHelperVideoKeyframeRequestSignal()
        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: 64,
            height: 64,
            frameRateBucket: .upTo15,
            keyFrameInterval: 2
        )
        // A wall-clock sleep is not enough to place the request between two
        // specific frames (VT session prepare can outlast it — measured: the
        // request drained at index 1). Gate the producer on the collector's
        // observed media count instead.
        let encodedMediaCount = EncodedMediaCounter()
        let pixelBuffers = AsyncThrowingStream<CVPixelBuffer, any Error> { continuation in
            let producer = Task.detached {
                do {
                    for frameIndex in 0..<2 {
                        let buffer = try Self.makePixelBuffer(
                            width: 64,
                            height: 64,
                            frameIndex: frameIndex
                        )
                        nonisolated(unsafe) let transferable = buffer
                        continuation.yield(transferable)
                    }
                    // Wait until both are actually encoded, then latch right
                    // before index 2 — which the interval (2) already forces
                    // as a keyframe.
                    var waitAttempts = 0
                    while encodedMediaCount.value < 2, waitAttempts < 250 {
                        waitAttempts += 1
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    signal.request()
                    for frameIndex in 2..<4 {
                        let buffer = try Self.makePixelBuffer(
                            width: 64,
                            height: 64,
                            frameIndex: frameIndex
                        )
                        nonisolated(unsafe) let transferable = buffer
                        continuation.yield(transferable)
                    }
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

        XCTAssertGreaterThanOrEqual(media.count, 4)
        XCTAssertEqual(
            media[1].kind,
            .delta,
            "Coordination guard: the request must not have drained before index 2 — a keyframe here means the producer/encoder gate failed and the test is vacuous."
        )
        XCTAssertEqual(media[2].kind, .keyframe)
        XCTAssertEqual(
            media[3].kind,
            .delta,
            "A request satisfied by a coinciding interval keyframe must clear the latch instead of leaking a redundant IDR into the next frame."
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

    private static func collectAccessUnits(
        from stream: AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error>
    ) async throws -> [NaruHelperVideoAccessUnit] {
        var accessUnits: [NaruHelperVideoAccessUnit] = []
        for try await accessUnit in stream {
            accessUnits.append(accessUnit)
        }
        return accessUnits
    }
    #endif
}
