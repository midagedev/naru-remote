import Foundation
import NaruHelperKit
import NaruRemoteCore

#if os(macOS) && canImport(CoreGraphics)
import CoreGraphics
#endif

public enum BenchmarkHelperVideoProbeMode: String, Codable, Equatable, Sendable {
    case disabled
    case syntheticTCP = "synthetic-tcp"
    case syntheticEncodedTCP = "synthetic-encoded-tcp"
    case screenCaptureKitTCP = "screen-capturekit-tcp"
    case externalHelperSyntheticEncodedTCP = "external-helper-synthetic-encoded-tcp"
    case externalHelperSustainedSyntheticEncodedTCP = "external-helper-sustained-synthetic-encoded-tcp"
    case externalHelperScreenCaptureKitTCP = "external-helper-screen-capturekit-tcp"
    case externalHelperSustainedScreenCaptureKitTCP = "external-helper-sustained-screen-capturekit-tcp"

    public static var usageDescription: String {
        "disabled|synthetic-tcp|synthetic-encoded-tcp|screen-capturekit-tcp|external-helper-synthetic-encoded-tcp|external-helper-sustained-synthetic-encoded-tcp|external-helper-screen-capturekit-tcp|external-helper-sustained-screen-capturekit-tcp"
    }

    public static func parse(_ rawValue: String) -> BenchmarkHelperVideoProbeMode? {
        BenchmarkHelperVideoProbeMode(rawValue: rawValue)
    }
}

public enum BenchmarkHelperVideoProbe {
    public static func makeComparison(
        selection: BenchmarkVisualTransportSelection,
        probeMode: BenchmarkHelperVideoProbeMode,
        screenCaptureKitAccessUnitSource: (any NaruHelperVideoAccessUnitSource)? = nil
    ) -> BenchmarkVisualTransportComparisonReport {
        guard selection.transports.contains(.helperVideo) else {
            return .fakeHelperComparison(selection: selection)
        }

        switch probeMode {
        case .disabled:
            return .fakeHelperComparison(selection: selection)
        case .syntheticTCP:
            return .helperComparison(
                selection: selection,
                helperVideoReport: syntheticTCPHelperVideoReport()
            )
        case .syntheticEncodedTCP:
            return .helperComparison(
                selection: selection,
                helperVideoReport: syntheticTCPHelperVideoReport(
                    accessUnitSource: NaruHelperVideoToolboxSyntheticAccessUnitSource()
                )
            )
        case .screenCaptureKitTCP:
            if screenCaptureKitAccessUnitSource == nil,
               let preflightReport = screenCaptureKitPreflightFailureReport()
            {
                return .helperComparison(
                    selection: selection,
                    helperVideoReport: preflightReport
                )
            }
            return .helperComparison(
                selection: selection,
                helperVideoReport: syntheticTCPHelperVideoReport(
                    accessUnitSource: screenCaptureKitAccessUnitSource
                        ?? NaruHelperVideoScreenCaptureKitAccessUnitSource()
                )
            )
        case .externalHelperSyntheticEncodedTCP:
            return .helperComparison(
                selection: selection,
                helperVideoReport: externalHelperSyntheticEncodedTCPHelperVideoReport()
            )
        case .externalHelperSustainedSyntheticEncodedTCP:
            return .helperComparison(
                selection: selection,
                helperVideoReport: externalHelperSustainedSyntheticEncodedTCPHelperVideoReport()
            )
        case .externalHelperScreenCaptureKitTCP:
            return .helperComparison(
                selection: selection,
                helperVideoReport: externalHelperScreenCaptureKitTCPHelperVideoReport()
            )
        case .externalHelperSustainedScreenCaptureKitTCP:
            return .helperComparison(
                selection: selection,
                helperVideoReport: externalHelperSustainedScreenCaptureKitTCPHelperVideoReport()
            )
        }
    }

