import Darwin
import Foundation
import NaruRemoteCore

private let toolName = "VNCLiveBenchmark"

@main
enum VNCLiveBenchmark {
    static func main() {
        do {
            let options = try BenchmarkOptions.parse(CommandLine.arguments.dropFirst())
            if options.showHelp {
                printUsage()
                return
            }

            guard let configuration = LiveTargetConfiguration.fromEnvironment() else {
                printUsage()
                print("\nerror: set NARU_LIVE_MAC_HOST and NARU_LIVE_MAC_PASSWORD before running.")
                exit(2)
            }

            let report = try run(configuration: configuration, options: options)
            if options.json {
                try renderJSON(report)
            } else {
                renderText(report)
            }
        } catch let error as UsageError {
            printUsage()
            print("\nerror: \(error.message)")
            exit(2)
        } catch {
            print("error: benchmark failed with \(safeFailureLabel(for: error)).")
            exit(1)
        }
    }

    private static func run(
        configuration: LiveTargetConfiguration,
        options: BenchmarkOptions
    ) throws -> BenchmarkReport {
        let profiles = BenchmarkProfile.allCases.map { profile in
            measureProfile(
                profile,
                configuration: configuration,
                attempts: options.attempts,
                timeout: options.timeout
            )
        }

        let idleProbe = measureIdleProbe(
            configuration: configuration,
            timeout: options.timeout,
            idleTimeout: options.idleTimeout
        )
        let continuousUpdatesProbe = measureContinuousUpdatesProbe(
            configuration: configuration,
            timeout: options.timeout,
            idleTimeout: options.idleTimeout
        )

        return BenchmarkReport(
            attemptsPerProfile: options.attempts,
            timeoutSeconds: options.timeout,
            idleTimeoutSeconds: options.idleTimeout,
            profiles: profiles,
            idleProbe: idleProbe,
            continuousUpdatesProbe: continuousUpdatesProbe
        )
    }

    private static func measureProfile(
        _ profile: BenchmarkProfile,
        configuration: LiveTargetConfiguration,
        attempts: Int,
        timeout: TimeInterval
    ) -> ProfileReport {
        var durations: [Int] = []
        var failures: [String: Int] = [:]

        for _ in 0..<attempts {
            let client = RFBNetworkClient(encodingPreference: profile.preference)
            let startedAt = Date()
            do {
                _ = try client.connectSession(
                    host: configuration.host,
                    port: configuration.port,
                    credential: .vncPassword(configuration.password),
                    timeout: timeout
                )
                _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)
                durations.append(milliseconds(since: startedAt))
            } catch {
                failures[safeFailureLabel(for: error), default: 0] += 1
            }
            client.disconnect()
        }

        return ProfileReport(
            label: profile.label,
            attempted: attempts,
            firstFrameMilliseconds: durations,
            failureLabels: failures
        )
    }

    private static func measureIdleProbe(
        configuration: LiveTargetConfiguration,
        timeout: TimeInterval,
        idleTimeout: TimeInterval
    ) -> IdleProbeReport {
        let client = RFBNetworkClient(encodingPreference: .localLowLatency)
        do {
            _ = try client.connectSession(
                host: configuration.host,
                port: configuration.port,
                credential: .vncPassword(configuration.password),
                timeout: timeout
            )
            _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)

            let startedAt = Date()
            let update = try client.requestFramebufferUpdate(incremental: true, timeout: idleTimeout)
            let duration = milliseconds(since: startedAt)
            client.disconnect()

            return IdleProbeReport(
                status: update.changedPixelCount == 0 ? .emptyUpdate : .contentUpdate,
                durationMilliseconds: duration,
                failureLabel: nil
            )
        } catch RFBNetworkClientError.timedOut {
            client.disconnect()
            return IdleProbeReport(
                status: .held,
                durationMilliseconds: milliseconds(from: idleTimeout),
                failureLabel: nil
            )
        } catch {
            client.disconnect()
            return IdleProbeReport(
                status: .failed,
                durationMilliseconds: nil,
                failureLabel: safeFailureLabel(for: error)
            )
        }
    }

    private static func measureContinuousUpdatesProbe(
        configuration: LiveTargetConfiguration,
        timeout: TimeInterval,
        idleTimeout: TimeInterval
    ) -> ContinuousUpdatesProbeReport {
        let preference = RFBEncodingPreference(
            hextile: true,
            copyRect: true,
            fence: true,
            continuousUpdates: true
        )
        let client = RFBNetworkClient(encodingPreference: preference)

        do {
            _ = try client.connectSession(
                host: configuration.host,
                port: configuration.port,
                credential: .vncPassword(configuration.password),
                timeout: timeout
            )
            _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)

            try client.enableContinuousUpdates(true, region: nil, timeout: timeout)

            let startedAt = Date()
            let update = try client.receiveFramebufferUpdate(timeout: idleTimeout)
            let duration = milliseconds(since: startedAt)
            try? client.enableContinuousUpdates(false, region: nil, timeout: timeout)
            client.disconnect()

            return ContinuousUpdatesProbeReport(
                status: update.changedPixelCount == 0 ? .emptyUpdate : .contentUpdate,
                durationMilliseconds: duration,
                failureLabel: nil
            )
        } catch RFBNetworkClientError.timedOut {
            try? client.enableContinuousUpdates(false, region: nil, timeout: timeout)
            client.disconnect()
            return ContinuousUpdatesProbeReport(
                status: .noUpdateBeforeTimeout,
                durationMilliseconds: milliseconds(from: idleTimeout),
                failureLabel: nil
            )
        } catch {
            client.disconnect()
            return ContinuousUpdatesProbeReport(
                status: .failed,
                durationMilliseconds: nil,
                failureLabel: safeFailureLabel(for: error)
            )
        }
    }

    private static func milliseconds(since start: Date) -> Int {
        milliseconds(from: Date().timeIntervalSince(start))
    }

    private static func milliseconds(from seconds: TimeInterval) -> Int {
        Int((seconds * 1_000).rounded())
    }
}

