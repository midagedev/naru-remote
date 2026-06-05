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
        let firstFrameProfiles = options.firstFrameProfiles.profiles(
            streamShapeProfiles: options.streamShapeProfiles
        )
        let profiles = firstFrameProfiles.map { profile in
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
        let streamShapePacingPolicy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: options.streamShapeFrameInterval,
            idleFrameInterval: options.streamShapeIdleFrameInterval,
            emptyBackoffMode: options.streamShapeEmptyBackoffMode,
            powerMode: options.streamShapePowerMode,
            clientPressureMode: options.streamShapeClientPressureMode,
            viewportInteractionMode: options.streamShapeViewportInteractionMode
        )
        let primaryStreamShapeProfile = options.streamShapeProfiles.profiles.first ?? .localLowLatency
        let primaryStreamShapeTransportMode = options.streamShapeTransportModes.modes.first ?? .requestResponse
        let streamShapeProbe = measureStreamShapeProbe(
            profile: primaryStreamShapeProfile,
            transportMode: primaryStreamShapeTransportMode,
            configuration: configuration,
            timeout: options.timeout,
            idleTimeout: options.idleTimeout,
            maxSamples: options.streamShapeSamples,
            durationLimit: options.streamShapeDuration,
            pacingPolicy: streamShapePacingPolicy
        )
        let streamShapeProfileProbes = options.streamShapeProfiles.profiles.flatMap { profile in
            options.streamShapeTransportModes.modes.map { transportMode in
                if profile == primaryStreamShapeProfile,
                   transportMode == primaryStreamShapeTransportMode {
                    return BenchmarkStreamShapeProfileReport(
                        label: profile.label,
                        transportMode: transportMode,
                        firstFrameMilliseconds: streamShapeProbe.firstFrameMilliseconds,
                        summary: streamShapeProbe.summary
                    )
                }
                return measureStreamShapeProfileProbe(
                    profile: profile,
                    transportMode: transportMode,
                    configuration: configuration,
                    timeout: options.timeout,
                    idleTimeout: options.idleTimeout,
                    maxSamples: options.streamShapeSamples,
                    durationLimit: options.streamShapeDuration,
                    pacingPolicy: streamShapePacingPolicy
                )
            }
        }
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
            streamShapeDuration: options.streamShapeDuration,
            streamShapeFrameInterval: options.streamShapeFrameInterval,
            streamShapeIdleFrameInterval: options.streamShapeIdleFrameInterval,
            streamShapeEmptyBackoffMode: options.streamShapeEmptyBackoffMode,
            streamShapePowerMode: options.streamShapePowerMode,
            streamShapeClientPressureMode: options.streamShapeClientPressureMode,
            streamShapeViewportInteractionMode: options.streamShapeViewportInteractionMode,
            streamShapeViewportInteractionPauseSeconds: options.streamShapeViewportInteractionPauseSeconds,
            firstFrameProfiles: options.firstFrameProfiles,
            streamShapeProfiles: options.streamShapeProfiles,
            streamShapeTransportModes: options.streamShapeTransportModes,
            profiles: profiles,
            idleProbe: idleProbe,
            streamShapeProbe: streamShapeProbe,
            streamShapeProfileProbes: streamShapeProfileProbes,
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
        defer {
            if continuousUpdatesEnabled {
                try? client.enableContinuousUpdates(false, region: nil, timeout: timeout)
            }
            client.disconnect()
        }

        do {
            _ = try client.connectSession(
                host: configuration.host,
                port: configuration.port,
                credential: .vncPassword(configuration.password),
                timeout: timeout
            )
        } catch {
            return ContinuousUpdatesProbeReport(
                requestedSamples: maxSamples,
                samples: samples,
                timeoutMilliseconds: nil,
                failureLabel: safeFailureLabel(for: error, phase: .continuousProbeConnect)
            )
        }

        do {
            _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)
        } catch {
            return ContinuousUpdatesProbeReport(
                requestedSamples: maxSamples,
                samples: samples,
                timeoutMilliseconds: nil,
                failureLabel: safeFailureLabel(for: error, phase: .continuousProbeFirstFrame)
            )
        }

        do {
            try client.enableContinuousUpdates(true, region: nil, timeout: timeout)
            continuousUpdatesEnabled = true
        } catch {
            return ContinuousUpdatesProbeReport(
                requestedSamples: maxSamples,
                samples: samples,
                timeoutMilliseconds: nil,
                failureLabel: safeFailureLabel(for: error, phase: .continuousProbeEnable)
            )
        }

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
            } catch {
                return ContinuousUpdatesProbeReport(
                    requestedSamples: maxSamples,
                    samples: samples,
                    timeoutMilliseconds: nil,
                    failureLabel: safeFailureLabel(for: error, phase: .continuousProbeReceive)
                )
            }
        }

        return ContinuousUpdatesProbeReport(
            requestedSamples: maxSamples,
            samples: samples,
            timeoutMilliseconds: timeoutMilliseconds,
            failureLabel: nil
        )
    }

    private static func measureStreamShapeProbe(
        profile: BenchmarkProfile,
        transportMode: BenchmarkStreamShapeTransportMode,
        configuration: LiveTargetConfiguration,
        timeout: TimeInterval,
        idleTimeout: TimeInterval,
        maxSamples: Int,
        durationLimit: TimeInterval?,
        pacingPolicy: BenchmarkStreamShapePacingPolicy
    ) -> StreamShapeProbeReport {
        guard maxSamples > 0 || durationLimit != nil else {
            return StreamShapeProbeReport(
                transportMode: transportMode,
                requestedSamples: 0,
                firstFrameMilliseconds: nil,
                samples: [],
                elapsedMilliseconds: nil,
                firstTimeoutMilliseconds: nil,
                failureLabel: nil
            )
        }

        let client = RFBNetworkClient(
            encodingPreference: profile.preference.applying(streamShapeTransportMode: transportMode)
        )
        let pump = RFBFramePump(source: client)
        var samples: [BenchmarkStreamShapeSample] = []
        var firstFrameMilliseconds: Int?
        var firstTimeoutMilliseconds: Int?
        var elapsedMilliseconds: Int?
        var failureLabel: String?
        var emptyUpdateStreak = 0
        var clientPressureState = BenchmarkStreamShapeClientPressureState()
        var adaptiveClientPressurePacingSamples = 0
        var viewportInteractionPacingSamples = 0
        defer {
            pump.stopContinuousUpdatesIfNeeded(timeout: timeout)
            client.disconnect()
        }

        do {
            _ = try client.connectSession(
                host: configuration.host,
                port: configuration.port,
                credential: .vncPassword(configuration.password),
                timeout: timeout
            )
        } catch {
            failureLabel = safeFailureLabel(for: error, phase: .streamConnect)
            return StreamShapeProbeReport(
                transportMode: transportMode,
                requestedSamples: streamShapeRequestedSamples(
                    maxSamples: maxSamples,
                    durationLimit: durationLimit,
                    receivedSamples: samples.count
                ),
                firstFrameMilliseconds: firstFrameMilliseconds,
                samples: samples,
                elapsedMilliseconds: elapsedMilliseconds,
                firstTimeoutMilliseconds: firstTimeoutMilliseconds,
                failureLabel: failureLabel
            )
        }

        do {
            let firstFrameStartedAt = Date()
            _ = try pump.nextFrame(
                requestTimeout: timeout,
                updateMode: transportMode.framePumpUpdateMode
            )
            firstFrameMilliseconds = milliseconds(since: firstFrameStartedAt)
        } catch {
            failureLabel = safeFailureLabel(for: error, phase: .streamFirstFrame)
            return StreamShapeProbeReport(
                transportMode: transportMode,
                requestedSamples: streamShapeRequestedSamples(
                    maxSamples: maxSamples,
                    durationLimit: durationLimit,
                    receivedSamples: samples.count
                ),
                firstFrameMilliseconds: firstFrameMilliseconds,
                samples: samples,
                elapsedMilliseconds: elapsedMilliseconds,
                firstTimeoutMilliseconds: firstTimeoutMilliseconds,
                failureLabel: failureLabel
            )
        }

        let streamStartedAt = Date()
        while shouldRequestAnotherStreamShapeSample(
            receivedSamples: samples.count,
            maxSamples: maxSamples,
            durationLimit: durationLimit,
            streamStartedAt: streamStartedAt
        ) {
            let startedAt = Date()
            let requestTimeout = streamShapeRequestTimeout(
                idleTimeout: idleTimeout,
                durationLimit: durationLimit,
                streamStartedAt: streamStartedAt
            )
            guard requestTimeout > 0 else {
                break
            }
            do {
                guard let frame = try pump.nextFrame(
                    requestTimeout: requestTimeout,
                    updateMode: transportMode.framePumpUpdateMode
                ) else {
                    break
                }
                let sample = streamShapeSample(
                    from: frame,
                    durationMilliseconds: milliseconds(since: startedAt)
                )
                samples.append(sample)
                clientPressureState.record(
                    sample: sample,
                    mode: pacingPolicy.clientPressureMode
                )
                let usesAdaptiveClientPressure = clientPressureState.usesAdaptivePowerSaverPacing
                if usesAdaptiveClientPressure {
                    adaptiveClientPressurePacingSamples += 1
                }
                let isEmptyUpdate = frame.isIncremental && frame.changedPixelCount == 0
                emptyUpdateStreak = isEmptyUpdate ? emptyUpdateStreak + 1 : 0
                let pacingDecision = pacingPolicy.decision(
                    isEmptyUpdate: isEmptyUpdate,
                    emptyUpdateStreak: emptyUpdateStreak,
                    usesAdaptiveClientPressure: usesAdaptiveClientPressure
                )
                if pacingDecision.usesViewportInteractionPacing {
                    viewportInteractionPacingSamples += 1
                }
                let cappedPacingDelay = streamShapeCappedDelay(
                    pacingDecision.delay,
                    durationLimit: durationLimit,
                    streamStartedAt: streamStartedAt
                )
                if cappedPacingDelay > 0 {
                    Thread.sleep(forTimeInterval: cappedPacingDelay)
                }
            } catch RFBNetworkClientError.timedOut {
                if requestTimeout >= idleTimeout {
                    firstTimeoutMilliseconds = milliseconds(from: requestTimeout)
                }
                break
            } catch RFBNetworkClientError.readTimedOut {
                if requestTimeout < idleTimeout {
                    break
                }
                failureLabel = safeFailureLabel(
                    for: RFBNetworkClientError.readTimedOut,
                    phase: transportMode.streamFailurePhase
                )
                break
            } catch {
                failureLabel = safeFailureLabel(for: error, phase: transportMode.streamFailurePhase)
                break
            }
        }
        elapsedMilliseconds = milliseconds(since: streamStartedAt)

        return StreamShapeProbeReport(
            transportMode: transportMode,
            requestedSamples: streamShapeRequestedSamples(
                maxSamples: maxSamples,
                durationLimit: durationLimit,
                receivedSamples: samples.count
            ),
            firstFrameMilliseconds: firstFrameMilliseconds,
            samples: samples,
            elapsedMilliseconds: elapsedMilliseconds,
            firstTimeoutMilliseconds: firstTimeoutMilliseconds,
            failureLabel: failureLabel,
            adaptiveClientPressurePacingSamples: adaptiveClientPressurePacingSamples,
            viewportInteractionPacingSamples: viewportInteractionPacingSamples,
            viewportInteractionPausedRequests: 0,
            viewportInteractionPausePolls: 0,
            viewportInteractionPausedMilliseconds: 0
        )
    }

    private static func measureStreamShapeProfileProbe(
        profile: BenchmarkProfile,
        transportMode: BenchmarkStreamShapeTransportMode,
        configuration: LiveTargetConfiguration,
        timeout: TimeInterval,
        idleTimeout: TimeInterval,
        maxSamples: Int,
        durationLimit: TimeInterval?,
        pacingPolicy: BenchmarkStreamShapePacingPolicy
    ) -> BenchmarkStreamShapeProfileReport {
        let probe = measureStreamShapeProbe(
            profile: profile,
            transportMode: transportMode,
            configuration: configuration,
            timeout: timeout,
            idleTimeout: idleTimeout,
            maxSamples: maxSamples,
            durationLimit: durationLimit,
            pacingPolicy: pacingPolicy
        )
        return BenchmarkStreamShapeProfileReport(
            label: profile.label,
            transportMode: transportMode,
            firstFrameMilliseconds: probe.firstFrameMilliseconds,
            summary: probe.summary
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
        let kind: BenchmarkStreamUpdateKind = frame.changedPixelCount == 0 ? .emptyUpdate : .contentUpdate
        let uploadPlan = FramebufferUploadPlan.plan(
            framebufferWidth: frame.framebuffer.width,
            framebufferHeight: frame.framebuffer.height,
            dirtyRectangles: frame.isIncremental ? frame.dirtyRectangles : nil,
            requiresTextureRecreation: false,
            changedPixelCount: frame.isIncremental ? frame.changedPixelCount : nil,
            shouldUpload: kind == .contentUpdate
        )

        return BenchmarkStreamShapeSample(
            kind: kind,
            durationMilliseconds: durationMilliseconds,
            dirtyRectangleCount: frame.dirtyRectangles.count,
            dirtyAreaPermille: permille(dirtyArea, of: framebufferArea),
            changedPixelsPermille: permille(frame.changedPixelCount, of: framebufferArea),
            rendererUploadStrategy: uploadPlan.strategy,
            rendererUploadRegionCount: uploadPlan.uploadRegionCount,
            receiveTotalMilliseconds: frame.timing?.totalMilliseconds,
            networkReadMilliseconds: frame.timing?.networkReadMilliseconds,
            clientProcessingMilliseconds: frame.timing?.clientProcessingMilliseconds,
            actualEncodingMix: frame.encodingMix
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

    private static func shouldRequestAnotherStreamShapeSample(
        receivedSamples: Int,
        maxSamples: Int,
        durationLimit: TimeInterval?,
        streamStartedAt: Date
    ) -> Bool {
        if maxSamples > 0, receivedSamples >= maxSamples {
            return false
        }
        guard let durationLimit else {
            return maxSamples > 0
        }
        return Date().timeIntervalSince(streamStartedAt) < durationLimit
    }

    private static func streamShapeRequestTimeout(
        idleTimeout: TimeInterval,
        durationLimit: TimeInterval?,
        streamStartedAt: Date
    ) -> TimeInterval {
        guard let durationLimit else {
            return idleTimeout
        }
        let remaining = durationLimit - Date().timeIntervalSince(streamStartedAt)
        return min(idleTimeout, max(remaining, 0))
    }

    private static func streamShapeCappedDelay(
        _ delay: TimeInterval,
        durationLimit: TimeInterval?,
        streamStartedAt: Date
    ) -> TimeInterval {
        guard delay > 0 else {
            return 0
        }
        guard let durationLimit else {
            return delay
        }
        let remaining = durationLimit - Date().timeIntervalSince(streamStartedAt)
        return min(delay, max(remaining, 0))
    }

    private static func streamShapeRequestedSamples(
        maxSamples: Int,
        durationLimit: TimeInterval?,
        receivedSamples: Int
    ) -> Int {
        if maxSamples > 0 {
            return maxSamples
        }
        if durationLimit != nil {
            return max(receivedSamples, 1)
        }
        return 0
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
    var streamShapeDuration: TimeInterval?
    var streamShapeFrameInterval: TimeInterval = BenchmarkStreamShapePacingPolicy
        .appBalancedContentFrameInterval
    var streamShapeIdleFrameInterval: TimeInterval = 0.05
    var streamShapeEmptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode = .app
    var streamShapePowerMode: BenchmarkStreamShapePowerMode = .normal
    var streamShapeClientPressureMode: BenchmarkStreamShapeClientPressureMode = .off
    var streamShapeViewportInteractionMode: BenchmarkStreamShapeViewportInteractionMode = .off
    var streamShapeViewportInteractionPauseSeconds: TimeInterval = BenchmarkStreamShapePacingPolicy
        .appViewportInteractionSyntheticPauseSeconds
    var firstFrameProfiles: BenchmarkFirstFrameProfileSelection = .all
    var streamShapeProfiles: StreamShapeProfileSelection = .localLowLatency
    var streamShapeTransportModes: StreamShapeTransportModeSelection = .requestResponse
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
            case "--stream-shape-duration-seconds":
                let value = try nextValue(after: index, in: arguments, option: argument)
                options.streamShapeDuration = try positiveTimeInterval(value, option: argument)
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-frame-interval":
                let value = try nextValue(after: index, in: arguments, option: argument)
                options.streamShapeFrameInterval = try nonNegativeTimeInterval(value, option: argument)
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-idle-frame-interval":
                let value = try nextValue(after: index, in: arguments, option: argument)
                options.streamShapeIdleFrameInterval = try nonNegativeTimeInterval(value, option: argument)
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-empty-backoff":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let mode = BenchmarkStreamShapeEmptyBackoffMode(rawValue: value) else {
                    throw UsageError("stream-shape-empty-backoff must be app or none.")
                }
                options.streamShapeEmptyBackoffMode = mode
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-power-mode":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let mode = BenchmarkStreamShapePowerMode(rawValue: value) else {
                    throw UsageError("stream-shape-power-mode must be normal or low-power.")
                }
                options.streamShapePowerMode = mode
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-client-pressure":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let mode = BenchmarkStreamShapeClientPressureMode(rawValue: value) else {
                    throw UsageError("stream-shape-client-pressure must be off or app.")
                }
                options.streamShapeClientPressureMode = mode
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-viewport-interaction":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let mode = BenchmarkStreamShapeViewportInteractionMode(rawValue: value) else {
                    throw UsageError("stream-shape-viewport-interaction must be off or app.")
                }
                options.streamShapeViewportInteractionMode = mode
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-viewport-interaction-pause-seconds":
                let value = try nextValue(after: index, in: arguments, option: argument)
                options.streamShapeViewportInteractionPauseSeconds = try nonNegativeTimeInterval(
                    value,
                    option: argument
                )
                index = arguments.index(index, offsetBy: 2)
            case "--first-frame-profiles":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let selection = BenchmarkFirstFrameProfileSelection(rawValue: value) else {
                    throw UsageError(
                        "first-frame-profiles must be \(BenchmarkFirstFrameProfileSelection.usageDescription)."
                    )
                }
                options.firstFrameProfiles = selection
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-profiles":
                let value = try nextValue(after: index, in: arguments, option: argument)
                do {
                    options.streamShapeProfiles = try StreamShapeProfileSelection.parse(value)
                } catch let error as BenchmarkStreamShapeProfileSelectionError {
                    throw UsageError(error.message)
                }
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-transport":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let selection = StreamShapeTransportModeSelection(rawValue: value) else {
                    throw UsageError("stream-shape-transport must be request-response, continuous-updates, or both.")
                }
                options.streamShapeTransportModes = selection
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

