import Darwin
import Foundation
import NaruRemoteCore
import VNCLiveBenchmarkKit

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

            let passwordOverride = try options.askPassword ? readPasswordFromTerminal() : nil
            guard let configuration = LiveTargetConfiguration.fromEnvironment(
                passwordOverride: passwordOverride
            ) else {
                printUsage()
                print("\nerror: set NARU_LIVE_MAC_HOST and either NARU_LIVE_MAC_PASSWORD or --ask-password before running.")
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
                fullRefreshSamples: options.fullRefreshSamples,
                timeout: options.timeout
            )
        }

        let idleProbe = measureIdleProbe(
            configuration: configuration,
            timeout: options.timeout,
            idleTimeout: options.idleTimeout
        )
        let streamShapeProbe = measureStreamShapeProbe(
            configuration: configuration,
            timeout: options.timeout,
            idleTimeout: options.idleTimeout,
            maxSamples: options.streamShapeSamples,
            frameInterval: options.streamShapeFrameInterval
        )
        let continuousUpdatesProbe = measureContinuousUpdatesProbe(
            configuration: configuration,
            timeout: options.timeout,
            idleTimeout: options.idleTimeout,
            maxSamples: options.continuousUpdateSamples
        )

        return BenchmarkReport(
            attemptsPerProfile: options.attempts,
            fullRefreshSamplesPerAttempt: options.fullRefreshSamples,
            continuousUpdateSamples: options.continuousUpdateSamples,
            timeoutSeconds: options.timeout,
            idleTimeoutSeconds: options.idleTimeout,
            streamShapeSamples: options.streamShapeSamples,
            streamShapeFrameInterval: options.streamShapeFrameInterval,
            profiles: profiles,
            idleProbe: idleProbe,
            streamShapeProbe: streamShapeProbe,
            continuousUpdatesProbe: continuousUpdatesProbe
        )
    }

    private static func measureProfile(
        _ profile: BenchmarkProfile,
        configuration: LiveTargetConfiguration,
        attempts: Int,
        fullRefreshSamples: Int,
        timeout: TimeInterval
    ) -> ProfileReport {
        var firstFrameDurations: [Int] = []
        var fullRefreshDurations: [Int] = []
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
                firstFrameDurations.append(milliseconds(since: startedAt))
            } catch {
                failures["first-frame-\(safeFailureLabel(for: error))", default: 0] += 1
                client.disconnect()
                continue
            }

            for _ in 0..<fullRefreshSamples {
                let refreshStartedAt = Date()
                do {
                    _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)
                    fullRefreshDurations.append(milliseconds(since: refreshStartedAt))
                } catch {
                    failures["full-refresh-\(safeFailureLabel(for: error))", default: 0] += 1
                    break
                }
            }
            client.disconnect()
        }

        return ProfileReport(
            label: profile.label,
            attempted: attempts,
            fullRefreshSamplesPerAttempt: fullRefreshSamples,
            firstFrameMilliseconds: firstFrameDurations,
            fullRefreshMilliseconds: fullRefreshDurations,
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
        idleTimeout: TimeInterval,
        maxSamples: Int
    ) -> ContinuousUpdatesProbeReport {
        let preference = RFBEncodingPreference(
            hextile: true,
            copyRect: true,
            fence: true,
            continuousUpdates: true
        )
        let client = RFBNetworkClient(encodingPreference: preference)
        var samples: [ContinuousUpdateSample] = []
        var timeoutMilliseconds: Int?
        var continuousUpdatesEnabled = false

        do {
            _ = try client.connectSession(
                host: configuration.host,
                port: configuration.port,
                credential: .vncPassword(configuration.password),
                timeout: timeout
            )
            _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)

            try client.enableContinuousUpdates(true, region: nil, timeout: timeout)
            continuousUpdatesEnabled = true

            for _ in 0..<maxSamples {
                let startedAt = Date()
                do {
                    let update = try client.receiveFramebufferUpdate(timeout: idleTimeout)
                    samples.append(ContinuousUpdateSample(
                        kind: update.changedPixelCount == 0 ? .emptyUpdate : .contentUpdate,
                        durationMilliseconds: milliseconds(since: startedAt)
                    ))
                } catch RFBNetworkClientError.timedOut {
                    timeoutMilliseconds = milliseconds(from: idleTimeout)
                    break
                }
            }

            try? client.enableContinuousUpdates(false, region: nil, timeout: timeout)
            client.disconnect()

            return ContinuousUpdatesProbeReport(
                requestedSamples: maxSamples,
                samples: samples,
                timeoutMilliseconds: timeoutMilliseconds,
                failureLabel: nil
            )
        } catch RFBNetworkClientError.timedOut {
            if continuousUpdatesEnabled {
                try? client.enableContinuousUpdates(false, region: nil, timeout: timeout)
            }
            client.disconnect()
            guard continuousUpdatesEnabled else {
                return ContinuousUpdatesProbeReport(
                    requestedSamples: maxSamples,
                    samples: samples,
                    timeoutMilliseconds: nil,
                    failureLabel: "timeout"
                )
            }
            return ContinuousUpdatesProbeReport(
                requestedSamples: maxSamples,
                samples: samples,
                timeoutMilliseconds: milliseconds(from: idleTimeout),
                failureLabel: nil
            )
        } catch {
            client.disconnect()
            return ContinuousUpdatesProbeReport(
                requestedSamples: maxSamples,
                samples: samples,
                timeoutMilliseconds: nil,
                failureLabel: safeFailureLabel(for: error)
            )
        }
    }

    private static func measureStreamShapeProbe(
        configuration: LiveTargetConfiguration,
        timeout: TimeInterval,
        idleTimeout: TimeInterval,
        maxSamples: Int,
        frameInterval: TimeInterval
    ) -> StreamShapeProbeReport {
        guard maxSamples > 0 else {
            return StreamShapeProbeReport(
                requestedSamples: maxSamples,
                firstFrameMilliseconds: nil,
                samples: [],
                elapsedMilliseconds: nil,
                firstTimeoutMilliseconds: nil,
                failureLabel: nil
            )
        }

        let client = RFBNetworkClient(encodingPreference: .localLowLatency)
        let pump = RFBFramePump(source: client)
        var samples: [BenchmarkStreamShapeSample] = []
        var firstFrameMilliseconds: Int?
        var firstTimeoutMilliseconds: Int?
        var elapsedMilliseconds: Int?
        var failureLabel: String?

        do {
            _ = try client.connectSession(
                host: configuration.host,
                port: configuration.port,
                credential: .vncPassword(configuration.password),
                timeout: timeout
            )

            let firstFrameStartedAt = Date()
            _ = try pump.nextFrame(requestTimeout: timeout)
            firstFrameMilliseconds = milliseconds(since: firstFrameStartedAt)

            let streamStartedAt = Date()
            for _ in 0..<maxSamples {
                let startedAt = Date()
                do {
                    guard let frame = try pump.nextFrame(requestTimeout: idleTimeout) else {
                        break
                    }
                    samples.append(streamShapeSample(
                        from: frame,
                        durationMilliseconds: milliseconds(since: startedAt)
                    ))
                    if frameInterval > 0 {
                        Thread.sleep(forTimeInterval: frameInterval)
                    }
                } catch RFBNetworkClientError.timedOut {
                    firstTimeoutMilliseconds = milliseconds(from: idleTimeout)
                    break
                } catch {
                    failureLabel = safeFailureLabel(for: error)
                    break
                }
            }
            elapsedMilliseconds = milliseconds(since: streamStartedAt)
            pump.stopContinuousUpdatesIfNeeded(timeout: timeout)
            client.disconnect()
        } catch {
            pump.stopContinuousUpdatesIfNeeded(timeout: timeout)
            client.disconnect()
            failureLabel = safeFailureLabel(for: error)
        }

        return StreamShapeProbeReport(
            requestedSamples: maxSamples,
            firstFrameMilliseconds: firstFrameMilliseconds,
            samples: samples,
            elapsedMilliseconds: elapsedMilliseconds,
            firstTimeoutMilliseconds: firstTimeoutMilliseconds,
            failureLabel: failureLabel
        )
    }

    private static func streamShapeSample(
        from frame: RFBFramePumpFrame,
        durationMilliseconds: Int
    ) -> BenchmarkStreamShapeSample {
        let framebufferArea = max(frame.framebuffer.width * frame.framebuffer.height, 1)
        let dirtyArea = frame.dirtyRectangles.reduce(0) { total, rect in
            total + max(rect.width, 0) * max(rect.height, 0)
        }

        return BenchmarkStreamShapeSample(
            kind: frame.changedPixelCount == 0 ? .emptyUpdate : .contentUpdate,
            durationMilliseconds: durationMilliseconds,
            dirtyRectangleCount: frame.dirtyRectangles.count,
            dirtyAreaPermille: permille(dirtyArea, of: framebufferArea),
            changedPixelsPermille: permille(frame.changedPixelCount, of: framebufferArea)
        )
    }

    private static func permille(_ value: Int, of total: Int) -> Int {
        guard total > 0 else {
            return 0
        }
        let rounded = Int((Double(value) / Double(total) * 1_000).rounded())
        return value > 0 ? max(rounded, 1) : 0
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
    var fullRefreshSamples = 1
    var continuousUpdateSamples = 1
    var streamShapeSamples = 12
    var streamShapeFrameInterval: TimeInterval = 1.0 / 30.0
    var timeout: TimeInterval = 5
    var idleTimeout: TimeInterval = 0.75
    var askPassword = false
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
            case "--ask-password":
                options.askPassword = true
                index = arguments.index(after: index)
            case "--attempts":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let attempts = Int(value), attempts > 0 else {
                    throw UsageError("attempts must be a positive integer.")
                }
                options.attempts = attempts
                index = arguments.index(index, offsetBy: 2)
            case "--full-refresh-samples":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let samples = Int(value), samples >= 0 else {
                    throw UsageError("full-refresh-samples must be a non-negative integer.")
                }
                options.fullRefreshSamples = samples
                index = arguments.index(index, offsetBy: 2)
            case "--continuous-update-samples":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let samples = Int(value), samples > 0 else {
                    throw UsageError("continuous-update-samples must be a positive integer.")
                }
                options.continuousUpdateSamples = samples
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-samples":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let samples = Int(value), samples >= 0 else {
                    throw UsageError("stream-shape-samples must be a non-negative integer.")
                }
                options.streamShapeSamples = samples
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-frame-interval":
                let value = try nextValue(after: index, in: arguments, option: argument)
                options.streamShapeFrameInterval = try nonNegativeTimeInterval(value, option: argument)
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

    private static func nonNegativeTimeInterval(_ value: String, option: String) throws -> TimeInterval {
        guard let interval = TimeInterval(value), interval >= 0 else {
            throw UsageError("\(option) must be a non-negative number of seconds.")
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

    static func fromEnvironment(passwordOverride: String? = nil) -> LiveTargetConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let host = environment["NARU_LIVE_MAC_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !host.isEmpty,
            let password = passwordOverride ?? environment["NARU_LIVE_MAC_PASSWORD"],
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

private func readPasswordFromTerminal() throws -> String {
    fputs("VNC password: ", stderr)
    fflush(stderr)

    var original = termios()
    let canDisableEcho = isatty(STDIN_FILENO) == 1 && tcgetattr(STDIN_FILENO, &original) == 0
    if canDisableEcho {
        var hidden = original
        hidden.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &hidden)
    }
    defer {
        if canDisableEcho {
            tcsetattr(STDIN_FILENO, TCSANOW, &original)
        }
        fputs("\n", stderr)
    }

    guard let password = readLine(), !password.isEmpty else {
        throw UsageError("password prompt could not read a non-empty password.")
    }
    return password
}

private enum BenchmarkProfile: CaseIterable {
    case localLowLatency
    case tightFirst
    case zrleFirst
    case zrleCompressionZero
    case adaptiveGoodZRLE
    case adaptivePoorZRLE
    case adaptiveGoodFull
    case adaptivePoorFull

    var label: String {
        switch self {
        case .localLowLatency:
            "local-low-latency"
        case .tightFirst:
            "tight-first"
        case .zrleFirst:
            "zrle-first"
        case .zrleCompressionZero:
            "zrle-compression-0"
        case .adaptiveGoodZRLE:
            "adaptive-good-zrle"
        case .adaptivePoorZRLE:
            "adaptive-poor-zrle"
        case .adaptiveGoodFull:
            "adaptive-good-full"
        case .adaptivePoorFull:
            "adaptive-poor-full"
        }
    }

    var preference: RFBEncodingPreference {
        switch self {
        case .localLowLatency:
            return .localLowLatency
        case .tightFirst:
            return RFBEncodingPreference(
                tight: true,
                tightQualityLevel: 8,
                compressionLevel: 1
            )
        case .zrleFirst:
            return .increment2
        case .zrleCompressionZero:
            return RFBEncodingPreference(zrle: true, compressionLevel: 0)
        case .adaptiveGoodZRLE:
            return .adaptive(supported: .increment2, connectionQuality: .good)
        case .adaptivePoorZRLE:
            return .adaptive(supported: .increment2, connectionQuality: .poor)
        case .adaptiveGoodFull:
            return .adaptive(
                supported: .full,
                requestedPseudoEncodings: .withServerCursorAndPacingExtensions,
                connectionQuality: .good
            )
        case .adaptivePoorFull:
            return .adaptive(
                supported: .full,
                requestedPseudoEncodings: .withServerCursorAndPacingExtensions,
                connectionQuality: .poor
            )
        }
    }
}

private struct BenchmarkReport: Codable, Equatable {
    let schemaVersion: Int
    let target: String
    let attemptsPerProfile: Int
    let fullRefreshSamplesPerAttempt: Int
    let continuousUpdateSamples: Int
    let streamShapeSamples: Int
    let streamShapeFrameIntervalSeconds: TimeInterval
    let timeoutSeconds: TimeInterval
    let idleTimeoutSeconds: TimeInterval
    let safety: [String]
    let profiles: [ProfileReport]
    let idleProbe: IdleProbeReport
    let streamShapeProbe: StreamShapeProbeReport
    let continuousUpdatesProbe: ContinuousUpdatesProbeReport

    init(
        attemptsPerProfile: Int,
        fullRefreshSamplesPerAttempt: Int,
        continuousUpdateSamples: Int,
        timeoutSeconds: TimeInterval,
        idleTimeoutSeconds: TimeInterval,
        streamShapeSamples: Int,
        streamShapeFrameInterval: TimeInterval,
        profiles: [ProfileReport],
        idleProbe: IdleProbeReport,
        streamShapeProbe: StreamShapeProbeReport,
        continuousUpdatesProbe: ContinuousUpdatesProbeReport
    ) {
        self.schemaVersion = 6
        self.target = "configured-redacted"
        self.attemptsPerProfile = attemptsPerProfile
        self.fullRefreshSamplesPerAttempt = fullRefreshSamplesPerAttempt
        self.continuousUpdateSamples = continuousUpdateSamples
        self.streamShapeSamples = streamShapeSamples
        self.streamShapeFrameIntervalSeconds = streamShapeFrameInterval
        self.timeoutSeconds = timeoutSeconds
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.safety = [
            "host, password, server name, framebuffer dimensions, pixel payloads, byte counts, cursor pixels, and raw error descriptions are not emitted",
            "stream-shape metrics emit aggregate counts and permille ratios only",
            "reports are written to stdout only"
        ]
        self.profiles = profiles
        self.idleProbe = idleProbe
        self.streamShapeProbe = streamShapeProbe
        self.continuousUpdatesProbe = continuousUpdatesProbe
    }
}

private struct ProfileReport: Codable, Equatable {
    let label: String
    let attempted: Int
    let succeeded: Int
    let failed: Int
    let fullRefreshSamplesPerAttempt: Int
    let fullRefreshSamplesSucceeded: Int
    let firstFrameLatency: BenchmarkLatencySummary?
    let averageFirstFrameMilliseconds: Int?
    let minFirstFrameMilliseconds: Int?
    let p50FirstFrameMilliseconds: Int?
    let p95FirstFrameMilliseconds: Int?
    let maxFirstFrameMilliseconds: Int?
    let fullRefreshLatency: BenchmarkLatencySummary?
    let averageFullRefreshMilliseconds: Int?
    let minFullRefreshMilliseconds: Int?
    let p50FullRefreshMilliseconds: Int?
    let p95FullRefreshMilliseconds: Int?
    let maxFullRefreshMilliseconds: Int?
    let failureLabels: [String: Int]

    init(
        label: String,
        attempted: Int,
        fullRefreshSamplesPerAttempt: Int,
        firstFrameMilliseconds: [Int],
        fullRefreshMilliseconds: [Int],
        failureLabels: [String: Int]
    ) {
        self.label = label
        self.attempted = attempted
        self.succeeded = firstFrameMilliseconds.count
        self.failed = attempted - firstFrameMilliseconds.count
        self.fullRefreshSamplesPerAttempt = fullRefreshSamplesPerAttempt
        self.fullRefreshSamplesSucceeded = fullRefreshMilliseconds.count
        let firstFrameLatency = BenchmarkLatencySummary(firstFrameMilliseconds)
        self.firstFrameLatency = firstFrameLatency
        self.averageFirstFrameMilliseconds = firstFrameLatency?.averageMilliseconds
        self.minFirstFrameMilliseconds = firstFrameLatency?.minMilliseconds
        self.p50FirstFrameMilliseconds = firstFrameLatency?.p50Milliseconds
        self.p95FirstFrameMilliseconds = firstFrameLatency?.p95Milliseconds
        self.maxFirstFrameMilliseconds = firstFrameLatency?.maxMilliseconds
        let fullRefreshLatency = BenchmarkLatencySummary(fullRefreshMilliseconds)
        self.fullRefreshLatency = fullRefreshLatency
        self.averageFullRefreshMilliseconds = fullRefreshLatency?.averageMilliseconds
        self.minFullRefreshMilliseconds = fullRefreshLatency?.minMilliseconds
        self.p50FullRefreshMilliseconds = fullRefreshLatency?.p50Milliseconds
        self.p95FullRefreshMilliseconds = fullRefreshLatency?.p95Milliseconds
        self.maxFullRefreshMilliseconds = fullRefreshLatency?.maxMilliseconds
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

private struct StreamShapeProbeReport: Codable, Equatable {
    let firstFrameMilliseconds: Int?
    let summary: BenchmarkStreamShapeSummary

    init(
        requestedSamples: Int,
        firstFrameMilliseconds: Int?,
        samples: [BenchmarkStreamShapeSample],
        elapsedMilliseconds: Int?,
        firstTimeoutMilliseconds: Int?,
        failureLabel: String?
    ) {
        self.firstFrameMilliseconds = firstFrameMilliseconds
        self.summary = BenchmarkStreamShapeSummary(
            requestedSamples: requestedSamples,
            samples: samples,
            elapsedMilliseconds: elapsedMilliseconds,
            firstTimeoutMilliseconds: firstTimeoutMilliseconds,
            failureLabel: failureLabel
        )
    }
}

private struct ContinuousUpdatesProbeReport: Codable, Equatable {
    let status: ContinuousUpdatesProbeStatus
    let requestedSamples: Int
    let receivedSamples: Int
    let emptyUpdateSamples: Int
    let contentUpdateSamples: Int
    let timedOutSamples: Int
    let durationLatency: BenchmarkLatencySummary?
    let averageDurationMilliseconds: Int?
    let minDurationMilliseconds: Int?
    let p50DurationMilliseconds: Int?
    let p95DurationMilliseconds: Int?
    let maxDurationMilliseconds: Int?
    let firstTimeoutMilliseconds: Int?
    let failureLabel: String?

    init(
        requestedSamples: Int,
        samples: [ContinuousUpdateSample],
        timeoutMilliseconds: Int?,
        failureLabel: String?
    ) {
        let emptyUpdateSamples = samples.filter { $0.kind == .emptyUpdate }.count
        let contentUpdateSamples = samples.filter { $0.kind == .contentUpdate }.count
        let durations = samples.map(\.durationMilliseconds)

        self.status = Self.status(
            emptyUpdateSamples: emptyUpdateSamples,
            contentUpdateSamples: contentUpdateSamples,
            timeoutMilliseconds: timeoutMilliseconds,
            failureLabel: failureLabel
        )
        self.requestedSamples = requestedSamples
        self.receivedSamples = samples.count
        self.emptyUpdateSamples = emptyUpdateSamples
        self.contentUpdateSamples = contentUpdateSamples
        self.timedOutSamples = timeoutMilliseconds == nil ? 0 : 1
        let durationLatency = BenchmarkLatencySummary(durations)
        self.durationLatency = durationLatency
        self.averageDurationMilliseconds = durationLatency?.averageMilliseconds
        self.minDurationMilliseconds = durationLatency?.minMilliseconds
        self.p50DurationMilliseconds = durationLatency?.p50Milliseconds
        self.p95DurationMilliseconds = durationLatency?.p95Milliseconds
        self.maxDurationMilliseconds = durationLatency?.maxMilliseconds
        self.firstTimeoutMilliseconds = timeoutMilliseconds
        self.failureLabel = failureLabel
    }

    private static func status(
        emptyUpdateSamples: Int,
        contentUpdateSamples: Int,
        timeoutMilliseconds: Int?,
        failureLabel: String?
    ) -> ContinuousUpdatesProbeStatus {
        if failureLabel != nil {
            return .failed
        }
        if emptyUpdateSamples > 0, contentUpdateSamples > 0 {
            return .mixedUpdates
        }
        if contentUpdateSamples > 0 {
            return .contentUpdate
        }
        if emptyUpdateSamples > 0 {
            return .emptyUpdate
        }
        if timeoutMilliseconds != nil {
            return .noUpdateBeforeTimeout
        }
        return .noUpdateBeforeTimeout
    }
}

private enum ContinuousUpdatesProbeStatus: String, Codable {
    case noUpdateBeforeTimeout = "no-update-before-timeout"
    case emptyUpdate = "empty-update"
    case contentUpdate = "content-update"
    case mixedUpdates = "mixed-updates"
    case failed
}

private struct ContinuousUpdateSample: Equatable {
    let kind: ContinuousUpdateSampleKind
    let durationMilliseconds: Int
}

private enum ContinuousUpdateSampleKind: Equatable {
    case emptyUpdate
    case contentUpdate
}

private func renderText(_ report: BenchmarkReport) {
    print("\(toolName)")
    print("target: \(report.target)")
    print("safety: host/password/server name/framebuffer dimensions/pixels/byte counts/cursor pixels/raw errors are not emitted")
    print("attempts per profile: \(report.attemptsPerProfile)")
    print("full-refresh samples per successful attempt: \(report.fullRefreshSamplesPerAttempt)")
    print("stream-shape samples: \(report.streamShapeSamples)")
    print("stream-shape frame interval seconds: \(formatSeconds(report.streamShapeFrameIntervalSeconds))")
    print("continuous-update samples: \(report.continuousUpdateSamples)")
    print("timeout seconds: \(formatSeconds(report.timeoutSeconds))")
    print("idle timeout seconds: \(formatSeconds(report.idleTimeoutSeconds))")
    print("")
    print("profiles:")
    for profile in report.profiles {
        print("- \(profile.label): \(profile.succeeded)/\(profile.attempted) succeeded")
        if let latency = profile.firstFrameLatency {
            print(
                "  first-frame ms avg/p50/p95/min/max: "
                    + "\(latency.averageMilliseconds)/\(latency.p50Milliseconds)/"
                    + "\(latency.p95Milliseconds)/\(latency.minMilliseconds)/"
                    + "\(latency.maxMilliseconds)"
            )
        } else {
            print("  first-frame ms avg/p50/p95/min/max: n/a")
        }
        if let latency = profile.fullRefreshLatency {
            print(
                "  full-refresh ms avg/p50/p95/min/max: "
                    + "\(latency.averageMilliseconds)/\(latency.p50Milliseconds)/"
                    + "\(latency.p95Milliseconds)/\(latency.minMilliseconds)/"
                    + "\(latency.maxMilliseconds) "
                    + "(\(profile.fullRefreshSamplesSucceeded) samples)"
            )
        } else {
            print("  full-refresh ms avg/p50/p95/min/max: n/a (\(profile.fullRefreshSamplesSucceeded) samples)")
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
    print("stream-shape probe:")
    renderStreamShapeProbe(report.streamShapeProbe)
    print("")
    print("continuous updates probe:")
    let probe = report.continuousUpdatesProbe
    if let failure = probe.failureLabel {
        print("- status: \(probe.status.rawValue), failure: \(failure)")
    } else if let latency = probe.durationLatency {
        print("- status: \(probe.status.rawValue), received: \(probe.receivedSamples)/\(probe.requestedSamples)")
        print(
            "  update ms avg/p50/p95/min/max: "
                + "\(latency.averageMilliseconds)/\(latency.p50Milliseconds)/"
                + "\(latency.p95Milliseconds)/\(latency.minMilliseconds)/"
                + "\(latency.maxMilliseconds)"
        )
        print("  empty/content/timeouts: \(probe.emptyUpdateSamples)/\(probe.contentUpdateSamples)/\(probe.timedOutSamples)")
        if let timeout = probe.firstTimeoutMilliseconds {
            print("  first timeout ms: \(timeout)")
        }
    } else if let timeout = probe.firstTimeoutMilliseconds {
        print("- status: \(probe.status.rawValue), timeout ms: \(timeout)")
    } else {
        print("- status: \(probe.status.rawValue)")
    }
}

private func renderStreamShapeProbe(_ probe: StreamShapeProbeReport) {
    let summary = probe.summary
    if let failure = summary.failureLabel {
        print("- status: \(summary.status.rawValue), failure: \(failure)")
        return
    }

    print("- status: \(summary.status.rawValue), received: \(summary.receivedSamples)/\(summary.requestedSamples)")
    if let firstFrameMilliseconds = probe.firstFrameMilliseconds {
        print("  first-frame ms: \(firstFrameMilliseconds)")
    }
    if let fps = summary.deliveredFramesPerSecond {
        print("  delivered incremental fps: \(formatFramesPerSecond(fps))")
    }
    if let latency = summary.updateLatency {
        print(
            "  update ms avg/p50/p95/min/max: "
                + "\(latency.averageMilliseconds)/\(latency.p50Milliseconds)/"
                + "\(latency.p95Milliseconds)/\(latency.minMilliseconds)/"
                + "\(latency.maxMilliseconds)"
        )
    }
    print("  empty/content/timeouts: \(summary.emptyUpdateSamples)/\(summary.contentUpdateSamples)/\(summary.timedOutSamples)")
    if let dirtyRectangles = summary.dirtyRectangleCount {
        print(
            "  dirty rect count avg/p50/p95/min/max: "
                + "\(dirtyRectangles.averageMilliseconds)/\(dirtyRectangles.p50Milliseconds)/"
                + "\(dirtyRectangles.p95Milliseconds)/\(dirtyRectangles.minMilliseconds)/"
                + "\(dirtyRectangles.maxMilliseconds)"
        )
    }
    if let dirtyArea = summary.dirtyAreaPermille {
        print(
            "  dirty area permille avg/p50/p95/min/max: "
                + "\(dirtyArea.averageMilliseconds)/\(dirtyArea.p50Milliseconds)/"
                + "\(dirtyArea.p95Milliseconds)/\(dirtyArea.minMilliseconds)/"
                + "\(dirtyArea.maxMilliseconds)"
        )
    }
    if let changedPixels = summary.changedPixelsPermille {
        print(
            "  changed pixel permille avg/p50/p95/min/max: "
                + "\(changedPixels.averageMilliseconds)/\(changedPixels.p50Milliseconds)/"
                + "\(changedPixels.p95Milliseconds)/\(changedPixels.minMilliseconds)/"
                + "\(changedPixels.maxMilliseconds)"
        )
    }
    if let timeout = summary.firstTimeoutMilliseconds {
        print("  first timeout ms: \(timeout)")
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

private func formatFramesPerSecond(_ value: Double) -> String {
    String(format: "%.2f", value)
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
      swift run VNCLiveBenchmark [--attempts N] [--full-refresh-samples N] [--stream-shape-samples N] [--stream-shape-frame-interval SECONDS] [--continuous-update-samples N] [--ask-password] [--timeout SECONDS] [--idle-timeout SECONDS] [--json]

    Options:
      --full-refresh-samples N  Extra non-incremental frame requests after each successful first frame. Defaults to 1; use 0 to disable.
      --stream-shape-samples N  Incremental request/response samples after a full frame using local-low-latency encoding. Defaults to 12; use 0 to disable.
      --stream-shape-frame-interval SECONDS
                                Delay between stream-shape incremental requests. Defaults to 0.033, matching the app's 30 fps cap.
      --continuous-update-samples N
                                Maximum pushed updates to sample after enabling continuous updates. Defaults to 1.
      --ask-password            Prompt for the VNC password without echoing it instead of reading NARU_LIVE_MAC_PASSWORD.

    Required environment:
      NARU_LIVE_MAC_HOST       redacted from output
      NARU_LIVE_MAC_PASSWORD   redacted from output; optional when --ask-password is used
      NARU_LIVE_MAC_PORT       optional, defaults to 5900

    The report intentionally omits target identity, framebuffer dimensions,
    pixel payloads, byte counts, cursor pixels, and raw error descriptions.
    Stream-shape metrics emit aggregate counts and permille ratios only.
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
    case RFBRawFramebufferDecoderError.malformedTight:
        return "malformed-tight"
    case RFBClientMessageEncodingError.unsupportedFenceFlags:
        return "client-message-encoding"
    case RFBClientMessageEncodingError.fencePayloadTooLarge:
        return "client-message-encoding"
    default:
        return "unexpected-error"
    }
}