private struct BenchmarkOptions: Equatable {
    var attempts = 3
    var timeout: TimeInterval = 5
    var idleTimeout: TimeInterval = 0.75
    var json = false
    var showHelp = false

    static func parse(_ arguments: ArraySlice<String>) throws -> BenchmarkOptions {
        var options = BenchmarkOptions()
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                options.showHelp = true
                index = arguments.index(after: index)
            case "--json":
                options.json = true
                index = arguments.index(after: index)
            case "--attempts":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let attempts = Int(value), attempts > 0 else {
                    throw UsageError("attempts must be a positive integer.")
                }
                options.attempts = attempts
                index = arguments.index(index, offsetBy: 2)
            case "--timeout":
                let value = try nextValue(after: index, in: arguments, option: argument)
                options.timeout = try positiveTimeInterval(value, option: argument)
                index = arguments.index(index, offsetBy: 2)
            case "--idle-timeout":
                let value = try nextValue(after: index, in: arguments, option: argument)
                options.idleTimeout = try positiveTimeInterval(value, option: argument)
                index = arguments.index(index, offsetBy: 2)
            default:
                throw UsageError("unknown option \(argument).")
            }
        }

        return options
    }

    private static func nextValue(
        after index: ArraySlice<String>.Index,
        in arguments: ArraySlice<String>,
        option: String
    ) throws -> String {
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else {
            throw UsageError("\(option) requires a value.")
        }
        return arguments[nextIndex]
    }

    private static func positiveTimeInterval(_ value: String, option: String) throws -> TimeInterval {
        guard let interval = TimeInterval(value), interval > 0 else {
            throw UsageError("\(option) must be a positive number of seconds.")
        }
        return interval
    }
}

private struct UsageError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

private struct LiveTargetConfiguration {
    let host: String
    let port: UInt16
    let password: String

    static func fromEnvironment() -> LiveTargetConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let host = environment["NARU_LIVE_MAC_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !host.isEmpty,
            let password = environment["NARU_LIVE_MAC_PASSWORD"],
            !password.isEmpty
        else {
            return nil
        }

        let portText = environment["NARU_LIVE_MAC_PORT"] ?? "5900"
        guard let port = UInt16(portText), port > 0 else {
            return nil
        }

        return LiveTargetConfiguration(host: host, port: port, password: password)
    }
}

private enum BenchmarkProfile: CaseIterable {
    case localLowLatency
    case zrleFirst
    case zrleCompressionZero
    case adaptiveGoodZRLE
    case adaptivePoorZRLE

    var label: String {
        switch self {
        case .localLowLatency:
            "local-low-latency"
        case .zrleFirst:
            "zrle-first"
        case .zrleCompressionZero:
            "zrle-compression-0"
        case .adaptiveGoodZRLE:
            "adaptive-good-zrle"
        case .adaptivePoorZRLE:
            "adaptive-poor-zrle"
        }
    }

    var preference: RFBEncodingPreference {
        switch self {
        case .localLowLatency:
            return .localLowLatency
        case .zrleFirst:
            return .increment2
        case .zrleCompressionZero:
            return RFBEncodingPreference(zrle: true, compressionLevel: 0)
        case .adaptiveGoodZRLE:
            return .adaptive(supported: .increment2, connectionQuality: .good)
        case .adaptivePoorZRLE:
            return .adaptive(supported: .increment2, connectionQuality: .poor)
        }
    }
}

