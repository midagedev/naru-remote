import Foundation
import XCTest
@testable import NaruHelperKit
import NaruRemoteCore

#if os(macOS) && canImport(VideoToolbox)
import CoreVideo
import VideoToolbox
#endif

#if os(macOS) && canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

final class NaruHelperVideoEncoderPrototypeTests: XCTestCase {
    func testFeatureFlagParsesOnlyExplicitEnabledValues() {
        XCTAssertTrue(
            NaruHelperVideoEncoderFeatureFlag.fromEnvironment(
                [NaruHelperVideoEncoderFeatureFlag.environmentKey: "1"]
            ).isEnabled
        )
        XCTAssertTrue(
            NaruHelperVideoEncoderFeatureFlag.fromEnvironment(
                [NaruHelperVideoEncoderFeatureFlag.environmentKey: "videotoolbox"]
            ).isEnabled
        )
        XCTAssertFalse(
            NaruHelperVideoEncoderFeatureFlag.fromEnvironment(
                [NaruHelperVideoEncoderFeatureFlag.environmentKey: "0"]
            ).isEnabled
        )
        XCTAssertFalse(NaruHelperVideoEncoderFeatureFlag.fromEnvironment([:]).isEnabled)
    }

    func testDisabledFeatureFlagDoesNotPrepareSession() {
        let recorder = VideoEncoderSessionProbeRecorder(result: .prepared)
        let probe = NaruHelperVideoEncoderPrototypeProbe(
            featureFlagProvider: { NaruHelperVideoEncoderFeatureFlag(isEnabled: false) },
            sessionProvider: {
                recorder.record()
            }
        )

        let response = probe.capability()

        XCTAssertEqual(response.availability, .disabled)
        XCTAssertEqual(response.featureFlagState, .disabled)
        XCTAssertEqual(response.encoderAPI, .videoToolbox)
        XCTAssertEqual(response.codec, .h264)
        XCTAssertEqual(response.codecProfile, .high)
        XCTAssertEqual(response.latencyMode, .lowLatency)
        XCTAssertEqual(response.qualityBucket, .readability)
        XCTAssertEqual(response.sessionState, .notStarted)
        XCTAssertEqual(response.safeFailureCode, .disabled)
        XCTAssertEqual(recorder.callCount, 0)
    }

    func testEnabledFeatureFlagWithPreparedSessionReportsAvailable() {
        let probe = NaruHelperVideoEncoderPrototypeProbe(
            featureFlagProvider: { NaruHelperVideoEncoderFeatureFlag(isEnabled: true) },
            sessionProvider: { .prepared }
        )

        let response = probe.capability()

        XCTAssertEqual(response.availability, .available)
        XCTAssertEqual(response.featureFlagState, .enabled)
        XCTAssertEqual(response.encoderAPI, .videoToolbox)
        XCTAssertEqual(response.codec, .h264)
        XCTAssertEqual(response.codecProfile, .high)
        XCTAssertEqual(response.latencyMode, .lowLatency)
        XCTAssertEqual(response.qualityBucket, .readability)
        XCTAssertEqual(response.sessionState, .prepared)
        XCTAssertNil(response.safeFailureCode)
    }

    func testEnabledFeatureFlagWithUnavailableSessionReportsCodecUnsupported() {
        let probe = NaruHelperVideoEncoderPrototypeProbe(
            featureFlagProvider: { NaruHelperVideoEncoderFeatureFlag(isEnabled: true) },
            sessionProvider: { .unavailable }
        )

        let response = probe.capability()

        XCTAssertEqual(response.availability, .codecUnsupported)
        XCTAssertEqual(response.featureFlagState, .enabled)
        XCTAssertEqual(response.encoderAPI, .videoToolbox)
        XCTAssertEqual(response.sessionState, .unavailable)
        XCTAssertEqual(response.safeFailureCode, .codecUnsupported)
    }

    func testUnsupportedPlatformOmitsEncoderAPI() {
        let probe = NaruHelperVideoEncoderPrototypeProbe(
            encoderAPI: nil,
            featureFlagProvider: { NaruHelperVideoEncoderFeatureFlag(isEnabled: true) },
            sessionProvider: { .unsupported }
        )

        let response = probe.capability()

        XCTAssertEqual(response.availability, .codecUnsupported)
        XCTAssertEqual(response.featureFlagState, .enabled)
        XCTAssertNil(response.encoderAPI)
        XCTAssertEqual(response.sessionState, .unsupported)
        XCTAssertEqual(response.safeFailureCode, .codecUnsupported)
    }