    public static func syntheticTCPHelperVideoReport(
        accessUnitSource: any NaruHelperVideoAccessUnitSource = NaruHelperVideoStaticAccessUnitSource(
            accessUnits: [
                NaruHelperVideoAccessUnit(
                    sequence: 0,
                    kind: .parameterSet,
                    binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x67])
                ),
                NaruHelperVideoAccessUnit(
                    sequence: 1,
                    kind: .keyframe,
                    binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
                )
            ]
        )
    ) -> BenchmarkHelperVideoReport {
        do {
            let result = try runSyntheticTCPHelperVideoProbe(accessUnitSource: accessUnitSource)
            let descriptor = result.startResponse.body.streamDescriptor
            let health: HelperVideoStreamHealth
            if let stall = result.stall {
                health = stall.body.health
            } else {
                health = HelperVideoStreamHealth(
                    state: .healthy,
                    startupBand: .fast,
                    sustainedUpdateBand: result.accessUnits.isEmpty ? .stalled : .smooth,
                    decodePressure: .low,
                    fallbackCountBucket: .none
                )
            }
            return BenchmarkHelperVideoReport(
                descriptor: descriptor,
                health: health,
                issueCodes: issueCodes(for: result.stall?.body.reason)
            )
        } catch {
            return failedReport(issueCodes: issueCodes(for: error))
        }
    }

    private static func screenCaptureKitPreflightFailureReport() -> BenchmarkHelperVideoReport? {
        #if os(macOS) && canImport(CoreGraphics)
        guard CGPreflightScreenCaptureAccess() else {
            return failedReport(issueCodes: [.permissionMissing])
        }
        return nil
        #else
        return failedReport()
        #endif
    }

    private static func failedReport(
        issueCodes: [BenchmarkHelperVideoIssueCode] = []
    ) -> BenchmarkHelperVideoReport {
        BenchmarkHelperVideoReport(
            streamState: .failed,
            startupBand: .failed,
            sustainedUpdateBand: .stalled,
            decodePressure: .notMeasured,
            fallbackCountBucket: .one,
            issueCodes: issueCodes
        )
    }

    private static func issueCodes(for error: Error) -> [BenchmarkHelperVideoIssueCode] {
        if let screenCaptureError = error as? NaruHelperVideoScreenCaptureKitAccessUnitSourceError {
            switch screenCaptureError {
            case .screenRecordingPermissionMissing:
                return [.permissionMissing]
            case .unsupportedPlatform, .captureSourceUnavailable:
                return [.captureSourceUnavailable]
            case .captureTimedOut, .noCapturedFrames:
                return [.captureTimedOut]
            case .captureNoOutputCallbacks:
                return [.captureNoOutputCallbacks]
            case .captureNonScreenOutputCallbacks:
                return [.captureNonScreenCallbacks]
            case .captureNonDisplayableScreenFrames:
                return [.captureNonDisplayableFrames]
            case .capturedFrameMissingImageBuffer:
                return [.captureMissingImageBuffer]
            case .captureInsufficientDisplayableFrames:
                return [.captureInsufficientDisplayableFrames]
            case .captureFailed:
                return [.captureFailed]
            }
        }

        if let probeError = error as? BenchmarkHelperVideoProbeError {
            switch probeError {
            case .helperUnavailable:
                return [.externalHelperUnavailable]
            case .helperTimedOut:
                return [.externalHelperTimedOut]
            }
        }

        if let networkError = error as? HelperVideoStreamNetworkClientError {
            switch networkError {
            case .timedOut:
                return [.externalHelperTimedOut]
            case .unreachable,
                 .transportProtectionRequired,
                 .malformedFrame,
                 .missingStartResponse,
                 .unexpectedMessageType:
                return [.transportFailed]
            case .invalidPort:
                return [.externalHelperUnavailable]
            }
        }

        return []
    }

    private static func runSyntheticTCPHelperVideoProbe(
        accessUnitSource: any NaruHelperVideoAccessUnitSource
    ) throws -> HelperVideoStreamNetworkStartResult {
        let pairingSecret = "benchmark-helper-video-synthetic-secret"
        let profileFingerprint = "sha256:benchmark-helper-video-synthetic"
        let requestHandler = NaruHelperVideoTransportRequestHandler(
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
        let pipeline = NaruHelperVideoStreamFramePipeline(
            requestHandler: requestHandler,
            accessUnitSource: accessUnitSource
        )
        let server = try NaruHelperVideoStreamNetworkServer(
            pipeline: pipeline,
            transportProtection: .authenticatedPrivateProfile
        )
        server.start()
        defer { server.cancel() }

        let port = try waitForSyntheticHelperVideoServerPort(server)
        let maxServerFrames = BenchmarkHelperVideoProbeTiming.maxServerFrames
        let clientTimeout = BenchmarkHelperVideoProbeTiming.clientTimeout(
            forLocalSyntheticMaxServerFrames: maxServerFrames
        )
        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: clientTimeout
        )
        return try awaitSynchronously(timeout: clientTimeout + 1.0) {
            try await client.startStream(maxServerFrames: maxServerFrames)
        }
    }

    public static func externalHelperSyntheticEncodedTCPHelperVideoReport(
        helperExecutablePath: String? = nil
    ) -> BenchmarkHelperVideoReport {
        externalHelperVideoReport(
            helperExecutablePath: helperExecutablePath,
            sourceMode: .syntheticEncoded,
            frameCount: BenchmarkHelperVideoProbeTiming.externalHelperSmokeFrameCount
        )
    }

    public static func externalHelperSustainedSyntheticEncodedTCPHelperVideoReport(
        helperExecutablePath: String? = nil
    ) -> BenchmarkHelperVideoReport {
        externalHelperVideoReport(
            helperExecutablePath: helperExecutablePath,
            sourceMode: .syntheticEncoded,
            frameCount: BenchmarkHelperVideoProbeTiming.externalHelperSustainedFrameCount()
        )
    }

    public static func externalHelperScreenCaptureKitTCPHelperVideoReport(
        helperExecutablePath: String? = nil
    ) -> BenchmarkHelperVideoReport {
        return externalHelperVideoReport(
            helperExecutablePath: helperExecutablePath,
            sourceMode: .screenCaptureKit,
            frameCount: BenchmarkHelperVideoProbeTiming.externalHelperSmokeFrameCount
        )
    }

    public static func externalHelperSustainedScreenCaptureKitTCPHelperVideoReport(
        helperExecutablePath: String? = nil
    ) -> BenchmarkHelperVideoReport {
        return externalHelperVideoReport(
            helperExecutablePath: helperExecutablePath,
            sourceMode: .screenCaptureKit,
            frameCount: BenchmarkHelperVideoProbeTiming.externalHelperSustainedFrameCount(),
            allowsPartialResultOnTimeout: true
        )
    }

    private static func externalHelperVideoReport(
        helperExecutablePath: String?,
        sourceMode: NaruHelperVideoListenSourceMode,
        frameCount: Int,
        allowsPartialResultOnTimeout: Bool = false
    ) -> BenchmarkHelperVideoReport {
        do {
            let result = try runExternalHelperTCPProbe(
                helperExecutablePath: helperExecutablePath,
                sourceMode: sourceMode,
                frameCount: frameCount,
                allowsPartialResultOnTimeout: allowsPartialResultOnTimeout
            )
            return helperVideoReport(
                for: result,
                expectedMediaFrameCount: BenchmarkHelperVideoProbeTiming
                    .clampedExternalHelperFrameCount(frameCount)
            )
        } catch {
            return failedReport(issueCodes: issueCodes(for: error))
        }
    }

    private static func helperVideoReport(
        for result: HelperVideoStreamNetworkStartResult,
        expectedMediaFrameCount: Int? = nil
    ) -> BenchmarkHelperVideoReport {
        let startBody = result.startResponse.body
        guard startBody.result == .accepted else {
            return failedReport(issueCodes: issueCodes(for: startBody.safeFailureCode))
        }
        let sustainedUpdateBand = sustainedUpdateBand(
            receivedAccessUnitCount: result.accessUnits.count,
            expectedMediaFrameCount: expectedMediaFrameCount
        )
        let health = HelperVideoStreamHealth(
            state: sustainedUpdateBand == .stalled ? .stalled : .healthy,
            startupBand: .fast,
            sustainedUpdateBand: sustainedUpdateBand,
            decodePressure: .low,
            fallbackCountBucket: sustainedUpdateBand == .stalled ? .one : .none
        )
        return BenchmarkHelperVideoReport(
            descriptor: startBody.streamDescriptor,
            health: health,
            issueCodes: issueCodes(for: result.stall?.body.reason)
        )
    }

    private static func sustainedUpdateBand(
        receivedAccessUnitCount: Int,
        expectedMediaFrameCount: Int?
    ) -> HelperVideoSustainedUpdateBand {
        guard receivedAccessUnitCount > 0 else {
            return .stalled
        }
        guard let expectedMediaFrameCount else {
            return .smooth
        }
        let expectedAccessUnitCount = max(expectedMediaFrameCount, 1) + 1
        let ratio = Double(receivedAccessUnitCount) / Double(expectedAccessUnitCount)
        if ratio >= 0.9 {
            return .smooth
        }
        if ratio >= 0.6 {
            return .usable
        }
        return .choppy
    }

    private static func issueCodes(
        for stallReason: HelperVideoStreamStallReason?
    ) -> [BenchmarkHelperVideoIssueCode] {
        switch stallReason {
        case .screenCaptureSourceUnavailable:
            return [.captureSourceUnavailable]
        case .screenCaptureTimedOut:
            return [.captureTimedOut]
        case .screenCaptureNoOutputCallbacks:
            return [.captureNoOutputCallbacks]
        case .screenCaptureNonScreenCallbacks:
            return [.captureNonScreenCallbacks]
        case .screenCaptureNonDisplayableFrames:
            return [.captureNonDisplayableFrames]
        case .screenCaptureMissingImageBuffer:
            return [.captureMissingImageBuffer]
        case .screenCaptureInsufficientDisplayableFrames:
            return [.captureInsufficientDisplayableFrames]
        case .screenCaptureFailed:
            return [.captureFailed]
        case .noAccessUnit,
             .encoderUnavailable,
             .transportBackpressure,
             .unknown,
             .none:
            return []
        }
    }

    private static func issueCodes(
        for failureCode: HelperVideoFailureCode?
    ) -> [BenchmarkHelperVideoIssueCode] {
        switch failureCode {
        case .permissionMissing:
            return [.permissionMissing]
        case .notConfigured,
             .disabled,
             .authFailed,
             .codecUnsupported,
             .streamStalled,
             .decoderRejected,
             .revoked,
             .transportFailed,
             .transportProtectionRequired,
             .fallbackToVNC,
             .privateNetworkRequired,
             .none:
            return []
        }
    }

    private static func runExternalHelperTCPProbe(
        helperExecutablePath: String?,
        sourceMode: NaruHelperVideoListenSourceMode,
        frameCount: Int,
        allowsPartialResultOnTimeout: Bool = false
    ) throws -> HelperVideoStreamNetworkStartResult {
        var lastError: Error?
        for _ in 0..<BenchmarkHelperVideoProbeTiming.externalHelperPortAttempts {
            do {
                return try runExternalHelperTCPProbe(
                    helperExecutablePath: helperExecutablePath,
                    sourceMode: sourceMode,
                    frameCount: frameCount,
                    port: externalHelperPortCandidate(),
                    allowsPartialResultOnTimeout: allowsPartialResultOnTimeout
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? BenchmarkHelperVideoProbeError.helperUnavailable
    }

    private static func runExternalHelperTCPProbe(
        helperExecutablePath: String?,
        sourceMode: NaruHelperVideoListenSourceMode,
        frameCount: Int,
        port: UInt16,
        allowsPartialResultOnTimeout: Bool = false
    ) throws -> HelperVideoStreamNetworkStartResult {
        let pairingSecret = "benchmark-helper-video-external-secret"
        let profileFingerprint = "sha256:benchmark-helper-video-external"
        let clampedFrameCount = BenchmarkHelperVideoProbeTiming.clampedExternalHelperFrameCount(
            frameCount
        )
        let process = Process()
        process.executableURL = helperExecutableURL(helperExecutablePath)
        process.arguments = [
            "--video-listen",
            "--token-env",
            "NARU_HELPER_VIDEO_BENCHMARK_TOKEN",
            "--profile-fingerprint-env",
            "NARU_HELPER_VIDEO_BENCHMARK_PROFILE_FINGERPRINT",
            "--port",
            "\(port)",
            "--video-source",
            sourceMode.rawValue,
            "--video-frame-count",
            "\(clampedFrameCount)"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["NARU_HELPER_VIDEO_BENCHMARK_TOKEN"] = pairingSecret
        environment["NARU_HELPER_VIDEO_BENCHMARK_PROFILE_FINGERPRINT"] = profileFingerprint
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw BenchmarkHelperVideoProbeError.helperUnavailable
        }
        defer {
            BenchmarkProcessWaiter.terminateAndWait(
                process,
                graceTimeout: BenchmarkHelperVideoProbeTiming.externalHelperTerminationGraceTimeout
            )
        }
        Thread.sleep(forTimeInterval: BenchmarkHelperVideoProbeTiming.externalHelperLaunchSettle)
        guard process.isRunning else {
            throw BenchmarkHelperVideoProbeError.helperUnavailable
        }

        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            transportProtection: .authenticatedPrivateProfile,
            timeout: BenchmarkHelperVideoProbeTiming.clientTimeout(
                forExternalHelperFrameCount: clampedFrameCount
            )
        )
        return try retryExternalHelperStart(
            startStreamTimeout: BenchmarkHelperVideoProbeTiming.startStreamTimeout(
                forExternalHelperFrameCount: clampedFrameCount
            )
        ) {
            try await client.startStream(
                maxServerFrames: BenchmarkHelperVideoProbeTiming.maxServerFrames(
                    forExternalHelperFrameCount: clampedFrameCount
                ),
                allowsPartialResultOnTimeout: allowsPartialResultOnTimeout
            )
        }
    }

    private static func retryExternalHelperStart(
        startStreamTimeout: TimeInterval = BenchmarkHelperVideoProbeTiming.startStreamTimeout,
        operation: @escaping @Sendable () async throws -> HelperVideoStreamNetworkStartResult
    ) throws -> HelperVideoStreamNetworkStartResult {
        let deadline = Date().addingTimeInterval(
            BenchmarkHelperVideoProbeTiming.externalHelperReadyTimeout
        )
        var lastError: Error?
        repeat {
            do {
                return try awaitSynchronously(
                    timeout: startStreamTimeout,
                    operation: operation
                )
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: BenchmarkHelperVideoProbeTiming.serverPortPollInterval)
            }
        } while Date() < deadline
        throw lastError ?? BenchmarkHelperVideoProbeError.helperUnavailable
    }

    private static func helperExecutableURL(_ path: String?) -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let executablePath = path ?? environment["NARU_HELPER_EXECUTABLE"],
           !executablePath.isEmpty
        {
            return fileURL(forExecutablePath: executablePath)
        }
        for productsDirectoryKey in ["BUILT_PRODUCTS_DIR", "CONFIGURATION_BUILD_DIR"] {
            guard let productsDirectory = environment[productsDirectoryKey],
                  !productsDirectory.isEmpty
            else {
                continue
            }
            return fileURL(forExecutablePath: productsDirectory)
                .appendingPathComponent("NaruHelper")
        }
        return fileURL(forExecutablePath: ".build/debug/NaruHelper")
    }

    private static func fileURL(forExecutablePath executablePath: String) -> URL {
        guard executablePath.hasPrefix("/") else {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(executablePath)
        }
        return URL(fileURLWithPath: executablePath)
    }

    private static func externalHelperPortCandidate() -> UInt16 {
        UInt16.random(in: UInt16(49_152)...UInt16.max)
    }

    private static func waitForSyntheticHelperVideoServerPort(
        _ server: NaruHelperVideoStreamNetworkServer
    ) throws -> UInt16 {
        let deadline = Date().addingTimeInterval(BenchmarkHelperVideoProbeTiming.serverPortTimeout)
        while Date() < deadline {
            if let port = server.port, port > 0 {
                Thread.sleep(forTimeInterval: BenchmarkHelperVideoProbeTiming.postPortReadySettle)
                return port
            }
            Thread.sleep(forTimeInterval: BenchmarkHelperVideoProbeTiming.serverPortPollInterval)
        }
        throw BenchmarkHelperVideoProbeError.helperUnavailable
    }

    private static func awaitSynchronously<T: Sendable>(
        timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = BenchmarkLockedResultBox<T>()
        Task {
            do {
                box.store(.success(try await operation()))
            } catch {
                box.store(.failure(error))
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw BenchmarkHelperVideoProbeError.helperTimedOut
        }
        return try box.value().get()
    }
}