private struct BenchmarkReport: Codable, Equatable {
    let schemaVersion: Int
    let target: String
    let attemptsPerProfile: Int
    let timeoutSeconds: TimeInterval
    let idleTimeoutSeconds: TimeInterval
    let safety: [String]
    let profiles: [ProfileReport]
    let idleProbe: IdleProbeReport
    let continuousUpdatesProbe: ContinuousUpdatesProbeReport

    init(
        attemptsPerProfile: Int,
        timeoutSeconds: TimeInterval,
        idleTimeoutSeconds: TimeInterval,
        profiles: [ProfileReport],
        idleProbe: IdleProbeReport,
        continuousUpdatesProbe: ContinuousUpdatesProbeReport
    ) {
        self.schemaVersion = 2
        self.target = "configured-redacted"
        self.attemptsPerProfile = attemptsPerProfile
        self.timeoutSeconds = timeoutSeconds
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.safety = [
            "host, password, server name, framebuffer dimensions, pixel payloads, byte counts, cursor pixels, and raw error descriptions are not emitted",
            "reports are written to stdout only"
        ]
        self.profiles = profiles
        self.idleProbe = idleProbe
        self.continuousUpdatesProbe = continuousUpdatesProbe
    }
}

private struct ProfileReport: Codable, Equatable {
    let label: String
    let attempted: Int
    let succeeded: Int
    let failed: Int
    let averageFirstFrameMilliseconds: Int?
    let minFirstFrameMilliseconds: Int?
    let maxFirstFrameMilliseconds: Int?
    let failureLabels: [String: Int]

    init(label: String, attempted: Int, firstFrameMilliseconds: [Int], failureLabels: [String: Int]) {
        self.label = label
        self.attempted = attempted
        self.succeeded = firstFrameMilliseconds.count
        self.failed = attempted - firstFrameMilliseconds.count
        if firstFrameMilliseconds.isEmpty {
            self.averageFirstFrameMilliseconds = nil
            self.minFirstFrameMilliseconds = nil
            self.maxFirstFrameMilliseconds = nil
        } else {
            self.averageFirstFrameMilliseconds = firstFrameMilliseconds.reduce(0, +) / firstFrameMilliseconds.count
            self.minFirstFrameMilliseconds = firstFrameMilliseconds.min()
            self.maxFirstFrameMilliseconds = firstFrameMilliseconds.max()
        }
        self.failureLabels = failureLabels
    }
}

private struct IdleProbeReport: Codable, Equatable {
    let status: IdleProbeStatus
    let durationMilliseconds: Int?
    let failureLabel: String?
}

private enum IdleProbeStatus: String, Codable {
    case held
    case emptyUpdate = "empty-update"
    case contentUpdate = "content-update"
    case failed
}

private struct ContinuousUpdatesProbeReport: Codable, Equatable {
    let status: ContinuousUpdatesProbeStatus
    let durationMilliseconds: Int?
    let failureLabel: String?
}

private enum ContinuousUpdatesProbeStatus: String, Codable {
    case noUpdateBeforeTimeout = "no-update-before-timeout"
    case emptyUpdate = "empty-update"
    case contentUpdate = "content-update"
    case failed
}

private func renderText(_ report: BenchmarkReport) {
    print("\(toolName)")
    print("target: \(report.target)")
    print("safety: host/password/server name/framebuffer dimensions/pixels/byte counts/cursor pixels/raw errors are not emitted")
    print("attempts per profile: \(report.attemptsPerProfile)")
    print("timeout seconds: \(formatSeconds(report.timeoutSeconds))")
    print("idle timeout seconds: \(formatSeconds(report.idleTimeoutSeconds))")
    print("")
    print("profiles:")
    for profile in report.profiles {
        print("- \(profile.label): \(profile.succeeded)/\(profile.attempted) succeeded")
        if let average = profile.averageFirstFrameMilliseconds,
           let minimum = profile.minFirstFrameMilliseconds,
           let maximum = profile.maxFirstFrameMilliseconds {
            print("  first-frame ms avg/min/max: \(average)/\(minimum)/\(maximum)")
        } else {
            print("  first-frame ms avg/min/max: n/a")
        }
        if profile.failureLabels.isEmpty {
            print("  failures: none")
        } else {
            print("  failures: \(formatFailureLabels(profile.failureLabels))")
        }
    }
    print("")
    print("idle probe:")
    if let duration = report.idleProbe.durationMilliseconds {
        print("- status: \(report.idleProbe.status.rawValue), duration ms: \(duration)")
    } else if let failure = report.idleProbe.failureLabel {
        print("- status: \(report.idleProbe.status.rawValue), failure: \(failure)")
    } else {
        print("- status: \(report.idleProbe.status.rawValue)")
    }
    print("")
    print("continuous updates probe:")
    if let duration = report.continuousUpdatesProbe.durationMilliseconds {
        print("- status: \(report.continuousUpdatesProbe.status.rawValue), duration ms: \(duration)")
    } else if let failure = report.continuousUpdatesProbe.failureLabel {
        print("- status: \(report.continuousUpdatesProbe.status.rawValue), failure: \(failure)")
    } else {
        print("- status: \(report.continuousUpdatesProbe.status.rawValue)")
    }
}