    func testEncoderPrototypeJSONUsesOnlyFixedCatalogValues() throws {
        let response = NaruHelperVideoEncoderPrototypeResponse(
            availability: .available,
            featureFlagState: .enabled,
            encoderAPI: .videoToolbox,
            sessionState: .prepared
        )

        let json = String(data: try JSONEncoder().encode(response), encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"availability\":\"available\""))
        XCTAssertTrue(json.contains("\"featureFlagState\":\"enabled\""))
        XCTAssertTrue(json.contains("\"encoderAPI\":\"videoToolbox\""))
        XCTAssertTrue(json.contains("\"codec\":\"h264\""))
        XCTAssertTrue(json.contains("\"codecProfile\":\"high\""))
        XCTAssertTrue(json.contains("\"latencyMode\":\"lowLatency\""))
        XCTAssertTrue(json.contains("\"qualityBucket\":\"readability\""))
        XCTAssertTrue(json.contains("\"sessionState\":\"prepared\""))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("display"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("dimension"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("endpoint"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("host"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("byte"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("payload"))
    }

    func testRateControlPolicyScalesByQualityAndFrameRateWithoutExportShape() {
        let readability15 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .readability,
            frameRateBucket: .upTo15
        )
        let readability30 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .readability,
            frameRateBucket: .upTo30
        )
        let balanced30 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .balanced,
            frameRateBucket: .upTo30
        )
        let fidelity30 = NaruHelperVideoRateControlPolicy(
            qualityBucket: .fidelity,
            frameRateBucket: .upTo30
        )
        let unknownFrameRate = NaruHelperVideoRateControlPolicy(
            qualityBucket: .readability,
            frameRateBucket: .unknown
        )

        XCTAssertEqual(readability15.averageBitRate, 1_200_000)
        XCTAssertEqual(readability15.dataRateLimits, [225_000, 1])
        XCTAssertGreaterThan(readability30.averageBitRate, readability15.averageBitRate)
        XCTAssertGreaterThan(balanced30.averageBitRate, readability30.averageBitRate)
        XCTAssertGreaterThan(fidelity30.averageBitRate, balanced30.averageBitRate)
        XCTAssertEqual(unknownFrameRate.averageBitRate, readability30.averageBitRate)
        XCTAssertEqual(unknownFrameRate.dataRateLimits, readability30.dataRateLimits)
    }

    #if os(macOS) && canImport(VideoToolbox) && canImport(ScreenCaptureKit)
    func testScreenCaptureKitPolicyScalesReadabilityAndUsesLowLatencyContinuousQueue() {
        let continuousReadability = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy
            .make(
                displayWidth: 6_016,
                displayHeight: 3_384,
                frameLimit: nil,
                qualityBucket: .readability
            )
        let finiteBalanced = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy
            .make(
                displayWidth: 6_016,
                displayHeight: 3_384,
                frameLimit: 30,
                qualityBucket: .balanced
            )
        let nativeFidelity = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy
            .make(
                displayWidth: 1_280,
                displayHeight: 721,
                frameLimit: nil,
                qualityBucket: .fidelity
            )

        XCTAssertEqual(continuousReadability.outputWidth, 960)
        XCTAssertEqual(continuousReadability.outputHeight, 540)
        XCTAssertEqual(continuousReadability.queueDepth, 3)
        XCTAssertEqual(finiteBalanced.outputWidth, 1_920)
        XCTAssertEqual(finiteBalanced.outputHeight, 1_080)
        XCTAssertEqual(finiteBalanced.queueDepth, 5)
        XCTAssertEqual(nativeFidelity.outputWidth, 1_280)
        XCTAssertEqual(nativeFidelity.outputHeight, 720)
        XCTAssertEqual(nativeFidelity.queueDepth, 3)
    }

