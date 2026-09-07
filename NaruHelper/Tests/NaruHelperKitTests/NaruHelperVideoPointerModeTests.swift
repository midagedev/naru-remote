import Foundation
import XCTest
#if canImport(CoreVideo)
import CoreVideo
#endif
@testable import NaruHelperKit
import NaruRemoteCore

// Spec 042 FR-007 — pointer mode on the helper-video wire, cursor off in
// trackpad mode (Round C).
//
// Contract ↔ assertion table:
//
// | FR-007 clause | Assertions |
// |---|---|
// | The start request carries the phone's pointer mode to the stream side | testStartStreamRequestHandsPointerModeToStartStreamProvider (trackpad recorded; nil recorded) |
// | `trackpad` ⇒ `showsCursor == false` | testTrackpadPointerModeDisablesCursorCapture (continuous + finite policy shapes; equality vs cursor-hidden legacy policy) |
// | `.directTouch` and `nil`/legacy ⇒ `showsCursor == true` (today's behaviour) | testDirectTouchAndLegacyRequestsKeepCursorCapture (directTouch; explicit nil; make() default; nil == omitted) |
// | Both capture sites apply the policy value (no literal `showsCursor = true` remains) | The two policy-shape tests pin the value the sites read (`configuration.showsCursor = policy.showsCursor`); the executable site check is the repo grep `grep -n 'showsCursor = true' …AccessUnitSource.swift` → exit 1 (lead gate); live behaviour is exercised end-to-end by the external-helper test below |
// | A mode switch mid-session re-issues the configuration where the API allows | testUpdatePointerModeOnDetachedStreamStoresModeWithoutThrowing (mode storage + no-throw when detached); testLiveRunningStreamUpdatePointerModeAppliesTrackpadToggle + testLiveSCStreamUpdateConfigurationAppliesShowsCursorToggle (the R1 measurement, on hosts whose swift-test SCK content is not TCC-redacted — see skipIfScreenContentIsRedacted); the granted-process fallback (a new start request carrying the mode) is measured live by testExternalHelperProcessStreamsRealScreenFramesForBothPointerModes |
// | The encoder does not force a keyframe across a mode toggle (R1 keyframe half) | testEncoderEmitsNoMidSequenceKeyframeAcrossToggleWindow |
//
// Input defense for the new `pointerMode` request field — three classes, one
// assertion each. The auth proof covers only
// requestID/messageType/profileFingerprint (HelperVideoAuthProof.canonicalMessage),
// so a hostile or corrupted body still reaches the decoder: these tests prove
// the handshake never breaks over this field.
//
// | Class | Input | Expected |
// |---|---|---|
// | malicious | 10 KB unknown string value | accepted; provider sees `nil` |
// | corrupted | wrong JSON type (number / bool) | accepted; provider sees `nil` |
// | stale-schema | key absent (pre-042 phone) | accepted; provider sees `nil` |

final class NaruHelperVideoPointerModeTests: XCTestCase {
    private let pairingSecret = "pointer-mode-test-secret"
    private let profileFingerprint = "sha256:pointer-mode-test-profile"

    // MARK: - Configuration policy (T-C2)

    #if os(macOS) && canImport(VideoToolbox) && canImport(ScreenCaptureKit)
    func testTrackpadPointerModeDisablesCursorCapture() {
        let continuous = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy
            .make(
                displayWidth: 1_512,
                displayHeight: 982,
                frameLimit: nil,
                qualityBucket: .readability,
                pointerMode: .trackpad
            )
        let finite = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy
            .make(
                displayWidth: 1_512,
                displayHeight: 982,
                frameLimit: 30,
                qualityBucket: .readability,
                pointerMode: .trackpad
            )
        var cursorHiddenLegacy = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy
            .make(
                displayWidth: 1_512,
                displayHeight: 982,
                frameLimit: nil,
                qualityBucket: .readability,
                pointerMode: nil
            )
        cursorHiddenLegacy.showsCursor = false

        XCTAssertEqual(continuous.showsCursor, false)
        XCTAssertEqual(finite.showsCursor, false)
        // The mode changes only cursor visibility — the rest of the policy
        // (scaling, queue depth) must not move with it. 982 × 960/1512 =
        // 623.49 → 623 → even-1 = 622 (same rounding as the 721→720 precedent
        // in NaruHelperVideoEncoderPrototypeTests).
        XCTAssertEqual(continuous.outputWidth, 960)
        XCTAssertEqual(continuous.outputHeight, 622)
        XCTAssertEqual(continuous.queueDepth, 3)
        XCTAssertEqual(finite.queueDepth, 5)
        XCTAssertEqual(continuous, cursorHiddenLegacy)
    }

    func testDirectTouchAndLegacyRequestsKeepCursorCapture() {
        let directTouch = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy
            .make(
                displayWidth: 1_512,
                displayHeight: 982,
                frameLimit: nil,
                qualityBucket: .readability,
                pointerMode: .directTouch
            )
        let legacyNil = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy
            .make(
                displayWidth: 1_512,
                displayHeight: 982,
                frameLimit: nil,
                qualityBucket: .readability,
                pointerMode: nil
            )
        let legacyOmitted = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy
            .make(
                displayWidth: 1_512,
                displayHeight: 982,
                frameLimit: nil,
                qualityBucket: .readability
            )

        XCTAssertEqual(directTouch.showsCursor, true)
        XCTAssertEqual(legacyNil.showsCursor, true)
        XCTAssertEqual(legacyOmitted.showsCursor, true)
        XCTAssertEqual(directTouch.outputWidth, legacyNil.outputWidth)
        XCTAssertEqual(directTouch.queueDepth, legacyNil.queueDepth)
        // Legacy requests (nil / omitted) are value-for-value today's policy.
        XCTAssertEqual(legacyNil, legacyOmitted)
    }
    #endif