private enum BenchmarkHelperVideoProbeError: Error {
    case helperUnavailable
    case helperTimedOut
}

enum BenchmarkHelperVideoProbeTiming {
    static let maxServerFrames = 6
    static let externalHelperSmokeFrameCount = 2
    static let externalHelperSustainedDefaultFrameCount = 30
    static let externalHelperFrameCountRange = 1...120
    static let externalHelperSustainedFrameCountRange = 6...120
    static let serverPortTimeout: TimeInterval = 2
    static let externalHelperPortAttempts = 3
    static let externalHelperLaunchSettle: TimeInterval = 0.25
    static let externalHelperReadyTimeout: TimeInterval = 2
    static let externalHelperTerminationGraceTimeout: TimeInterval = 0.5
    static let serverPortPollInterval: TimeInterval = 0.02
    static let postPortReadySettle: TimeInterval = 0.05
    static let clientTimeout: TimeInterval = 2
    static let startStreamTimeout: TimeInterval = 3

    static func externalHelperSustainedFrameCount(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        guard let rawValue = environment["NARU_HELPER_VIDEO_SUSTAINED_FRAME_COUNT"],
              let frameCount = Int(rawValue)
        else {
            return externalHelperSustainedDefaultFrameCount
        }
        return min(
            max(frameCount, externalHelperSustainedFrameCountRange.lowerBound),
            externalHelperSustainedFrameCountRange.upperBound
        )
    }

    static func clampedExternalHelperFrameCount(_ frameCount: Int) -> Int {
        min(
            max(frameCount, externalHelperFrameCountRange.lowerBound),
            externalHelperFrameCountRange.upperBound
        )
    }

    static func maxServerFrames(forExternalHelperFrameCount frameCount: Int) -> Int {
        max(clampedExternalHelperFrameCount(frameCount) + 2, 1)
    }

    static func clientTimeout(forExternalHelperFrameCount frameCount: Int) -> TimeInterval {
        max(clientTimeout, Double(clampedExternalHelperFrameCount(frameCount)) / 15.0 + 4.0)
    }

    static func startStreamTimeout(forExternalHelperFrameCount frameCount: Int) -> TimeInterval {
        clientTimeout(forExternalHelperFrameCount: frameCount) + 1.0
    }

    static func clientTimeout(forLocalSyntheticMaxServerFrames maxServerFrames: Int) -> TimeInterval {
        max(clientTimeout, Double(max(maxServerFrames, 1)) / 15.0 + 4.0)
    }
}

private final class BenchmarkLockedResultBox<T>: @unchecked Sendable {
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
                throw BenchmarkHelperVideoProbeError.helperUnavailable
            }
            return result
        }
    }
}