    func testScreenCaptureKitWindowFallbackPolicyRejectsSystemAndOversizedWindows() {
        let policy = NaruHelperVideoScreenCaptureKitWindowFallbackPolicy.live

        XCTAssertTrue(policy.isUsable(
            width: 1_512,
            height: 982,
            applicationName: "Terminal"
        ))
        XCTAssertTrue(policy.isUsable(
            width: 640,
            height: 360,
            applicationName: nil
        ))
        XCTAssertFalse(policy.isUsable(
            width: 30_000,
            height: 30_000,
            applicationName: "Window Server"
        ))
        XCTAssertFalse(policy.isUsable(
            width: 1_512,
            height: 982,
            applicationName: "Window Server"
        ))
        XCTAssertFalse(policy.isUsable(
            width: 1_512,
            height: 982,
            applicationName: "loginwindow"
        ))
        XCTAssertFalse(policy.isUsable(
            width: 1_512,
            height: 982,
            applicationName: "Dock"
        ))
        XCTAssertFalse(policy.isUsable(
            width: 352,
            height: 152,
            applicationName: "제어 센터"
        ))
        XCTAssertFalse(policy.isUsable(
            width: 96,
            height: 64,
            applicationName: "Terminal"
        ))
    }

    func testScreenCaptureKitWindowFallbackPolicyPrefersCoreGraphicsFrontToBackMatch() {
        let policy = NaruHelperVideoScreenCaptureKitWindowFallbackPolicy.live
        let xcode = NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor(
            applicationName: "Xcode",
            title: "Devices",
            width: 1_184,
            height: 700
        )
        let stimulus = NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor(
            applicationName: "VNCLiveStimulusWindow",
            title: "Naru Video Probe",
            width: 942,
            height: 738
        )
        let shield = NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor(
            applicationName: "Window Server",
            title: "Display 1 Shield",
            width: 1_512,
            height: 982
        )

        let preferred = policy.preferredDescriptor(
            screenCaptureKitOrder: [xcode, stimulus],
            coreGraphicsFrontToBackOrder: [shield, stimulus, xcode],
            frontmostApplicationName: "loginwindow"
        )

        XCTAssertEqual(preferred, stimulus)
    }

    func testScreenCaptureKitWindowFallbackPolicyFallsBackToFrontmostAppWhenCoreGraphicsIsUnavailable() {
        let policy = NaruHelperVideoScreenCaptureKitWindowFallbackPolicy.live
        let xcode = NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor(
            applicationName: "Xcode",
            title: "Devices",
            width: 1_184,
            height: 700
        )
        let terminal = NaruHelperVideoScreenCaptureKitWindowFallbackDescriptor(
            applicationName: "Terminal",
            title: "Logs",
            width: 960,
            height: 720
        )

        let preferred = policy.preferredDescriptor(
            screenCaptureKitOrder: [xcode, terminal],
            coreGraphicsFrontToBackOrder: [],
            frontmostApplicationName: "Terminal"
        )

        XCTAssertEqual(preferred, terminal)
    }

    func testToolboxSyntheticAccessUnitSourceEmitsRealAnnexBParameterSetsAndFrame() throws {
        let source = NaruHelperVideoToolboxSyntheticAccessUnitSource(
            frameCount: 2,
            width: 64,
            height: 64
        )

        let accessUnits = try source.accessUnits(
            for: HelperVideoStartStreamRequestBody(maxFrameRateBucket: .upTo15)
        )

        XCTAssertGreaterThanOrEqual(accessUnits.count, 2)
        XCTAssertEqual(accessUnits[0].sequence, 0)
        XCTAssertEqual(accessUnits[0].kind, .parameterSet)
        XCTAssertTrue(Self.nalTypes(in: accessUnits[0].binaryPayload).contains(7))
        XCTAssertTrue(Self.nalTypes(in: accessUnits[0].binaryPayload).contains(8))
        XCTAssertTrue(accessUnits[0].binaryPayload.starts(with: Self.annexBStartCode))

        let mediaAccessUnits = accessUnits.dropFirst()
        XCTAssertTrue(mediaAccessUnits.contains { $0.kind == .keyframe })
        XCTAssertTrue(mediaAccessUnits.allSatisfy { $0.binaryPayload.starts(with: Self.annexBStartCode) })
        XCTAssertFalse(accessUnits.map(\.binaryPayload).contains(Data([0x65, 0x88])))
    }