    // MARK: - Request threading (T-C1, handler → provider)

    func testStartStreamRequestHandsPointerModeToStartStreamProvider() throws {
        let recorder = StartStreamProviderRecorder()
        let handler = makeHandler(startStreamProvider: recorder.provider())

        let response = try handler.handleStartStreamFrame(
            try HelperVideoWireCodec.frame(signedStartEnvelope(
                body: HelperVideoStartStreamRequestBody(pointerMode: .trackpad)
            ))
        )
        let responseEnvelope = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
            from: response
        ).envelope

        XCTAssertEqual(responseEnvelope.body.result, .accepted)
        XCTAssertEqual(responseEnvelope.body.streamDescriptor.codec, .h264)
        XCTAssertEqual(recorder.requests.map(\.pointerMode), [.trackpad])

        // The legacy default still reaches the provider (nil ⇒ cursor shown).
        _ = try handler.handleStartStreamFrame(
            try HelperVideoWireCodec.frame(signedStartEnvelope(
                body: HelperVideoStartStreamRequestBody()
            ))
        )
        XCTAssertEqual(recorder.requests.map(\.pointerMode), [.trackpad, nil])
    }

    // MARK: - Input defense (3 classes)

    func testMaliciousTenKilobytePointerModeStringValueStillHandshakes() throws {
        try assertHostilePointerMode(
            .string(String(repeating: "a", count: 10_240)),
            file: #filePath,
            line: #line
        )
    }

    func testCorruptedWrongTypePointerModeJSONValueStillHandshakes() throws {
        try assertHostilePointerMode(
            .number(3),
            file: #filePath,
            line: #line
        )
        try assertHostilePointerMode(
            .boolean(true),
            file: #filePath,
            line: #line
        )
    }

    func testStaleSchemaPointerModeKeyAbsentStillHandshakes() throws {
        try assertHostilePointerMode(
            nil,
            file: #filePath,
            line: #line
        )
    }

    // MARK: - R1, keyframe half (no live SCK needed)

    #if os(macOS) && canImport(CoreVideo) && canImport(VideoToolbox)
    /// R1 keyframe half: with a keyFrameInterval far beyond the toggle
    /// window, frames spanning a mode toggle encode as deltas only — the
    /// encoder does not force a keyframe of its own at content discontinuities
    /// (the wire's requestKeyframe exists for when the decoder needs one).
    func testEncoderEmitsNoMidSequenceKeyframeAcrossToggleWindow() throws {
        let colors: [(UInt8, UInt8, UInt8)] = [
            (0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255)
        ]
        let pixelBuffers = try colors.map { rgb in
            try Self.solidColorPixelBuffer(width: 128, height: 96, rgb: rgb)
        }
        let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
            width: 128,
            height: 96,
            frameRateBucket: .upTo15,
            qualityBucket: .readability,
            keyFrameInterval: 10_000,
            encodingMode: .lowLatencyRealtime,
            codec: .h264
        )
        let units = try encoder.encode(pixelBuffers: pixelBuffers)

        let kinds = units.map(\.kind)
        XCTAssertEqual(kinds.first, .parameterSet)
        XCTAssertEqual(kinds.count, pixelBuffers.count + 1)
        XCTAssertEqual(kinds.dropFirst().first, .keyframe)
        XCTAssertTrue(
            kinds.dropFirst(2).allSatisfy { $0 == .delta },
            "no mid-sequence keyframe expected across the toggle window: \(kinds)"
        )
        XCTAssertFalse(
            kinds.dropFirst(2).contains(.keyframe),
            "encoder forced a keyframe mid-sequence across the toggle window: \(kinds)"
        )
    }

    private static func solidColorPixelBuffer(
        width: Int,
        height: Int,
        rgb: (UInt8, UInt8, UInt8)
    ) throws -> CVPixelBuffer {
        var optionalPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &optionalPixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = optionalPixelBuffer else {
            throw NSError(
                domain: "NaruHelperVideoPointerModeTests",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate failed: \(status)"]
            )
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(
                domain: "NaruHelperVideoPointerModeTests",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "pixel buffer base address unavailable"]
            )
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = UnsafeMutableRawPointer(baseAddress).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let row = bytes + y * bytesPerRow
            for x in 0..<width {
                let offset = x * 4 // BGRA
                row[offset] = rgb.2
                row[offset + 1] = rgb.1
                row[offset + 2] = rgb.0
                row[offset + 3] = 255
            }
        }
        return pixelBuffer
    }
    #endif

    // MARK: - R1, granted-process end-to-end (external helper binary)

    #if canImport(Network)
    /// R1 on a granted process: the benchmark-granted `.build/debug/NaruHelper`
    /// binary answers real ScreenCaptureKit frames. A trackpad-mode request and
    /// a legacy request must both handshake and both stream an encoded screen
    /// sequence — this is the mechanism a mode switch actually relies on (the
    /// next start request carries the mode), and it exercises the policy's
    /// `showsCursor` value inside a real `SCStreamConfiguration`.
    /// Gated like the repo's other external helper process tests.
    func testExternalHelperProcessStreamsRealScreenFramesForBothPointerModes() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NARU_RUN_EXTERNAL_HELPER_PROCESS_TESTS"] == "1",
            "Set NARU_RUN_EXTERNAL_HELPER_PROCESS_TESTS=1 to run external helper process tests."
        )
        let helperPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/NaruHelper")
            .path
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: helperPath),
            "NaruHelper executable is not available at \(helperPath)"
        )

        let port = UInt16.random(in: 49_152...65_000)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = [
            "--video-listen",
            "--token-env", "NARU_HELPER_VIDEO_POINTER_MODE_TEST_TOKEN",
            "--profile-fingerprint-env", "NARU_HELPER_VIDEO_POINTER_MODE_TEST_FINGERPRINT",
            "--port", "\(port)",
            "--video-source", "screen-capturekit",
            "--video-frame-count", "6"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["NARU_HELPER_VIDEO_POINTER_MODE_TEST_TOKEN"] = pairingSecret
        environment["NARU_HELPER_VIDEO_POINTER_MODE_TEST_FINGERPRINT"] = profileFingerprint
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(process.isRunning, "helper exited before serving a request")

        let cases: [(label: String, body: HelperVideoStartStreamRequestBody)] = [
            ("trackpad", HelperVideoStartStreamRequestBody(pointerMode: .trackpad)),
            ("legacy", HelperVideoStartStreamRequestBody())
        ]
        for testCase in cases {
            let client = HelperVideoStreamNetworkClient(
                host: "127.0.0.1",
                port: port,
                profileFingerprint: profileFingerprint,
                pairingSecret: pairingSecret,
                transportProtection: .authenticatedPrivateProfile,
                timeout: 12
            )
            // A freshly spawned helper can need a beat before its listener
            // answers (measured 2026-09-07: first attempt times out, the
            // immediate retry succeeds) — retry instead of failing the case.
            var result: HelperVideoStreamNetworkStartResult?
            var lastError: (any Error)?
            for _ in 0..<3 {
                do {
                    result = try await client.startStream(testCase.body)
                    break
                } catch {
                    lastError = error
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
            guard let result = result else {
                throw lastError ?? NSError(
                    domain: "NaruHelperVideoPointerModeTests",
                    code: 12,
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(testCase.label) start request never succeeded"
                    ]
                )
            }

            XCTAssertEqual(
                result.startResponse.body.result,
                .accepted,
                "\(testCase.label) start request must be accepted"
            )
            XCTAssertNil(result.stall, "\(testCase.label) stream must not stall")
            let kinds = result.accessUnits.map { $0.envelope.body.kind }
            XCTAssertEqual(kinds.first, .parameterSet, testCase.label)
            XCTAssertTrue(
                kinds.dropFirst().contains(.keyframe),
                "\(testCase.label) needs at least one keyframe after the parameter set"
            )
            XCTAssertGreaterThanOrEqual(
                kinds.dropFirst().filter { $0 == .delta }.count,
                2,
                "\(testCase.label) needs sustained delta frames"
            )
            print(
                "R1 external-helper: mode=\(testCase.label) units=\(kinds.map(\.rawValue))"
            )
        }
    }
    #endif

    // MARK: - Live probes (R1, T-C3) — opt-in via NARU_LIVE_SCK_PROBE=1

    #if DEBUG && os(macOS) && canImport(CoreGraphics) && canImport(CoreMedia) && canImport(CoreVideo) && canImport(ScreenCaptureKit)
    /// The mode switch's storage contract when no stream is attached (never
    /// started, or already stopped): the call stores the mode and returns —
    /// no throw, no stream to reconfigure — and the stored mode is what the
    /// next start request uses. Not env-gated: no live capture is involved.
    func testUpdatePointerModeOnDetachedStreamStoresModeWithoutThrowing() async throws {
        let runningStream = NaruHelperVideoScreenCaptureKitRunningStream(
            configuration: SCStreamConfiguration()
        )

        try await runningStream.updatePointerMode(.trackpad)
        XCTAssertEqual(runningStream.pointerMode, .trackpad)

        try await runningStream.updatePointerMode(nil)
        XCTAssertNil(runningStream.pointerMode)
    }

    func testLiveSCStreamUpdateConfigurationAppliesShowsCursorToggle() async throws {
        try skipUnlessLiveProbeEnabled()
        try await skipIfScreenContentIsRedacted()

        let measurement = try await measureCursorCompositing { stream, configuration in
            configuration.showsCursor = false
            try await stream.updateConfiguration(configuration)
        }

        // Baseline sanity: the arrow was composited before the toggle.
        XCTAssertGreaterThan(
            measurement.preToggleMoveDiff,
            max(measurement.stationaryNoiseFloor * 3, 2.0),
            "cursor did not register as composited before the toggle — measurement invalid"
        )
        // The R1 answer: updateConfiguration applied showsCursor live.
        XCTAssertLessThan(
            measurement.postToggleMoveDiff1,
            measurement.preToggleMoveDiff * 0.3,
            "cursor still composited after updateConfiguration — not applied live"
        )
        XCTAssertLessThan(
            measurement.postToggleMoveDiff2,
            measurement.preToggleMoveDiff * 0.3,
            "cursor still composited after updateConfiguration — not applied live"
        )
        // The stream kept delivering frames; no restart happened.
        XCTAssertGreaterThanOrEqual(measurement.framesAfterToggle, 3)
    }

    func testLiveRunningStreamUpdatePointerModeAppliesTrackpadToggle() async throws {
        try skipUnlessLiveProbeEnabled()
        try await skipIfScreenContentIsRedacted()

        var observedPointerMode: HelperVideoPointerMode?
        let measurement = try await measureCursorCompositing { stream, configuration in
            let runningStream = NaruHelperVideoScreenCaptureKitRunningStream(
                configuration: configuration
            )
            runningStream.attach(stream)
            try await runningStream.updatePointerMode(.trackpad)
            observedPointerMode = runningStream.pointerMode
        }

        XCTAssertEqual(observedPointerMode, .trackpad)
        XCTAssertGreaterThan(
            measurement.preToggleMoveDiff,
            max(measurement.stationaryNoiseFloor * 3, 2.0),
            "cursor did not register as composited before the toggle — measurement invalid"
        )
        XCTAssertLessThan(
            measurement.postToggleMoveDiff1,
            measurement.preToggleMoveDiff * 0.3
        )
        XCTAssertLessThan(
            measurement.postToggleMoveDiff2,
            measurement.preToggleMoveDiff * 0.3
        )
        XCTAssertGreaterThanOrEqual(measurement.framesAfterToggle, 3)
    }
    #endif
}

