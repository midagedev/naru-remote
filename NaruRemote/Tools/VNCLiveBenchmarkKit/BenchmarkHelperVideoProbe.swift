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
    case externalHelperScreenCaptureKitTCP = "external-helper-screen-capturekit-tcp"

    public static var usageDescription: String {
        "disabled|synthetic-tcp|synthetic-encoded-tcp|screen-capturekit-tcp|external-helper-synthetic-encoded-tcp|external-helper-screen-capturekit-tcp"
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
        case .externalHelperScreenCaptureKitTCP:
            return .helperComparison(
                selection: selection,
                helperVideoReport: externalHelperScreenCaptureKitTCPHelperVideoReport()
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
            return BenchmarkHelperVideoReport(descriptor: descriptor, health: health)
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
        guard let screenCaptureError = error as? NaruHelperVideoScreenCaptureKitAccessUnitSourceError
        else {
            return []
        }

        switch screenCaptureError {
        case .screenRecordingPermissionMissing:
            return [.permissionMissing]
        case .unsupportedPlatform,
             .captureSourceUnavailable,
             .captureTimedOut,
             .captureFailed,
             .capturedFrameMissingImageBuffer,
             .noCapturedFrames:
            return []
        }
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
        let server = try NaruHelperVideoStreamNetworkServer(pipeline: pipeline)
        server.start()
        defer { server.cancel() }

        let port = try waitForSyntheticHelperVideoServerPort(server)
        let client = HelperVideoStreamNetworkClient(
            host: "127.0.0.1",
            port: port,
            profileFingerprint: profileFingerprint,
            pairingSecret: pairingSecret,
            timeout: BenchmarkHelperVideoProbeTiming.clientTimeout
        )
        return try awaitSynchronously(timeout: BenchmarkHelperVideoProbeTiming.startStreamTimeout) {
            try await client.startStream(maxServerFrames: BenchmarkHelperVideoProbeTiming.maxServerFrames)
        }
    }

    public static func externalHelperSyntheticEncodedTCPHelperVideoReport(
        helperExecutablePath: String? = nil
    ) -> BenchmarkHelperVideoReport {
        externalHelperVideoReport(
            helperExecutablePath: helperExecutablePath,
            sourceMode: .syntheticEncoded
        )
    }

    public static func externalHelperScreenCaptureKitTCPHelperVideoReport(
        helperExecutablePath: String? = nil
    ) -> BenchmarkHelperVideoReport {
        return externalHelperVideoReport(
            helperExecutablePath: helperExecutablePath,
            sourceMode: .screenCaptureKit
        )
    }

    private static func externalHelperVideoReport(
        helperExecutablePath: String?,
        sourceMode: NaruHelperVideoListenSourceMode
    ) -> BenchmarkHelperVideoReport {
        do {
            let result = try runExternalHelperTCPProbe(
                helperExecutablePath: helperExecutablePath,
                sourceMode: sourceMode
            )
            return helperVideoReport(for: result)
        } catch {
            return failedReport()
        }
    }

    private static func helperVideoReport(
        for result: HelperVideoStreamNetworkStartResult
    ) -> BenchmarkHelperVideoReport {
        let startBody = result.startResponse.body
        guard startBody.result == .accepted else {
            return failedReport(issueCodes: issueCodes(for: startBody.safeFailureCode))
        }
        let health = HelperVideoStreamHealth(
            state: .healthy,
            startupBand: .fast,
            sustainedUpdateBand: result.accessUnits.isEmpty ? .stalled : .smooth,
            decodePressure: .low,
            fallbackCountBucket: .none
        )
        return BenchmarkHelperVideoReport(
            descriptor: startBody.streamDescriptor,
            health: health
        )
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
             .fallbackToVNC,
             .privateNetworkRequired,
             .none:
            return []
        }
    }

    private static func runExternalHelperTCPProbe(
        helperExecutablePath: String?,
        sourceMode: NaruHelperVideoListenSourceMode
    ) throws -> HelperVideoStreamNetworkStartResult {
        var lastError: Error?
        for _ in 0..<BenchmarkHelperVideoProbeTiming.externalHelperPortAttempts {
            do {
                return try runExternalHelperTCPProbe(
                    helperExecutablePath: helperExecutablePath,
                    sourceMode: sourceMode,
                    port: externalHelperPortCandidate()
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
        port: UInt16
    ) throws -> HelperVideoStreamNetworkStartResult {
        let pairingSecret = "benchmark-helper-video-external-secret"
        let profileFingerprint = "sha256:benchmark-helper-video-external"
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
            "2"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["NARU_HELPER_VIDEO_BENCHMARK_TOKEN"] = pairingSecret
        environment["NARU_HELPER_VIDEO_BENCHMARK_PROFILE_FINGERPRINT"] = profileFingerprint
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
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
            timeout: BenchmarkHelperVideoProbeTiming.clientTimeout
        )
        return try retryExternalHelperStart {
            try await client.startStream(maxServerFrames: BenchmarkHelperVideoProbeTiming.maxServerFrames)
        }
    }

    private static func retryExternalHelperStart(
        operation: @escaping @Sendable () async throws -> HelperVideoStreamNetworkStartResult
    ) throws -> HelperVideoStreamNetworkStartResult {
        let deadline = Date().addingTimeInterval(
            BenchmarkHelperVideoProbeTiming.externalHelperReadyTimeout
        )
        var lastError: Error?
        repeat {
            do {
                return try awaitSynchronously(
                    timeout: BenchmarkHelperVideoProbeTiming.startStreamTimeout,
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

private enum BenchmarkHelperVideoProbeTiming {
    static let maxServerFrames = 6
    static let serverPortTimeout: TimeInterval = 2
    static let externalHelperPortAttempts = 3
    static let externalHelperLaunchSettle: TimeInterval = 0.25
    static let externalHelperReadyTimeout: TimeInterval = 2
    static let externalHelperTerminationGraceTimeout: TimeInterval = 0.5
    static let serverPortPollInterval: TimeInterval = 0.02
    static let postPortReadySettle: TimeInterval = 0.05
    static let clientTimeout: TimeInterval = 2
    static let startStreamTimeout: TimeInterval = 3
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