private func renderJSON(_ report: BenchmarkReport) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    print(String(decoding: data, as: UTF8.self))
}

private func formatSeconds(_ value: TimeInterval) -> String {
    let rounded = (value * 1_000).rounded() / 1_000
    return String(format: "%.3f", rounded)
}

private func formatFailureLabels(_ failures: [String: Int]) -> String {
    failures
        .sorted { lhs, rhs in lhs.key < rhs.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ", ")
}

private func printUsage() {
    print("""
    Usage:
      swift run VNCLiveBenchmark [--attempts N] [--timeout SECONDS] [--idle-timeout SECONDS] [--json]

    Required environment:
      NARU_LIVE_MAC_HOST       redacted from output
      NARU_LIVE_MAC_PASSWORD   redacted from output
      NARU_LIVE_MAC_PORT       optional, defaults to 5900

    The report intentionally omits target identity, framebuffer dimensions,
    pixel payloads, byte counts, cursor pixels, and raw error descriptions.
    """)
}

private func safeFailureLabel(for error: Error) -> String {
    switch error {
    case RFBNetworkClientError.invalidPort:
        return "invalid-port"
    case RFBNetworkClientError.timedOut:
        return "timeout"
    case RFBNetworkClientError.incompleteTranscript:
        return "incomplete-transcript"
    case RFBNetworkClientError.connectionFailed:
        return "connection-failed"
    case RFBNetworkClientError.writeFailed:
        return "write-failed"
    case RFBNetworkClientError.authenticationRequired:
        return "authentication-required"
    case RFBNetworkClientError.unsupportedSecurityTypes:
        return "unsupported-security-types"
    case RFBNetworkClientError.unsupportedFramebufferEncoding:
        return "unsupported-framebuffer-encoding"
    case RFBNetworkClientError.notConnected:
        return "not-connected"
    case RFBProtocolDecoderError.insufficientData:
        return "protocol-insufficient-data"
    case RFBProtocolDecoderError.invalidProtocolVersion:
        return "invalid-protocol-version"
    case RFBProtocolDecoderError.securityFailed:
        return "security-failed"
    case RFBProtocolDecoderError.unexpectedMessageType:
        return "unexpected-message-type"
    case RFBProtocolDecoderError.truncatedServerCutText:
        return "truncated-server-cuttext"
    case RFBProtocolDecoderError.invalidServerCutTextEncoding:
        return "invalid-server-cuttext-encoding"
    case RFBRawFramebufferDecoderError.unsupportedPixelFormat:
        return "unsupported-pixel-format"
    case RFBRawFramebufferDecoderError.unsupportedEncoding:
        return "unsupported-encoding"
    case RFBRawFramebufferDecoderError.rectangleOutOfBounds:
        return "rectangle-out-of-bounds"
    case RFBRawFramebufferDecoderError.insufficientPixelData:
        return "insufficient-pixel-data"
    case RFBRawFramebufferDecoderError.framebufferSizeMismatch:
        return "framebuffer-size-mismatch"
    case RFBRawFramebufferDecoderError.copyRectOutOfBounds:
        return "copyrect-out-of-bounds"
    case RFBRawFramebufferDecoderError.malformedHextile:
        return "malformed-hextile"
    case RFBRawFramebufferDecoderError.invalidDimensions:
        return "invalid-dimensions"
    case RFBRawFramebufferDecoderError.malformedZRLE:
        return "malformed-zrle"
    case RFBRawFramebufferDecoderError.malformedCursor:
        return "malformed-cursor"
    case RFBClientMessageEncodingError.unsupportedFenceFlags:
        return "client-message-encoding"
    case RFBClientMessageEncodingError.fencePayloadTooLarge:
        return "client-message-encoding"
    default:
        return "unexpected-error"
    }
}