// MARK: - Handler helpers

private extension NaruHelperVideoPointerModeTests {
    func makeHandler(
        startStreamProvider: @escaping NaruHelperVideoTransportRequestHandler
            .StartStreamProvider
    ) -> NaruHelperVideoTransportRequestHandler {
        NaruHelperVideoTransportRequestHandler(
            expectedPairingSecret: pairingSecret,
            expectedProfileFingerprint: profileFingerprint,
            capabilityProvider: {
                HelperVideoCapabilityResponseBody(
                    availability: .available,
                    screenRecordingPermission: .granted,
                    codecSupport: .h264,
                    latencyModes: [.lowLatency]
                )
            },
            startStreamProvider: startStreamProvider
        )
    }

    func signedStartEnvelope(
        body: HelperVideoStartStreamRequestBody
    ) -> HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody> {
        NaruHelperVideoTransportRequestHandler.signedEnvelope(
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            body: body
        )
    }

    func assertHostilePointerMode(
        _ rawValue: ProbeRawJSONValue?,
        file: StaticString,
        line: UInt
    ) throws {
        let recorder = StartStreamProviderRecorder()
        let handler = makeHandler(startStreamProvider: recorder.provider())
        let rawBody = ProbeRawPointerModeStartBody(pointerMode: rawValue)
        let requestID = UUID()
        let envelope = HelperVideoWireEnvelope(
            requestID: requestID,
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            authProof: HelperVideoAuthProof.make(
                requestID: requestID,
                messageType: .startStream,
                profileFingerprint: profileFingerprint,
                pairingSecret: pairingSecret
            ),
            body: rawBody
        )

        let response = try handler.handleStartStreamFrame(
            try HelperVideoWireCodec.frame(envelope)
        )
        let responseEnvelope = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
            from: response
        ).envelope