    func testToolboxSyntheticAccessUnitSourceEmitsSustainedFrameBatch() throws {
        let source = NaruHelperVideoToolboxSyntheticAccessUnitSource(
            frameCount: 6,
            width: 64,
            height: 64
        )

        let accessUnits = try source.accessUnits(
            for: HelperVideoStartStreamRequestBody(maxFrameRateBucket: .upTo30)
        )

        XCTAssertEqual(accessUnits.map(\.sequence), Array(0..<accessUnits.count))
        XCTAssertGreaterThanOrEqual(accessUnits.count, 7)
        XCTAssertEqual(accessUnits[0].kind, .parameterSet)
        XCTAssertEqual(accessUnits.dropFirst().filter { $0.kind == .keyframe }.count, 1)
        XCTAssertGreaterThanOrEqual(accessUnits.dropFirst().filter { $0.kind == .delta }.count, 5)
        XCTAssertTrue(accessUnits.allSatisfy { $0.binaryPayload.starts(with: Self.annexBStartCode) })
    }

    func testToolboxSyntheticAccessUnitStreamEmitsFinitePacedFrames() async throws {
        let source = NaruHelperVideoToolboxSyntheticAccessUnitSource(
            frameCount: 4,
            width: 64,
            height: 64
        )

        let stream = try source.accessUnitStream(
            for: HelperVideoStartStreamRequestBody(maxFrameRateBucket: .upTo30)
        )
        let accessUnits = try await Self.collectAccessUnits(from: stream)

        XCTAssertEqual(accessUnits.map(\.sequence), Array(0..<accessUnits.count))
        XCTAssertGreaterThanOrEqual(accessUnits.count, 4)
        XCTAssertEqual(accessUnits[0].kind, .parameterSet)
        XCTAssertTrue(accessUnits.dropFirst().contains { $0.kind == .keyframe })
        XCTAssertTrue(accessUnits.allSatisfy { $0.binaryPayload.starts(with: Self.annexBStartCode) })
    }

    func testToolboxSyntheticAccessUnitStreamCanRunUnboundedUntilClientStopsReading() async throws {
        let source = NaruHelperVideoToolboxSyntheticAccessUnitSource(
            frameCount: 0,
            width: 64,
            height: 64
        )

        let stream = try source.accessUnitStream(
            for: HelperVideoStartStreamRequestBody(maxFrameRateBucket: .upTo30)
        )
        let accessUnits = try await Self.collectAccessUnits(from: stream, limit: 6)

        XCTAssertEqual(accessUnits.map(\.sequence), Array(0..<accessUnits.count))
        XCTAssertGreaterThanOrEqual(accessUnits.count, 6)
        XCTAssertEqual(accessUnits[0].kind, .parameterSet)
        XCTAssertGreaterThanOrEqual(accessUnits.dropFirst().count, 5)
    }

    func testToolboxPixelBufferEncoderRejectsEmptyFrameBatch() throws {
        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: 64,
            height: 64,
            frameRateBucket: .upTo15,
            keyFrameInterval: 2
        )