private struct StreamShapeProfileSelection: Equatable {
    let rawValue: String
    let profiles: [BenchmarkProfile]

    static let localLowLatency = StreamShapeProfileSelection(
        rawValue: BenchmarkProfile.localLowLatency.label,
        profiles: [.localLowLatency]
    )

    static func parse(_ rawValue: String) throws -> StreamShapeProfileSelection {
        let labels = try BenchmarkStreamShapeProfileSelection.selectedLabels(
            from: rawValue,
            allProfileLabels: BenchmarkProfile.allCases.map(\.label),
            localLowLatencyLabel: BenchmarkProfile.localLowLatency.label
        )
        let profiles = labels.compactMap(BenchmarkProfile.init(label:))
        guard profiles.count == labels.count else {
            let unmappedLabels = labels.filter { BenchmarkProfile(label: $0) == nil }
            throw UsageError("unknown stream-shape profile label(s): \(unmappedLabels.joined(separator: ", ")).")
        }
        return StreamShapeProfileSelection(
            rawValue: canonicalRawValue(for: rawValue, selectedLabels: labels),
            profiles: profiles
        )
    }

    private static func canonicalRawValue(for rawValue: String, selectedLabels: [String]) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "all" || trimmed == BenchmarkProfile.localLowLatency.label {
            return trimmed
        }
        return selectedLabels.joined(separator: ",")
    }
}