        XCTAssertEqual(responseEnvelope.body.result, .accepted, file: file, line: line)
        XCTAssertEqual(responseEnvelope.body.streamDescriptor.codec, .h264, file: file, line: line)
        XCTAssertEqual(
            recorder.requests.map(\.pointerMode),
            [nil],
            "hostile pointerMode must degrade to nil, never fail the handshake",
            file: file,
            line: line
        )
    }
}

// MARK: - Hostile JSON fixtures

/// A bare JSON primitive, so tests can place values the real decoder does not
/// expect (10 KB strings, numbers, booleans) into the `pointerMode` slot.
private enum ProbeRawJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .boolean(try container.decode(Bool.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        }
    }
}

/// Encode-only mirror of `HelperVideoStartStreamRequestBody` that allows a
/// raw `pointerMode` JSON value (or its absence) instead of the typed enum.
private struct ProbeRawPointerModeStartBody: Codable, Equatable, Sendable {
    var codec: String = "h264"
    var latencyMode: String = "lowLatency"
    var qualityBucket: String = "readability"
    var maxFrameRateBucket: String = "upTo30"
    var pointerMode: ProbeRawJSONValue?
}

private final class StartStreamProviderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [HelperVideoStartStreamRequestBody] = []

    func provider() -> NaruHelperVideoTransportRequestHandler.StartStreamProvider {
        { request in
            self.lock.lock()
            self.recordedRequests.append(request)
            self.lock.unlock()
            return NaruHelperVideoTransportRequestHandler
                .defaultStartStreamResponse(request: request)
        }
    }

    var requests: [HelperVideoStartStreamRequestBody] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return recordedRequests
    }
}

// MARK: - Live probe harness (R1 measurement)

#if DEBUG && os(macOS) && canImport(CoreGraphics) && canImport(CoreMedia) && canImport(CoreVideo) && canImport(ScreenCaptureKit)
import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
@preconcurrency import ScreenCaptureKit

private struct ProbeCapturedPixelBuffer: @unchecked Sendable {
    var pixelBuffer: CVPixelBuffer
}