        XCTAssertThrowsError(try encoder.encode(pixelBuffers: [])) { error in
            XCTAssertEqual(
                error as? NaruHelperVideoToolboxSyntheticAccessUnitSourceError,
                .noSourceFrames
            )
        }
    }

    func testToolboxPixelBufferEncoderStoresRequestedRateControlPolicy() throws {
        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: 64,
            height: 64,
            frameRateBucket: .upTo15,
            qualityBucket: .balanced,
            keyFrameInterval: 2
        )

        XCTAssertEqual(
            encoder.rateControlPolicy,
            NaruHelperVideoRateControlPolicy(
                qualityBucket: .balanced,
                frameRateBucket: .upTo15
            )
        )
    }

    #if canImport(ScreenCaptureKit)
    func testScreenCaptureKitAccessUnitSourceEncodesInjectedPixelBuffers() throws {
        let provider = StubScreenCaptureKitPixelBufferProvider(pixelBuffers: [
            try Self.makePixelBuffer(width: 80, height: 48, frameIndex: 0),
            try Self.makePixelBuffer(width: 80, height: 48, frameIndex: 1)
        ])
        let source = NaruHelperVideoScreenCaptureKitAccessUnitSource(
            frameCount: 2,
            pixelBufferProvider: provider
        )

        let accessUnits = try source.accessUnits(
            for: HelperVideoStartStreamRequestBody(maxFrameRateBucket: .upTo15)
        )

        XCTAssertEqual(provider.requests, [
            StubScreenCaptureKitPixelBufferProvider.Request(
                frameLimit: 2,
                frameRateBucket: .upTo15
            )
        ])
        XCTAssertGreaterThanOrEqual(accessUnits.count, 2)
        XCTAssertEqual(accessUnits[0].kind, .parameterSet)
        XCTAssertTrue(Self.nalTypes(in: accessUnits[0].binaryPayload).contains(7))
        XCTAssertTrue(Self.nalTypes(in: accessUnits[0].binaryPayload).contains(8))
        XCTAssertTrue(accessUnits.dropFirst().contains { $0.kind == .keyframe })
        XCTAssertTrue(accessUnits.allSatisfy { $0.binaryPayload.starts(with: Self.annexBStartCode) })
    }

    func testScreenCaptureKitAccessUnitSourceStreamsInjectedPixelBuffers() async throws {
        let provider = StubScreenCaptureKitPixelBufferProvider(pixelBuffers: [
            try Self.makePixelBuffer(width: 80, height: 48, frameIndex: 0),
            try Self.makePixelBuffer(width: 80, height: 48, frameIndex: 1),
            try Self.makePixelBuffer(width: 80, height: 48, frameIndex: 2)
        ])
        let source = NaruHelperVideoScreenCaptureKitAccessUnitSource(
            frameCount: 3,
            pixelBufferProvider: provider
        )

        let stream = try source.accessUnitStream(
            for: HelperVideoStartStreamRequestBody(maxFrameRateBucket: .upTo15)
        )
        let accessUnits = try await Self.collectAccessUnits(from: stream)

        XCTAssertEqual(provider.streamRequests, [
            StubScreenCaptureKitPixelBufferProvider.StreamRequest(
                frameLimit: 3,
                frameRateBucket: .upTo15
            )
        ])
        XCTAssertEqual(accessUnits.map(\.sequence), Array(0..<accessUnits.count))
        XCTAssertGreaterThanOrEqual(accessUnits.count, 3)
        XCTAssertEqual(accessUnits[0].kind, .parameterSet)
        XCTAssertTrue(accessUnits.dropFirst().contains { $0.kind == .keyframe })
        XCTAssertTrue(accessUnits.allSatisfy { $0.binaryPayload.starts(with: Self.annexBStartCode) })
    }

    func testScreenCaptureKitFrameStatusPolicyAcceptsStartedFramesOnlyWhenBuffered() {
        XCTAssertTrue(
            NaruHelperVideoScreenCaptureKitFrameSamplePolicy.isDisplayableScreenFrame(
                rawStatus: nil,
                hasImageBuffer: false
            )
        )
        XCTAssertTrue(
            NaruHelperVideoScreenCaptureKitFrameSamplePolicy.isDisplayableScreenFrame(
                rawStatus: SCFrameStatus.complete.rawValue,
                hasImageBuffer: false
            )
        )
        XCTAssertTrue(
            NaruHelperVideoScreenCaptureKitFrameSamplePolicy.isDisplayableScreenFrame(
                rawStatus: SCFrameStatus.started.rawValue,
                hasImageBuffer: true
            )
        )
        XCTAssertFalse(
            NaruHelperVideoScreenCaptureKitFrameSamplePolicy.isDisplayableScreenFrame(
                rawStatus: SCFrameStatus.started.rawValue,
                hasImageBuffer: false
            )
        )
        XCTAssertFalse(
            NaruHelperVideoScreenCaptureKitFrameSamplePolicy.isDisplayableScreenFrame(
                rawStatus: SCFrameStatus.idle.rawValue,
                hasImageBuffer: true
            )
        )
    }

    func testScreenCaptureKitStartedOrIdleCallbacksDoNotBecomeMissingImageBufferFailures() {
        var diagnostics = LiveNaruHelperVideoScreenCaptureKitNoFrameDiagnostics()

        diagnostics.record(
            isScreenOutput: true,
            isDisplayableScreenFrame: NaruHelperVideoScreenCaptureKitFrameSamplePolicy
                .isDisplayableScreenFrame(
                    rawStatus: SCFrameStatus.started.rawValue,
                    hasImageBuffer: false
                ),
            hasImageBuffer: false
        )
        diagnostics.record(
            isScreenOutput: true,
            isDisplayableScreenFrame: NaruHelperVideoScreenCaptureKitFrameSamplePolicy
                .isDisplayableScreenFrame(
                    rawStatus: SCFrameStatus.idle.rawValue,
                    hasImageBuffer: false
                ),
            hasImageBuffer: false
        )

        XCTAssertEqual(diagnostics.timeoutError, .captureNonDisplayableScreenFrames)

        diagnostics.record(
            isScreenOutput: true,
            isDisplayableScreenFrame: true,
            hasImageBuffer: false
        )

        XCTAssertEqual(diagnostics.timeoutError, .capturedFrameMissingImageBuffer)
    }
    #endif
    #endif

    private static let annexBStartCode = Data([0x00, 0x00, 0x00, 0x01])

    #if os(macOS) && canImport(VideoToolbox)
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
    #endif

    #if os(macOS) && canImport(VideoToolbox)
    private static func collectAccessUnits(
        from stream: AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error>,
        limit: Int? = nil
    ) async throws -> [NaruHelperVideoAccessUnit] {
        var accessUnits: [NaruHelperVideoAccessUnit] = []
        for try await accessUnit in stream {
            accessUnits.append(accessUnit)
            if let limit, accessUnits.count >= limit {
                break
            }
        }
        return accessUnits
    }
    #endif

    private static func nalTypes(in annexBPayload: Data) -> [UInt8] {
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
                    types.append(bytes[index + 3] & 0x1F)
                }
                index += 3
                continue
            }

            if index + 3 < bytes.count, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                if index + 4 < bytes.count {
                    types.append(bytes[index + 4] & 0x1F)
                }
                index += 4
                continue
            }

            index += 1
        }
        return types
    }
}