private enum StreamShapeTransportModeSelection: String, Codable, Equatable {
    case requestResponse = "request-response"
    case continuousUpdates = "continuous-updates"
    case both

    var modes: [BenchmarkStreamShapeTransportMode] {
        switch self {
        case .requestResponse:
            return [.requestResponse]
        case .continuousUpdates:
            return [.continuousUpdates]
        case .both:
            return BenchmarkStreamShapeTransportMode.allCases
        }
    }
}

private extension BenchmarkFirstFrameProfileSelection {
    func profiles(streamShapeProfiles: StreamShapeProfileSelection) -> [BenchmarkProfile] {
        let labels = selectedLabels(
            allProfileLabels: BenchmarkProfile.allCases.map(\.label),
            streamShapeProfileLabels: streamShapeProfiles.profiles.map(\.label),
            localLowLatencyLabel: BenchmarkProfile.localLowLatency.label
        )
        return labels.compactMap(BenchmarkProfile.init(label:))
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

private enum BenchmarkProfile: CaseIterable, Equatable {
    case localLowLatency
    case tightFirst
    case zrleFirst
    case zrleCompressionZero
    case zrleCompressionZeroCursor
    case zrleCompressionZeroClipboard
    case zrleCompressionZeroCursorClipboard
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
        case .zrleCompressionZeroCursor:
            "zrle-compression-0-cursor"
        case .zrleCompressionZeroClipboard:
            "zrle-compression-0-clipboard"
        case .zrleCompressionZeroCursorClipboard:
            "zrle-compression-0-cursor-clipboard"
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

    init?(label: String) {
        guard let profile = Self.allCases.first(where: { $0.label == label }) else {
            return nil
        }
        self = profile
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
        case .zrleCompressionZeroCursor:
            return RFBEncodingPreference(
                zrle: true,
                cursor: true,
                compressionLevel: 0
            )
        case .zrleCompressionZeroClipboard:
            return RFBEncodingPreference(
                zrle: true,
                extendedClipboard: true,
                compressionLevel: 0
            )
        case .zrleCompressionZeroCursorClipboard:
            return RFBEncodingPreference(
                zrle: true,
                cursor: true,
                extendedClipboard: true,
                compressionLevel: 0
            )
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

private extension BenchmarkStreamShapeTransportMode {
    var framePumpUpdateMode: RFBFramePumpUpdateMode {
        switch self {
        case .requestResponse:
            return .requestResponse
        case .continuousUpdates:
            return .continuousUpdates
        }
    }

    var streamFailurePhase: BenchmarkFailurePhase {
        switch self {
        case .requestResponse:
            return .streamIncremental
        case .continuousUpdates:
            return .streamContinuousUpdates
        }
    }
}

private extension RFBEncodingPreference {
    func applying(streamShapeTransportMode mode: BenchmarkStreamShapeTransportMode) -> RFBEncodingPreference {
        var preference = self
        switch mode {
        case .requestResponse:
            preference.fence = false
            preference.continuousUpdates = false
        case .continuousUpdates:
            preference.fence = true
            preference.continuousUpdates = true
        }
        return preference
    }
}

private struct BenchmarkReport: Codable, Equatable {
    let schemaVersion: Int
    let target: String
    let attemptsPerProfile: Int
    let fullRefreshSamplesPerAttempt: Int
    let continuousUpdateSamples: Int
    let streamShapeSamples: Int
    let streamShapeDurationSeconds: TimeInterval?
    let streamShapeFrameIntervalSeconds: TimeInterval
    let streamShapeIdleFrameIntervalSeconds: TimeInterval
    let streamShapeEmptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode
    let streamShapePowerMode: BenchmarkStreamShapePowerMode
    let streamShapeClientPressureMode: BenchmarkStreamShapeClientPressureMode
    let streamShapeViewportInteractionMode: BenchmarkStreamShapeViewportInteractionMode
    let streamShapeViewportInteractionPauseSeconds: TimeInterval
    let streamShapeViewportInteractionRequestPausePollSeconds: TimeInterval
    let streamShapeLowPowerContentFrameIntervalSeconds: TimeInterval
    let streamShapeLowPowerIdleFrameIntervalSeconds: TimeInterval
    let streamShapeViewportInteractionContentFrameIntervalSeconds: TimeInterval
    let streamShapeViewportInteractionIdleFrameIntervalSeconds: TimeInterval
    let streamShapeClientPressureLaggingThresholdMilliseconds: Int
    let streamShapeClientPressureConsecutiveContentFrameThreshold: Int
    let streamShapeClientPressureSustainedLaggingThresholdMilliseconds: Int
    let streamShapeClientPressureConsecutiveSustainedContentFrameThreshold: Int
    let streamShapeClientPressureVerySlowThresholdMilliseconds: Int
    let streamShapeClientPressureVerySlowRecoveryUpdateCount: Int
    let streamShapeClientPressureConsecutiveFullUploadFrameThreshold: Int
    let streamShapeClientPressureRecoveryUpdateCount: Int
    let streamShapeEmptyBackoffMediumStreakThreshold: Int
    let streamShapeEmptyBackoffLongStreakThreshold: Int
    let streamShapeEmptyBackoffMediumIdleFrameIntervalSeconds: TimeInterval
    let streamShapeEmptyBackoffLongIdleFrameIntervalSeconds: TimeInterval
    let firstFrameProfiles: BenchmarkFirstFrameProfileSelection
    let streamShapeProfiles: String
    let streamShapeTransportModes: StreamShapeTransportModeSelection
    let timeoutSeconds: TimeInterval
    let idleTimeoutSeconds: TimeInterval
    let safety: [String]
    let profiles: [ProfileReport]
    let idleProbe: IdleProbeReport
    let streamShapeProbe: StreamShapeProbeReport
    let streamShapeProfileProbes: [BenchmarkStreamShapeProfileReport]
    let streamShapeRecommendation: BenchmarkStreamShapeRecommendation?
    let continuousUpdatesProbe: ContinuousUpdatesProbeReport

    init(
        attemptsPerProfile: Int,
        fullRefreshSamplesPerAttempt: Int,
        continuousUpdateSamples: Int,
        timeoutSeconds: TimeInterval,
        idleTimeoutSeconds: TimeInterval,
        streamShapeSamples: Int,
        streamShapeDuration: TimeInterval?,
        streamShapeFrameInterval: TimeInterval,
        streamShapeIdleFrameInterval: TimeInterval,
        streamShapeEmptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode,
        streamShapePowerMode: BenchmarkStreamShapePowerMode,
        streamShapeClientPressureMode: BenchmarkStreamShapeClientPressureMode,
        streamShapeViewportInteractionMode: BenchmarkStreamShapeViewportInteractionMode,
        streamShapeViewportInteractionPauseSeconds _: TimeInterval,
        firstFrameProfiles: BenchmarkFirstFrameProfileSelection,
        streamShapeProfiles: StreamShapeProfileSelection,
        streamShapeTransportModes: StreamShapeTransportModeSelection,
        profiles: [ProfileReport],
        idleProbe: IdleProbeReport,
        streamShapeProbe: StreamShapeProbeReport,
        streamShapeProfileProbes: [BenchmarkStreamShapeProfileReport],
        continuousUpdatesProbe: ContinuousUpdatesProbeReport
    ) {
        self.schemaVersion = 30
        self.target = "configured-redacted"
        self.attemptsPerProfile = attemptsPerProfile
        self.fullRefreshSamplesPerAttempt = fullRefreshSamplesPerAttempt
        self.continuousUpdateSamples = continuousUpdateSamples
        self.streamShapeSamples = streamShapeSamples
        self.streamShapeDurationSeconds = streamShapeDuration
        self.streamShapeFrameIntervalSeconds = streamShapeFrameInterval
        self.streamShapeIdleFrameIntervalSeconds = streamShapeIdleFrameInterval
        self.streamShapeEmptyBackoffMode = streamShapeEmptyBackoffMode
        self.streamShapePowerMode = streamShapePowerMode
        self.streamShapeClientPressureMode = streamShapeClientPressureMode
        self.streamShapeViewportInteractionMode = streamShapeViewportInteractionMode
        self.streamShapeViewportInteractionPauseSeconds = 0
        self.streamShapeViewportInteractionRequestPausePollSeconds = 0
        self.streamShapeLowPowerContentFrameIntervalSeconds =
            BenchmarkStreamShapePacingPolicy.appLowPowerContentFrameInterval
        self.streamShapeLowPowerIdleFrameIntervalSeconds =
            BenchmarkStreamShapePacingPolicy.appLowPowerIdleFrameInterval
        self.streamShapeViewportInteractionContentFrameIntervalSeconds =
            BenchmarkStreamShapePacingPolicy.appViewportInteractionContentFrameInterval
        self.streamShapeViewportInteractionIdleFrameIntervalSeconds =
            BenchmarkStreamShapePacingPolicy.appViewportInteractionIdleFrameInterval
        self.streamShapeClientPressureLaggingThresholdMilliseconds =
            BenchmarkStreamShapePacingPolicy.appLaggingClientProcessingThresholdMilliseconds
        self.streamShapeClientPressureConsecutiveContentFrameThreshold =
            BenchmarkStreamShapePacingPolicy.appConsecutiveLaggingContentFrameThreshold
        self.streamShapeClientPressureSustainedLaggingThresholdMilliseconds =
            BenchmarkStreamShapePacingPolicy.appSustainedLaggingClientProcessingThresholdMilliseconds
        self.streamShapeClientPressureConsecutiveSustainedContentFrameThreshold =
            BenchmarkStreamShapePacingPolicy.appConsecutiveSustainedLaggingContentFrameThreshold
        self.streamShapeClientPressureVerySlowThresholdMilliseconds =
            BenchmarkStreamShapePacingPolicy.appVerySlowClientProcessingThresholdMilliseconds
        self.streamShapeClientPressureVerySlowRecoveryUpdateCount =
            BenchmarkStreamShapePacingPolicy.appVerySlowClientPressureRecoveryUpdateCount
        self.streamShapeClientPressureConsecutiveFullUploadFrameThreshold =
            BenchmarkStreamShapePacingPolicy.appConsecutiveFullUploadContentFrameThreshold
        self.streamShapeClientPressureRecoveryUpdateCount =
            BenchmarkStreamShapePacingPolicy.appClientPressureRecoveryUpdateCount
        self.streamShapeEmptyBackoffMediumStreakThreshold =
            BenchmarkStreamShapePacingPolicy.appMediumEmptyUpdateStreakThreshold
        self.streamShapeEmptyBackoffLongStreakThreshold =
            BenchmarkStreamShapePacingPolicy.appLongEmptyUpdateStreakThreshold
        self.streamShapeEmptyBackoffMediumIdleFrameIntervalSeconds =
            BenchmarkStreamShapePacingPolicy.appMediumIdleFrameInterval
        self.streamShapeEmptyBackoffLongIdleFrameIntervalSeconds =
            BenchmarkStreamShapePacingPolicy.appLongIdleFrameInterval
        self.firstFrameProfiles = firstFrameProfiles
        self.streamShapeProfiles = streamShapeProfiles.rawValue
        self.streamShapeTransportModes = streamShapeTransportModes
        self.timeoutSeconds = timeoutSeconds
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.safety = [
            "host, password, server name, framebuffer dimensions, pixel payloads, byte counts, cursor pixels, and raw error descriptions are not emitted",
            "stream-shape metrics emit aggregate counts and permille ratios only",
            "renderer upload metrics emit aggregate strategy counts only",
            "receive/network/client-processing timing metrics emit aggregate millisecond summaries only",
            "viewport-interaction metrics emit only fixed mode labels, configured pause windows, fixed pacing floors, counts, aggregate paused milliseconds, and permille ratios",
            "reports are written to stdout only"
        ]
        self.profiles = profiles
        self.idleProbe = idleProbe
        self.streamShapeProbe = streamShapeProbe
        self.streamShapeProfileProbes = streamShapeProfileProbes
        self.streamShapeRecommendation = BenchmarkStreamShapeRecommendation
            .recommendedRequestResponseProfile(from: streamShapeProfileProbes)
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
    let transportMode: BenchmarkStreamShapeTransportMode
    let firstFrameMilliseconds: Int?
    let summary: BenchmarkStreamShapeSummary

    init(
        transportMode: BenchmarkStreamShapeTransportMode,
        requestedSamples: Int,
        firstFrameMilliseconds: Int?,
        samples: [BenchmarkStreamShapeSample],
        elapsedMilliseconds: Int?,
        firstTimeoutMilliseconds: Int?,
        failureLabel: String?,
        adaptiveClientPressurePacingSamples: Int = 0,
        viewportInteractionPacingSamples: Int = 0,
        viewportInteractionPausedRequests: Int = 0,
        viewportInteractionPausePolls: Int = 0,
        viewportInteractionPausedMilliseconds: Int = 0
    ) {
        self.transportMode = transportMode
        self.firstFrameMilliseconds = firstFrameMilliseconds
        self.summary = BenchmarkStreamShapeSummary(
            requestedSamples: requestedSamples,
            samples: samples,
            elapsedMilliseconds: elapsedMilliseconds,
            firstTimeoutMilliseconds: firstTimeoutMilliseconds,
            failureLabel: failureLabel,
            adaptiveClientPressurePacingSamples: adaptiveClientPressurePacingSamples,
            viewportInteractionPacingSamples: viewportInteractionPacingSamples,
            viewportInteractionPausedRequestCount: viewportInteractionPausedRequests,
            viewportInteractionPausePollCount: viewportInteractionPausePolls,
            viewportInteractionPausedMilliseconds: viewportInteractionPausedMilliseconds
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
    print("safety: \(report.safety.joined(separator: "; "))")
    print("attempts per profile: \(report.attemptsPerProfile)")
    print("full-refresh samples per successful attempt: \(report.fullRefreshSamplesPerAttempt)")
    print("stream-shape samples: \(report.streamShapeSamples)")
    if let duration = report.streamShapeDurationSeconds {
        print("stream-shape duration seconds: \(formatSeconds(duration))")
    }
    print("stream-shape frame interval seconds: \(formatSeconds(report.streamShapeFrameIntervalSeconds))")
    print("stream-shape idle frame interval seconds: \(formatSeconds(report.streamShapeIdleFrameIntervalSeconds))")
    print("stream-shape empty backoff: \(report.streamShapeEmptyBackoffMode.rawValue)")
    print("stream-shape power mode: \(report.streamShapePowerMode.rawValue)")
    print("stream-shape client pressure: \(report.streamShapeClientPressureMode.rawValue)")
    print("stream-shape viewport interaction: \(report.streamShapeViewportInteractionMode.rawValue)")
    if report.streamShapePowerMode == .lowPower {
        print(
            "stream-shape low-power floors: content "
                + "\(formatSeconds(report.streamShapeLowPowerContentFrameIntervalSeconds))s, idle "
                + "\(formatSeconds(report.streamShapeLowPowerIdleFrameIntervalSeconds))s"
        )
    }
    if report.streamShapeClientPressureMode == .app {
        print(
            "stream-shape client-pressure thresholds: client-processing >= "
                + "\(report.streamShapeClientPressureLaggingThresholdMilliseconds)ms for "
                + "\(report.streamShapeClientPressureConsecutiveContentFrameThreshold) content frames, "
                + "or client-processing >= "
                + "\(report.streamShapeClientPressureSustainedLaggingThresholdMilliseconds)ms for "
                + "\(report.streamShapeClientPressureConsecutiveSustainedContentFrameThreshold) content frames, "
                + "or client-processing >= "
                + "\(report.streamShapeClientPressureVerySlowThresholdMilliseconds)ms once, "
                + "or full renderer uploads for "
                + "\(report.streamShapeClientPressureConsecutiveFullUploadFrameThreshold) content frames, "
                + "very-slow recovery "
                + "\(report.streamShapeClientPressureVerySlowRecoveryUpdateCount) updates, "
                + "sustained recovery \(report.streamShapeClientPressureRecoveryUpdateCount) updates"
            )
    }
    if report.streamShapeViewportInteractionMode == .app {
        print(
            "stream-shape viewport-interaction live cadence floors: content "
                + "\(formatSeconds(report.streamShapeViewportInteractionContentFrameIntervalSeconds))s, idle "
                + "\(formatSeconds(report.streamShapeViewportInteractionIdleFrameIntervalSeconds))s"
        )
    }
    if report.streamShapeEmptyBackoffMode == .app {
        print(
            "stream-shape empty backoff thresholds: "
                + "\(report.streamShapeEmptyBackoffMediumStreakThreshold)->"
                + "\(formatSeconds(report.streamShapeEmptyBackoffMediumIdleFrameIntervalSeconds))s, "
                + "\(report.streamShapeEmptyBackoffLongStreakThreshold)->"
                + "\(formatSeconds(report.streamShapeEmptyBackoffLongIdleFrameIntervalSeconds))s"
        )
    }
    print("first-frame profiles: \(report.firstFrameProfiles.rawValue)")
    print("stream-shape profiles: \(report.streamShapeProfiles)")
    print("stream-shape transport: \(report.streamShapeTransportModes.rawValue)")
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
    if report.streamShapeProfileProbes.count > 1 {
        print("")
        print("stream-shape profile probes:")
        for profileProbe in report.streamShapeProfileProbes {
            print("- \(profileProbe.label) [\(profileProbe.transportMode.rawValue)]:")
            renderStreamShapeSummary(
                firstFrameMilliseconds: profileProbe.firstFrameMilliseconds,
                summary: profileProbe.summary,
                indentation: "  "
            )
        }
    }
    if let recommendation = report.streamShapeRecommendation {
        print("")
        print("stream-shape recommendation:")
        print("- request-response profile: \(recommendation.label)")
        print("  reason: \(recommendation.reason)")
        print(
            "  update ms avg/p95: "
                + "\(recommendation.averageUpdateMilliseconds)/\(recommendation.p95UpdateMilliseconds)"
        )
        print(
            "  content fps: \(formatFramesPerSecond(recommendation.contentFramesPerSecond)); "
                + "full-upload permille: \(recommendation.rendererFullUploadPermille); "
                + "slow samples: \(recommendation.slowUpdateSamples)/\(recommendation.receivedSamples)"
        )
    }
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
    print("- transport: \(probe.transportMode.rawValue)")
    renderStreamShapeSummary(
        firstFrameMilliseconds: probe.firstFrameMilliseconds,
        summary: probe.summary,
        indentation: "  "
    )
}

private func renderStreamShapeSummary(
    firstFrameMilliseconds: Int?,
    summary: BenchmarkStreamShapeSummary,
    indentation: String
) {
    if let failure = summary.failureLabel {
        print("\(indentation)- status: \(summary.status.rawValue), failure: \(failure)")
        return
    }

    print("\(indentation)- status: \(summary.status.rawValue), received: \(summary.receivedSamples)/\(summary.requestedSamples)")
    let assessment = summary.practicalAssessment
    print(
        "\(indentation)  practical target: \(assessment.targetName) "
            + "\(assessment.verdict.rawValue)"
            + (assessment.issueCodes.isEmpty
                ? ""
                : " (\(assessment.issueCodes.map(\.rawValue).joined(separator: ",")))")
    )
    if let firstFrameMilliseconds {
        print("\(indentation)  first-frame ms: \(firstFrameMilliseconds)")
    }
    if let fps = summary.deliveredFramesPerSecond {
        print("\(indentation)  all-update fps: \(formatFramesPerSecond(fps))")
    }
    if let fps = summary.contentFramesPerSecond {
        print("\(indentation)  content-frame fps: \(formatFramesPerSecond(fps))")
    }
    if let latency = summary.updateLatency {
        print(
            "\(indentation)  update ms avg/p50/p95/min/max: "
                + "\(latency.averageMilliseconds)/\(latency.p50Milliseconds)/"
                + "\(latency.p95Milliseconds)/\(latency.minMilliseconds)/"
                + "\(latency.maxMilliseconds)"
        )
    }
    print(
        "\(indentation)  tail >=\(summary.tailLatency.slowUpdateThresholdMilliseconds)ms "
            + "samples/content/full-dirty/full-upload: "
            + "\(summary.tailLatency.slowUpdateSamples)/"
            + "\(summary.tailLatency.slowContentUpdateSamples)/"
            + "\(summary.tailLatency.slowFullDirtyAreaSamples)/"
            + "\(summary.tailLatency.slowRendererFullUploadSamples), "
            + ">=\(summary.tailLatency.verySlowUpdateThresholdMilliseconds)ms: "
            + "\(summary.tailLatency.verySlowUpdateSamples)"
    )
    if let firstVerySlow = summary.tailLatency.firstVerySlowUpdateOrdinal {
        let contentOrdinal = summary.tailLatency.firstVerySlowContentUpdateOrdinal
            .map(String.init) ?? "n/a"
        print(
            "\(indentation)  first very-slow update ordinal/content ordinal: "
                + "\(firstVerySlow)/\(contentOrdinal)"
        )
    }
    print("\(indentation)  empty/content/timeouts: \(summary.emptyUpdateSamples)/\(summary.contentUpdateSamples)/\(summary.timedOutSamples)")
    if let adaptivePermille = summary.adaptiveClientPressurePacingPermille,
       summary.adaptiveClientPressurePacingSamples > 0 {
        print(
            "\(indentation)  adaptive client-pressure pacing samples/permille: "
                + "\(summary.adaptiveClientPressurePacingSamples)/\(adaptivePermille)"
        )
    }
    if let viewportPermille = summary.viewportInteractionPacingPermille,
       summary.viewportInteractionPacingSamples > 0 {
        print(
            "\(indentation)  viewport-interaction pacing samples/permille: "
                + "\(summary.viewportInteractionPacingSamples)/\(viewportPermille)"
        )
    }
    if let pausePermille = summary.viewportInteractionPausedRequestPermille,
       summary.viewportInteractionPausedRequestCount > 0 {
        print(
            "\(indentation)  viewport-interaction paused requests/permille: "
                + "\(summary.viewportInteractionPausedRequestCount)/\(pausePermille)"
        )
        print(
            "\(indentation)  viewport-interaction pause polls/ms: "
                + "\(summary.viewportInteractionPausePollCount)/"
                + "\(summary.viewportInteractionPausedMilliseconds)"
        )
    }
    print("\(indentation)  actual encodings: \(formatEncodingMix(summary.actualEncodingMix))")
    if let dirtyRectangles = summary.dirtyRectangleCount {
        print(
            "\(indentation)  dirty rect count avg/p50/p95/min/max: "
                + "\(dirtyRectangles.averageMilliseconds)/\(dirtyRectangles.p50Milliseconds)/"
                + "\(dirtyRectangles.p95Milliseconds)/\(dirtyRectangles.minMilliseconds)/"
                + "\(dirtyRectangles.maxMilliseconds)"
        )
    }
    if let dirtyArea = summary.dirtyAreaPermille {
        print(
            "\(indentation)  dirty area permille avg/p50/p95/min/max: "
                + "\(dirtyArea.averageMilliseconds)/\(dirtyArea.p50Milliseconds)/"
                + "\(dirtyArea.p95Milliseconds)/\(dirtyArea.minMilliseconds)/"
                + "\(dirtyArea.maxMilliseconds)"
        )
    }
    if let changedPixels = summary.changedPixelsPermille {
        print(
            "\(indentation)  changed pixel permille avg/p50/p95/min/max: "
                + "\(changedPixels.averageMilliseconds)/\(changedPixels.p50Milliseconds)/"
                + "\(changedPixels.p95Milliseconds)/\(changedPixels.minMilliseconds)/"
                + "\(changedPixels.maxMilliseconds)"
        )
    }
    if let receiveTotal = summary.receiveTotalLatency {
        print(
            "\(indentation)  receive total ms avg/p50/p95/min/max: "
                + "\(receiveTotal.averageMilliseconds)/\(receiveTotal.p50Milliseconds)/"
                + "\(receiveTotal.p95Milliseconds)/\(receiveTotal.minMilliseconds)/"
                + "\(receiveTotal.maxMilliseconds)"
        )
    }
    if let networkRead = summary.networkReadLatency {
        print(
            "\(indentation)  network read ms avg/p50/p95/min/max: "
                + "\(networkRead.averageMilliseconds)/\(networkRead.p50Milliseconds)/"
                + "\(networkRead.p95Milliseconds)/\(networkRead.minMilliseconds)/"
                + "\(networkRead.maxMilliseconds)"
        )
    }
    if let clientProcessing = summary.clientProcessingLatency {
        print(
            "\(indentation)  client processing ms avg/p50/p95/min/max: "
                + "\(clientProcessing.averageMilliseconds)/\(clientProcessing.p50Milliseconds)/"
                + "\(clientProcessing.p95Milliseconds)/\(clientProcessing.minMilliseconds)/"
                + "\(clientProcessing.maxMilliseconds)"
        )
    }
    if summary.rendererUploadSampleCount > 0 {
        print(
            "\(indentation)  renderer uploads partial/full: "
                + "\(summary.rendererPartialUploadSamples)/\(summary.rendererFullUploadSamples)"
        )
        if let partialPermille = summary.rendererPartialUploadPermille,
           let fullPermille = summary.rendererFullUploadPermille {
            print(
                "\(indentation)  renderer upload permille partial/full: "
                    + "\(partialPermille)/\(fullPermille)"
            )
        }
        if let uploadRegions = summary.rendererUploadRegionCount {
            print(
                "\(indentation)  renderer upload region count avg/p50/p95/min/max: "
                    + "\(uploadRegions.averageValue)/\(uploadRegions.p50Value)/"
                    + "\(uploadRegions.p95Value)/\(uploadRegions.minValue)/"
                    + "\(uploadRegions.maxValue)"
            )
        }
    }
    if let timeout = summary.firstTimeoutMilliseconds {
        print("\(indentation)  first timeout ms: \(timeout)")
    }
}

private func formatEncodingMix(_ mix: RFBFramebufferEncodingMix) -> String {
    "raw=\(mix.rawRectangles),copyRect=\(mix.copyRectRectangles),hextile=\(mix.hextileRectangles),"
        + "zrle=\(mix.zrleRectangles),tight=\(mix.tightRectangles),cursor=\(mix.cursorRectangles),"
        + "xCursor=\(mix.xCursorRectangles),desktopSize=\(mix.desktopSizeRectangles),"
        + "extendedDesktopSize=\(mix.extendedDesktopSizeRectangles),lastRect=\(mix.lastRectRectangles),"
        + "endCU=\(mix.endOfContinuousUpdatesEvents)"
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
      swift run VNCLiveBenchmark [--attempts N] [--full-refresh-samples N] [--stream-shape-samples N] [--stream-shape-duration-seconds SECONDS] [--stream-shape-frame-interval SECONDS] [--stream-shape-idle-frame-interval SECONDS] [--stream-shape-empty-backoff app|none] [--stream-shape-power-mode normal|low-power] [--stream-shape-client-pressure off|app] [--stream-shape-viewport-interaction off|app] [--stream-shape-viewport-interaction-pause-seconds SECONDS] [--first-frame-profiles all|local-low-latency|stream-shape-profiles|none] [--stream-shape-profiles local-low-latency|all|PROFILE,...] [--stream-shape-transport request-response|continuous-updates|both] [--continuous-update-samples N] [--ask-password] [--timeout SECONDS] [--idle-timeout SECONDS] [--json]

    Options:
      --full-refresh-samples N  Extra non-incremental frame requests after each successful first frame. Defaults to 1; use 0 to disable.
      --stream-shape-samples N  Incremental request/response samples after a full frame. Defaults to 12; use 0 with --stream-shape-duration-seconds for duration-only sustained runs.
      --stream-shape-duration-seconds SECONDS
                                Optional sustained stream-shape duration limit. When set, the probe stops at this duration or the sample cap, whichever comes first.
      --stream-shape-frame-interval SECONDS
                                Delay after content stream-shape incremental requests. Defaults to \(formatSeconds(BenchmarkStreamShapePacingPolicy.appBalancedContentFrameInterval)), matching the app's balanced sustained-session cap.
      --stream-shape-idle-frame-interval SECONDS
                                Delay after empty stream-shape incremental requests. Defaults to 0.05, matching the app's idle poll backoff.
      --stream-shape-empty-backoff app|none
                                Adaptive backoff for sustained empty stream-shape replies. Defaults to app, matching the app's 8/24 empty-update thresholds.
      --stream-shape-power-mode normal|low-power
                                App power-mode pacing profile. Defaults to normal; low-power applies the app's 30 Hz content and 125 ms idle floors.
      --stream-shape-client-pressure off|app
                                Adaptive client-processing pressure pacing. Defaults to off; app mirrors the app's repeated lagging content-frame trigger.
      --stream-shape-viewport-interaction off|app
                                Viewport-interaction cadence parity. Defaults to off; app applies the same bounded live content/idle floors as active local zoom and pan.
      --stream-shape-viewport-interaction-pause-seconds SECONDS
                                Deprecated compatibility option; current app parity no longer pauses requests during viewport interaction.
      --first-frame-profiles all|local-low-latency|stream-shape-profiles|none
                                Profile set for first-frame/full-refresh probes. Defaults to all for compatibility; use stream-shape-profiles or none for longer stream-shape-only runs.
      --stream-shape-profiles \(BenchmarkStreamShapeProfileSelection.usageDescription(allProfileLabels: BenchmarkProfile.allCases.map(\.label)))
                                Profile set for stream-shape probes. Defaults to local-low-latency; use all to compare every encoding profile, or a comma-separated list for targeted long runs.
      --stream-shape-transport request-response|continuous-updates|both
                                Transport mode for stream-shape probes. Defaults to request-response; use both to compare request/response with the ContinuousUpdates overlay.
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
    Renderer upload metrics emit aggregate strategy counts only.
    """)
}

private func safeFailureLabel(for error: Error) -> String {
    BenchmarkFailureLabel.safeLabel(for: error)
}

private func safeFailureLabel(for error: Error, phase: BenchmarkFailurePhase) -> String {
    BenchmarkFailureLabel.safeLabel(for: error, phase: phase)
}