private final class ProbeFrameStore: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Frame {
        let timestamp: Date
        let pixelBuffer: ProbeCapturedPixelBuffer
    }

    private let lock = NSLock()
    private var frames: [Frame] = []
    private var totalFrameCount = 0
    private var stopped = false
    private var statusCounts: [String: Int] = [:]
    private var nonScreenCallbacks = 0

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            lock.lock()
            nonScreenCallbacks += 1
            lock.unlock()
            return
        }
        // The probe accepts every screen frame that carries pixels — `.idle`
        // frames (static content) still hold the composited screen, and the
        // probe needs continuous delivery even when nothing but the cursor
        // moves. Statuses are counted for diagnostics instead of filtered.
        let status = NaruHelperVideoScreenCaptureKitFrameSamplePolicy.rawStatus(
            from: sampleBuffer
        ).map { SCFrameStatus(rawValue: $0)?.rawValue ?? $0 } ?? -1
        lock.lock()
        defer {
            lock.unlock()
        }
        statusCounts["s\(status)", default: 0] += 1
        guard !stopped else {
            return
        }
        totalFrameCount += 1
        frames.append(
            Frame(timestamp: Date(), pixelBuffer: ProbeCapturedPixelBuffer(pixelBuffer: imageBuffer))
        )
        if frames.count > 60 {
            frames.removeFirst(frames.count - 60)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    var totalCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return totalFrameCount
    }

    /// Diagnostic summary for timeout errors: what the stream actually
    /// delivered (SCFrameStatus raw values: 0 idle, 1 complete, 2 blank,
    /// 3 suspended, 4 started), so a missing-frame failure names its cause.
    var deliverySummary: String {
        lock.lock()
        defer {
            lock.unlock()
        }
        let statuses = statusCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)x\($0.value)" }
            .joined(separator: " ")
        return "delivered=\(totalFrameCount) stopped=\(stopped) nonScreen=\(nonScreenCallbacks) statuses[\(statuses)]"
    }

    func latestFrame(onOrAfter date: Date) -> Frame? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return frames.last { $0.timestamp >= date }
    }

    func waitForFrame(onOrAfter date: Date, timeout: TimeInterval) throws -> Frame {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let frame = latestFrame(onOrAfter: date) {
                return frame
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw NSError(
            domain: "NaruHelperVideoPointerModeTests",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "no probe frame arrived onOrAfter \(date) — \(deliverySummary)"
            ]
        )
    }
}

private struct CursorToggleMeasurement {
    /// Mean |ΔRGB| between two frames with the cursor parked — the noise floor.
    var stationaryNoiseFloor: Double
    /// Same metric across a cursor warp while `showsCursor = true` (arrow moves).
    var preToggleMoveDiff: Double
    /// Across the first warp after the toggle (arrow must be gone if applied).
    var postToggleMoveDiff1: Double
    /// Across the second warp after the toggle (stability of the answer).
    var postToggleMoveDiff2: Double
    var framesBeforeToggle: Int
    var framesAfterToggle: Int
    var encoderKindSequence: [String]
    var deliverySummary: String
    var lastWarpTarget: CGPoint?
    var finalMouseLocation: CGPoint
}

/// Drives real on-screen content changes. SCK on a static screen delivers a
/// few `.idle` frames and then goes silent (measured 2026-09-07: delivered=3,
/// all idle, zero `.complete` despite cursor warps), so the probe parks a
/// small borderless window flipping black/white at the display's bottom-left
/// corner — away from both cursor sample points (upper third).
@MainActor
private final class ProbeContentDriver: @unchecked Sendable {
    private let window: NSWindow
    private let view: ProbeFlipView
    private var flipTask: Task<Void, Never>?

    init() {
        view = ProbeFlipView(frame: NSRect(x: 0, y: 0, width: 120, height: 120))
        window = NSWindow(
            contentRect: view.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.level = .floating
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
    }

    func startFlipping() {
        flipTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.flip()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func flip() {
        view.white.toggle()
        view.needsDisplay = true
    }

    func stop() {
        flipTask?.cancel()
        flipTask = nil
        window.orderOut(nil)
        window.close()
    }
}

private final class ProbeFlipView: NSView {
    var white = false

    override func draw(_ dirtyRect: NSRect) {
        (white ? NSColor.white : NSColor.black).setFill()
        bounds.fill()
    }
}

private extension NaruHelperVideoPointerModeTests {
    func skipUnlessLiveProbeEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NARU_LIVE_SCK_PROBE"] == "1",
            "Set NARU_LIVE_SCK_PROBE=1 to run the live ScreenCaptureKit probe."
        )
        try XCTSkipUnless(
            CGPreflightScreenCaptureAccess(),
            "The swift test host has no Screen Recording permission — the probe cannot measure. (CGPreflightScreenCaptureAccess() == false)"
        )
    }