#if os(macOS) && canImport(VideoToolbox) && canImport(ScreenCaptureKit)
private final class StubScreenCaptureKitPixelBufferProvider:
    NaruHelperVideoScreenCaptureKitPixelBufferStreamProvider,
    @unchecked Sendable
{
    struct Request: Equatable {
        var frameLimit: Int
        var frameRateBucket: HelperVideoFrameRateBucket
    }

    struct StreamRequest: Equatable {
        var frameLimit: Int?
        var frameRateBucket: HelperVideoFrameRateBucket
    }

    private let lock = NSLock()
    private let pixelBuffersToReturn: [CVPixelBuffer]
    private var recordedRequests: [Request] = []
    private var recordedStreamRequests: [StreamRequest] = []

    init(pixelBuffers: [CVPixelBuffer]) {
        self.pixelBuffersToReturn = pixelBuffers
    }

    var requests: [Request] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return recordedRequests
    }

    var streamRequests: [StreamRequest] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return recordedStreamRequests
    }

    func pixelBuffers(
        frameLimit: Int,
        frameRateBucket: HelperVideoFrameRateBucket,
        qualityBucket: HelperVideoQualityBucket
    ) throws -> [CVPixelBuffer] {
        lock.lock()
        defer {
            lock.unlock()
        }
        recordedRequests.append(Request(frameLimit: frameLimit, frameRateBucket: frameRateBucket))
        return pixelBuffersToReturn
    }

    func pixelBufferStream(
        frameLimit: Int?,
        frameRateBucket: HelperVideoFrameRateBucket,
        qualityBucket: HelperVideoQualityBucket
    ) throws -> AsyncThrowingStream<CVPixelBuffer, any Error> {
        lock.lock()
        recordedStreamRequests.append(StreamRequest(
            frameLimit: frameLimit,
            frameRateBucket: frameRateBucket
        ))
        let pixelBuffers = pixelBuffersToReturn
        lock.unlock()

        return AsyncThrowingStream { continuation in
            let limitedPixelBuffers = Array(pixelBuffers.prefix(frameLimit ?? pixelBuffers.count))
            for pixelBuffer in limitedPixelBuffers {
                nonisolated(unsafe) let transferablePixelBuffer = pixelBuffer
                continuation.yield(transferablePixelBuffer)
            }
            continuation.finish()
        }
    }
}
#endif

private final class VideoEncoderSessionProbeRecorder: @unchecked Sendable {
    private let result: NaruHelperVideoEncoderSessionState
    private let lock = NSLock()
    private var count = 0

    init(result: NaruHelperVideoEncoderSessionState) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return count
    }

    func record() -> NaruHelperVideoEncoderSessionState {
        lock.lock()
        defer {
            lock.unlock()
        }
        count += 1
        return result
    }
}