    /// The one lie `CGPreflightScreenCaptureAccess()` tells: it can return
    /// `true` while macOS redacts the content for this host — streams then
    /// deliver idle-status placeholder frames and screenshots are a static
    /// image that ignores `showsCursor` (measured 2026-09-07; research §R1
    /// records the exact API results). Ground truth: park the cursor and
    /// take two screenshots at the same position with `showsCursor` true
    /// then false. On a granted host the flag visibly adds/removes the
    /// arrow; on a redacted host the two shots are byte-identical. If the
    /// flag has no effect, cursor compositing cannot be measured here, so
    /// the probe skips instead of reporting a bogus "never composited"
    /// failure. The cursor is always restored.
    func skipIfScreenContentIsRedacted() async throws {
        let originalMouseLocation = NSEvent.mouseLocation
        let displayID = CGMainDisplayID()
        let displayBounds = CGDisplayBounds(displayID)
        let mainScreenHeight = displayBounds.height
        defer {
            CGWarpMouseCursorPosition(
                CGPoint(
                    x: originalMouseLocation.x,
                    y: mainScreenHeight - originalMouseLocation.y
                )
            )
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == displayID })
            ?? content.displays.first
        else {
            // No display to check against — the probe's own path reports it.
            return
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let parkedPoint = CGPoint(
            x: displayBounds.width * 0.3,
            y: displayBounds.height * 0.3
        )
        CGWarpMouseCursorPosition(parkedPoint)
        try await Task.sleep(nanoseconds: 150_000_000)

        let cursorConfiguration = SCStreamConfiguration()
        cursorConfiguration.showsCursor = true
        let withCursor = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: cursorConfiguration
        )
        cursorConfiguration.showsCursor = false
        let withoutCursor = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: cursorConfiguration
        )

        let toggleDiff = try Self.cursorRegionDiff(
            withCursor,
            withoutCursor,
            at: parkedPoint,
            displayBounds: displayBounds
        )
        try XCTSkipIf(
            toggleDiff < 0.25,
            "ScreenCaptureKit content is TCC-redacted on this host: CGPreflightScreenCaptureAccess() is true but the showsCursor flag has no effect on captured pixels (toggleDiff \(toggleDiff)) — cursor compositing cannot be measured from the swift-test host. See research §R1."
        )
    }

    /// Mean |ΔRGB| over the parked cursor's region of two screenshots,
    /// mapped from display points into whatever pixel size the screenshot
    /// came back as (the redacted placeholder is a fixed 1920×1080 while the
    /// display is 1512×982 points, so the scale is real, not theoretical).
    /// Both shots go through the same raster path, so any orientation flip
    /// is identical between them and cancels out.
    private static func cursorRegionDiff(
        _ lhs: CGImage,
        _ rhs: CGImage,
        at point: CGPoint,
        displayBounds: CGRect
    ) throws -> Double {
        let left = try bitmapPixels(of: lhs)
        let right = try bitmapPixels(of: rhs)
        guard left.width == right.width,
              left.height == right.height,
              left.width > 0,
              left.height > 0,
              displayBounds.width > 0,
              displayBounds.height > 0
        else {
            throw NSError(
                domain: "NaruHelperVideoPointerModeTests",
                code: 9,
                userInfo: [
                    NSLocalizedDescriptionKey: "redaction-check screenshots have unusable sizes"
                ]
            )
        }

        let scaleX = Double(left.width) / displayBounds.width
        let scaleY = Double(left.height) / displayBounds.height
        // Bounds are clamped before the Range is built — a lower bound above
        // the upper bound traps at construction, it does not return empty.
        let xLower = max(Int((point.x - 2) * scaleX), 0)
        let xUpper = min(Int((point.x + 62) * scaleX), left.width)
        let yLower = max(Int((point.y - 2) * scaleY), 0)
        let yUpper = min(Int((point.y + 62) * scaleY), left.height)
        guard xLower < xUpper, yLower < yUpper else {
            throw NSError(
                domain: "NaruHelperVideoPointerModeTests",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "redaction-check cursor region is empty"]
            )
        }

        var total = 0
        var count = 0
        for y in yLower..<yUpper {
            let leftRow = y * left.bytesPerRow
            let rightRow = y * right.bytesPerRow
            for x in xLower..<xUpper {
                let leftOffset = leftRow + x * 4 // BGRA
                let rightOffset = rightRow + x * 4
                total += abs(Int(left.bytes[leftOffset]) - Int(right.bytes[rightOffset]))
                total += abs(
                    Int(left.bytes[leftOffset + 1]) - Int(right.bytes[rightOffset + 1])
                )
                total += abs(
                    Int(left.bytes[leftOffset + 2]) - Int(right.bytes[rightOffset + 2])
                )
                count += 3
            }
        }
        return count == 0 ? 0 : Double(total) / Double(count)
    }

    private struct ProbeBitmapPixels {
        var bytes: [UInt8]
        var width: Int
        var height: Int
        var bytesPerRow: Int
    }

    private static func bitmapPixels(of image: CGImage) throws -> ProbeBitmapPixels {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGImageByteOrderInfo.order32Little.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else {
            throw NSError(
                domain: "NaruHelperVideoPointerModeTests",
                code: 11,
                userInfo: [
                    NSLocalizedDescriptionKey: "could not rasterize the redaction-check screenshot"
                ]
            )
        }
        return ProbeBitmapPixels(
            bytes: bytes,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow
        )
    }

    /// Native-size capture configuration with the cursor baked in — the state
    /// every stream starts in today.
    private func nativeConfiguration(
        for display: SCDisplay
    ) -> (configuration: SCStreamConfiguration, policy: NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy) {
        let policy = NaruHelperVideoScreenCaptureKitCaptureConfigurationPolicy.make(
            displayWidth: display.width,
            displayHeight: display.height,
            frameLimit: nil,
            qualityBucket: .fidelity
        )
        let configuration = SCStreamConfiguration()
        configuration.width = policy.outputWidth
        configuration.height = policy.outputHeight
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = policy.queueDepth
        configuration.minimumFrameInterval = HelperVideoFrameRateBucket.upTo15
            .screenCaptureMinimumFrameInterval
        configuration.capturesAudio = false
        configuration.showsCursor = true
        return (configuration, policy)
    }

    /// One R1 pass: capture at native size, park/warp the cursor, toggle
    /// `showsCursor` via `applyToggle`, and diff the cursor regions. The
    /// system cursor is restored and the stream is always stopped.
    func measureCursorCompositing(
        applyToggle: (SCStream, SCStreamConfiguration) async throws -> Void
    ) async throws -> CursorToggleMeasurement {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID })
            ?? content.displays.first
        else {
            throw NSError(
                domain: "NaruHelperVideoPointerModeTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "no SCDisplay available for the probe"]
            )
        }
        let displayBounds = CGDisplayBounds(mainDisplayID)

        let (configuration, policy) = nativeConfiguration(for: display)
        let store = ProbeFrameStore()
        let stream = SCStream(
            filter: SCContentFilter(display: display, excludingWindows: []),
            configuration: configuration,
            delegate: store
        )
        try stream.addStreamOutput(
            store,
            type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "com.naruremote.pointer-mode-probe")
        )

        // Save the cursor now (AppKit base coords) to restore after the probe;
        // CG global coords flip y per the main display, so restore flips back.
        let originalMouseLocation = NSEvent.mouseLocation
        let mainScreenHeight = CGDisplayBounds(CGMainDisplayID()).height

        // Content driver: without window-server changes SCK delivers only
        // `.idle` frames on this OS, and the probe needs `.complete` frames
        // that composite the current cursor position.
        let contentDriver = await MainActor.run { () -> ProbeContentDriver in
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            let driver = ProbeContentDriver()
            driver.startFlipping()
            return driver
        }
        var lastWarpTarget: CGPoint?

        // One screen point == one captured pixel (native capture), so the
        // cursor-region diff needs no coordinate scaling.
        let scale = Double(policy.outputWidth) / Double(display.width)
        func cursorRect(_ point: CGPoint) -> CGRect {
            let side = 64.0
            let origin = CGPoint(x: (point.x - 2) * scale, y: (point.y - 2) * scale)
            return CGRect(
                x: max(origin.x, 0),
                y: max(origin.y, 0),
                width: min(side * scale, Double(policy.outputWidth) - origin.x),
                height: min(side * scale, Double(policy.outputHeight) - origin.y)
            )
        }
        let pointA = CGPoint(x: displayBounds.width * 0.3, y: displayBounds.height * 0.3)
        let pointB = CGPoint(x: displayBounds.width * 0.7, y: displayBounds.height * 0.3)
        func cursorUnionDiff(_ lhs: ProbeFrameStore.Frame, _ rhs: ProbeFrameStore.Frame) throws -> Double {
            let diffA = try meanAbsoluteRGBDifference(lhs.pixelBuffer, rhs.pixelBuffer, rect: cursorRect(pointA))
            let diffB = try meanAbsoluteRGBDifference(lhs.pixelBuffer, rhs.pixelBuffer, rect: cursorRect(pointB))
            return (diffA + diffB) / 2
        }

        // Measurement runs first; cleanup below ALWAYS restores the cursor and
        // stops the stream (defer cannot await, so the body is a do/catch).
        var measurement: CursorToggleMeasurement?
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                stream.startCapture { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            // Let the first flips reach the compositor before sampling.
            try await Task.sleep(nanoseconds: 400_000_000)

            // 1. Park at A; two frames with no movement → the noise floor.
            CGWarpMouseCursorPosition(pointA)
            lastWarpTarget = pointA
            let settleA = Date().addingTimeInterval(0.55)
            let parked1 = try store.waitForFrame(onOrAfter: settleA, timeout: 4.0)
            try await Task.sleep(nanoseconds: 300_000_000)
            let parked2 = try store.waitForFrame(onOrAfter: parked1.timestamp.addingTimeInterval(0.05), timeout: 4.0)
            let noiseFloor = try cursorUnionDiff(parked1, parked2)

            // 2. Warp A → B with showsCursor = true → the arrow must register.
            CGWarpMouseCursorPosition(pointB)
            lastWarpTarget = pointB
            let settleB = Date().addingTimeInterval(0.55)
            let movedPreToggle = try store.waitForFrame(onOrAfter: settleB, timeout: 4.0)
            let preToggleDiff = try cursorUnionDiff(parked2, movedPreToggle)

            // 3. The toggle under measurement.
            let framesBefore = store.totalCount
            try await applyToggle(stream, configuration)

            // 4. Two more warps → the arrow must be gone if it applied live.
            let settleToggle = Date().addingTimeInterval(0.55)
            let afterToggle = try store.waitForFrame(onOrAfter: settleToggle, timeout: 4.0)
            CGWarpMouseCursorPosition(pointA)
            lastWarpTarget = pointA
            let settleC = Date().addingTimeInterval(0.55)
            let movedPost1 = try store.waitForFrame(onOrAfter: settleC, timeout: 4.0)
            let postToggleDiff1 = try cursorUnionDiff(afterToggle, movedPost1)
            CGWarpMouseCursorPosition(pointB)
            lastWarpTarget = pointB
            let settleD = Date().addingTimeInterval(0.55)
            let movedPost2 = try store.waitForFrame(onOrAfter: settleD, timeout: 4.0)
            let postToggleDiff2 = try cursorUnionDiff(movedPost1, movedPost2)
            let framesAfter = store.totalCount - framesBefore

            // 5. Keyframe half of R1: encode frames spanning the toggle with a
            // keyFrameInterval far beyond the window — if the encoder needed a
            // forced keyframe at the boundary, a keyframe would appear mid-sequence.
            var kindSequence: [String] = []
            #if canImport(VideoToolbox)
            let encoder = NaruHelperVideoToolboxPixelBufferAccessUnitEncoder(
                width: Int32(policy.outputWidth),
                height: Int32(policy.outputHeight),
                frameRateBucket: .upTo15,
                qualityBucket: .readability,
                keyFrameInterval: 10_000,
                encodingMode: .lowLatencyRealtime,
                codec: .h264
            )
            let sequence = [
                movedPreToggle.pixelBuffer,
                afterToggle.pixelBuffer,
                movedPost1.pixelBuffer,
                movedPost2.pixelBuffer,
            ]
            if let units = try? encoder.encode(pixelBuffers: sequence.map(\.pixelBuffer)) {
                kindSequence = units.map { $0.kind.rawValue }
            }
            #endif

            measurement = CursorToggleMeasurement(
                stationaryNoiseFloor: noiseFloor,
                preToggleMoveDiff: preToggleDiff,
                postToggleMoveDiff1: postToggleDiff1,
                postToggleMoveDiff2: postToggleDiff2,
                framesBeforeToggle: framesBefore,
                framesAfterToggle: framesAfter,
                encoderKindSequence: kindSequence,
                deliverySummary: store.deliverySummary,
                lastWarpTarget: lastWarpTarget,
                finalMouseLocation: .zero
            )
        }

        // Cleanup: cursor back where it was, driver window gone, stream
        // stopped — the probe never leaves a capture running.
        CGWarpMouseCursorPosition(
            CGPoint(x: originalMouseLocation.x, y: mainScreenHeight - originalMouseLocation.y)
        )
        await MainActor.run {
            contentDriver.stop()
        }
        let finalMouseLocation = NSEvent.mouseLocation
        if measurement != nil {
            measurement?.finalMouseLocation = finalMouseLocation
        }
        try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        guard let measurement else {
            // Unreachable: the do block either threw (skipping this via catch)
            // or assigned. Defensive only.
            throw NSError(
                domain: "NaruHelperVideoPointerModeTests",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "probe produced no measurement"]
            )
        }
        print(
            "R1 probe: noiseFloor=\(measurement.stationaryNoiseFloor) "
                + "preToggle=\(measurement.preToggleMoveDiff) "
                + "postToggle1=\(measurement.postToggleMoveDiff1) "
                + "postToggle2=\(measurement.postToggleMoveDiff2) "
                + "framesBefore=\(measurement.framesBeforeToggle) "
                + "framesAfter=\(measurement.framesAfterToggle) "
                + "encoderKinds=\(measurement.encoderKindSequence) "
                + "[\(measurement.deliverySummary)] "
                + "lastWarp=\(String(describing: measurement.lastWarpTarget)) "
                + "finalMouse=\(measurement.finalMouseLocation)"
        )
        return measurement
    }

    /// Mean |Δ| over the RGB channels of a square region of two BGRA buffers.
    func meanAbsoluteRGBDifference(
        _ lhs: ProbeCapturedPixelBuffer,
        _ rhs: ProbeCapturedPixelBuffer,
        rect: CGRect
    ) throws -> Double {
        nonisolated(unsafe) let left = lhs.pixelBuffer
        nonisolated(unsafe) let right = rhs.pixelBuffer
        guard CVPixelBufferGetPixelFormatType(left) == CVPixelBufferGetPixelFormatType(right),
              CVPixelBufferGetWidth(left) == CVPixelBufferGetWidth(right),
              CVPixelBufferGetHeight(left) == CVPixelBufferGetHeight(right)
        else {
            throw NSError(
                domain: "NaruHelperVideoPointerModeTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "probe frames have mismatched formats"]
            )
        }

        CVPixelBufferLockBaseAddress(left, [.readOnly])
        CVPixelBufferLockBaseAddress(right, [.readOnly])
        defer {
            CVPixelBufferUnlockBaseAddress(right, [.readOnly])
            CVPixelBufferUnlockBaseAddress(left, [.readOnly])
        }
        guard let leftBase = CVPixelBufferGetBaseAddress(left),
              let rightBase = CVPixelBufferGetBaseAddress(right)
        else {
            throw NSError(
                domain: "NaruHelperVideoPointerModeTests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "probe frame base address unavailable"]
            )
        }
        let bytesPerRowLeft = CVPixelBufferGetBytesPerRow(left)
        let bytesPerRowRight = CVPixelBufferGetBytesPerRow(right)
        let width = CVPixelBufferGetWidth(left)
        let height = CVPixelBufferGetHeight(left)
        let leftBytes = leftBase.assumingMemoryBound(to: UInt8.self)
        let rightBytes = rightBase.assumingMemoryBound(to: UInt8.self)

        let xRange = max(Int(rect.minX), 0)..<min(Int(rect.maxX), width)
        let yRange = max(Int(rect.minY), 0)..<min(Int(rect.maxY), height)
        guard xRange.lowerBound < xRange.upperBound, yRange.lowerBound < yRange.upperBound else {
            throw NSError(
                domain: "NaruHelperVideoPointerModeTests",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "probe cursor region is empty"]
            )
        }

        var total = 0
        var count = 0
        for y in yRange {
            let leftRow = leftBytes + y * bytesPerRowLeft
            let rightRow = rightBytes + y * bytesPerRowRight
            for x in xRange {
                let offset = x * 4 // BGRA
                total += abs(Int(leftRow[offset]) - Int(rightRow[offset]))
                total += abs(Int(leftRow[offset + 1]) - Int(rightRow[offset + 1]))
                total += abs(Int(leftRow[offset + 2]) - Int(rightRow[offset + 2]))
                count += 3
            }
        }
        return Double(total) / Double(count)
    }
}
#endif
