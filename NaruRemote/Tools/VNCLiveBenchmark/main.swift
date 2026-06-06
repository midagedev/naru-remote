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
            if options.environmentPreflight {
                let report = BenchmarkLiveEnvironmentPreflightReport.make(
                    environment: ProcessInfo.processInfo.environment,
                    askPassword: options.askPassword,
                    stimulusMode: options.streamShapeStimulusMode
                )
                if options.json {
                    try renderJSON(report)
                } else {
                    renderText(report)
                }
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

            let proxy = try configuration.networkConditioningProxy(
                profile: options.networkConditionProfile
            )
            defer { proxy?.stop() }
            let report = try run(
                configuration: configuration.conditioned(by: proxy),
                options: options
            )
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
        let streamShapePacingWindowCandidates = options.effectiveStreamShapePacingWindowCandidates()
        let streamShapeRequestRegions = options.effectiveStreamShapeRequestRegions()
        let streamShapeSchedule = streamShapeProfileSchedule(
            profiles: options.streamShapeProfiles.profiles,
            transportModes: options.streamShapeTransportModes.modes,
            pacingWindows: streamShapePacingWindowCandidates,
            requestRegions: streamShapeRequestRegions,
            iterations: options.streamShapeProfileIterations,
            orderMode: options.streamShapeProfileOrderMode
        )
        let streamShapeProfileProbes = streamShapeSchedule.map { scheduledProbe in
            // Keep the report label and the request-loop pacing policy coupled
            // so a sweep cannot accidentally relabel identical measurements.
            let streamShapePacingPolicy = scheduledProbe.pacingWindow.policy(
                powerMode: options.streamShapePowerMode,
                clientPressureMode: options.streamShapeClientPressureMode,
                viewportInteractionMode: options.streamShapeViewportInteractionMode
            )
            return measureStreamShapeProfileProbe(
                profile: scheduledProbe.profile,
                transportMode: scheduledProbe.transportMode,
                pacingWindow: scheduledProbe.pacingWindow.label,
                requestRegion: scheduledProbe.requestRegion,
                configuration: configuration,
                timeout: options.timeout,
                idleTimeout: options.idleTimeout,
                maxSamples: options.streamShapeSamples,
                durationLimit: options.streamShapeDuration,
                pacingPolicy: streamShapePacingPolicy,
                stimulusMode: options.streamShapeStimulusMode,
                stimulusWarmupSeconds: options.streamShapeStimulusWarmupSeconds,
                stimulusFrameInterval: options.streamShapeStimulusFrameInterval,
                preflightFrames: options.streamShapePreflightFrames,
                practicalTargets: options.streamShapePracticalTarget.targets,
                iterationOrdinal: scheduledProbe.iterationOrdinal,
                orderOrdinal: scheduledProbe.orderOrdinal
            )
        }
        let streamShapeProbe = compatibilityStreamShapeProbe(
            from: streamShapeProfileProbes,
            fallbackTransportMode: options.streamShapeTransportModes.modes.first ?? .requestResponse,
            practicalTargets: options.streamShapePracticalTarget.targets
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
            networkConditionProfile: options.networkConditionProfile,
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
            streamShapeStimulusMode: options.streamShapeStimulusMode,
            streamShapeStimulusWarmupSeconds: options.streamShapeStimulusWarmupSeconds,
            streamShapeStimulusFrameInterval: options.streamShapeStimulusFrameInterval,
            streamShapePreflightFrames: options.streamShapePreflightFrames,
            streamShapePracticalTarget: options.streamShapePracticalTarget,
            streamShapeGatePreset: options.streamShapeGatePreset,
            streamShapeProfileIterations: options.streamShapeProfileIterations,
            streamShapeProfileOrderMode: options.streamShapeProfileOrderMode,
            streamShapePacingWindows: streamShapePacingWindowCandidates.map(\.label),
            streamShapeRequestRegions: streamShapeRequestRegions,
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

    private static func compatibilityStreamShapeProbe(
        from profileProbes: [BenchmarkStreamShapeProfileReport],
        fallbackTransportMode: BenchmarkStreamShapeTransportMode,
        practicalTargets: BenchmarkStreamShapePracticalTargets
    ) -> StreamShapeProbeReport {
        guard let firstProfileProbe = profileProbes.first else {
            return StreamShapeProbeReport(
                transportMode: fallbackTransportMode,
                requestedSamples: 0,
                firstFrameMilliseconds: nil,
                samples: [],
                elapsedMilliseconds: nil,
                firstTimeoutMilliseconds: nil,
                failureLabel: "stream-shape-schedule-empty",
                practicalTargets: practicalTargets
            )
        }
        return StreamShapeProbeReport(profileReport: firstProfileProbe)
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
            let client = RFBNetworkClient(
                encodingPreference: profile.preference,
                pixelFormatPreference: profile.pixelFormatPreference
            )
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
        guard maxSamples > 0 else {
            return ContinuousUpdatesProbeReport(
                requestedSamples: 0,
                samples: [],
                timeoutMilliseconds: nil,
                failureLabel: nil
            )
        }

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
        requestRegion: BenchmarkStreamShapeRequestRegion,
        configuration: LiveTargetConfiguration,
        timeout: TimeInterval,
        idleTimeout: TimeInterval,
        maxSamples: Int,
        durationLimit: TimeInterval?,
        pacingPolicy: BenchmarkStreamShapePacingPolicy,
        stimulusMode: BenchmarkStreamShapeStimulusMode,
        stimulusWarmupSeconds: TimeInterval,
        stimulusFrameInterval: TimeInterval,
        preflightFrames: Int,
        practicalTargets: BenchmarkStreamShapePracticalTargets
    ) -> StreamShapeProbeReport {
        guard maxSamples > 0 || durationLimit != nil else {
            return StreamShapeProbeReport(
                transportMode: transportMode,
                requestedSamples: 0,
                firstFrameMilliseconds: nil,
                samples: [],
                elapsedMilliseconds: nil,
                firstTimeoutMilliseconds: nil,
                failureLabel: nil,
                practicalTargets: practicalTargets
            )
        }

        let client = RFBNetworkClient(
            encodingPreference: profile.preference.applying(streamShapeTransportMode: transportMode),
            pixelFormatPreference: profile.pixelFormatPreference
        )
        let pump = RFBFramePump(source: client)
        var samples: [BenchmarkStreamShapeSample] = []
        var firstFrameMilliseconds: Int?
        var firstTimeoutMilliseconds: Int?
        var elapsedMilliseconds: Int?
        var failureLabel: String?
        var attemptedSamples = 0
        var emptyUpdateStreak = 0
        var clientPressureState = BenchmarkStreamShapeClientPressureState()
        var adaptiveClientPressurePacingSamples = 0
        var viewportInteractionPacingSamples = 0
        defer {
            pump.stopContinuousUpdatesIfNeeded(timeout: timeout)
            client.disconnect()
        }

        let serverInit: RFBServerInit
        do {
            serverInit = try client.connectSession(
                host: configuration.host,
                port: configuration.port,
                credential: .vncPassword(configuration.password),
                timeout: timeout
            )
        } catch {
            failureLabel = safeFailureLabel(for: error, phase: .streamConnect)
            return StreamShapeProbeReport(
                transportMode: transportMode,
                requestRegionAreaPermille: nil,
                requestedSamples: streamShapeRequestedSamples(
                    maxSamples: maxSamples,
                    durationLimit: durationLimit,
                    receivedSamples: samples.count
                ),
                attemptedSamples: attemptedSamples,
                firstFrameMilliseconds: firstFrameMilliseconds,
                samples: samples,
                elapsedMilliseconds: elapsedMilliseconds,
                firstTimeoutMilliseconds: firstTimeoutMilliseconds,
                failureLabel: failureLabel,
                practicalTargets: practicalTargets
            )
        }
        let requestRegionAreaPermille = requestRegion.requestAreaPermille(
            width: serverInit.width,
            height: serverInit.height
        )
        let stimulusStart = startStreamShapeStimulus(
            mode: stimulusMode,
            profile: profile,
            transportMode: transportMode,
            maxSamples: maxSamples,
            durationLimit: durationLimit,
            idleTimeout: idleTimeout,
            warmupSeconds: stimulusWarmupSeconds,
            frameInterval: stimulusFrameInterval
        )
        guard stimulusStart.failureLabel == nil else {
            return StreamShapeProbeReport(
                transportMode: transportMode,
                requestRegionAreaPermille: requestRegionAreaPermille,
                requestedSamples: streamShapeRequestedSamples(
                    maxSamples: maxSamples,
                    durationLimit: durationLimit,
                    receivedSamples: samples.count
                ),
                attemptedSamples: attemptedSamples,
                firstFrameMilliseconds: firstFrameMilliseconds,
                samples: samples,
                elapsedMilliseconds: elapsedMilliseconds,
                firstTimeoutMilliseconds: firstTimeoutMilliseconds,
                failureLabel: stimulusStart.failureLabel,
                practicalTargets: practicalTargets
            )
        }
        let runningStimulus = stimulusStart.runningStimulus
        defer {
            runningStimulus?.stop()
        }
        if runningStimulus != nil, stimulusWarmupSeconds > 0 {
            Thread.sleep(forTimeInterval: stimulusWarmupSeconds)
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
                requestRegionAreaPermille: requestRegionAreaPermille,
                requestedSamples: streamShapeRequestedSamples(
                    maxSamples: maxSamples,
                    durationLimit: durationLimit,
                    receivedSamples: samples.count
                ),
                attemptedSamples: attemptedSamples,
                firstFrameMilliseconds: firstFrameMilliseconds,
                samples: samples,
                elapsedMilliseconds: elapsedMilliseconds,
                firstTimeoutMilliseconds: firstTimeoutMilliseconds,
                failureLabel: failureLabel,
                practicalTargets: practicalTargets
            )
        }

        if transportMode == .continuousUpdates,
           !client.canEnableContinuousUpdates {
            failureLabel = safeFailureLabel(
                for: RFBNetworkClientError.continuousUpdatesNotConfirmed,
                phase: transportMode.streamFailurePhase
            )
            return StreamShapeProbeReport(
                transportMode: transportMode,
                requestRegionAreaPermille: requestRegionAreaPermille,
                requestedSamples: streamShapeRequestedSamples(
                    maxSamples: maxSamples,
                    durationLimit: durationLimit,
                    receivedSamples: samples.count
                ),
                attemptedSamples: attemptedSamples,
                firstFrameMilliseconds: firstFrameMilliseconds,
                samples: samples,
                elapsedMilliseconds: elapsedMilliseconds,
                firstTimeoutMilliseconds: firstTimeoutMilliseconds,
                failureLabel: failureLabel,
                practicalTargets: practicalTargets
            )
        }

        performStreamShapePreflightFrames(
            count: preflightFrames,
            pump: pump,
            transportMode: transportMode,
            requestRegion: requestRegion,
            framebufferWidth: serverInit.width,
            framebufferHeight: serverInit.height,
            idleTimeout: idleTimeout
        )

        let streamStartedAt = Date()
        var regionTimeoutStreak = 0
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
            attemptedSamples += 1
            do {
                guard let frame = try nextStreamShapeFrame(
                    pump: pump,
                    requestTimeout: requestTimeout,
                    updateMode: transportMode.framePumpUpdateMode,
                    requestRegion: requestRegion,
                    framebufferWidth: serverInit.width,
                    framebufferHeight: serverInit.height,
                    incrementalRequestIndex: attemptedSamples,
                    regionTimeoutStreak: &regionTimeoutStreak
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
            requestRegionAreaPermille: requestRegionAreaPermille,
            requestedSamples: streamShapeRequestedSamples(
                maxSamples: maxSamples,
                durationLimit: durationLimit,
                receivedSamples: samples.count
            ),
            attemptedSamples: attemptedSamples,
            firstFrameMilliseconds: firstFrameMilliseconds,
            samples: samples,
            elapsedMilliseconds: elapsedMilliseconds,
            firstTimeoutMilliseconds: firstTimeoutMilliseconds,
            failureLabel: failureLabel,
            adaptiveClientPressurePacingSamples: adaptiveClientPressurePacingSamples,
            viewportInteractionPacingSamples: viewportInteractionPacingSamples,
            viewportInteractionPausedRequests: 0,
            viewportInteractionPausePolls: 0,
            viewportInteractionPausedMilliseconds: 0,
            practicalTargets: practicalTargets
        )
    }

    private static func measureStreamShapeProfileProbe(
        profile: BenchmarkProfile,
        transportMode: BenchmarkStreamShapeTransportMode,
        pacingWindow: BenchmarkStreamShapePacingWindow,
        requestRegion: BenchmarkStreamShapeRequestRegion,
        configuration: LiveTargetConfiguration,
        timeout: TimeInterval,
        idleTimeout: TimeInterval,
        maxSamples: Int,
        durationLimit: TimeInterval?,
        pacingPolicy: BenchmarkStreamShapePacingPolicy,
        stimulusMode: BenchmarkStreamShapeStimulusMode,
        stimulusWarmupSeconds: TimeInterval,
        stimulusFrameInterval: TimeInterval,
        preflightFrames: Int,
        practicalTargets: BenchmarkStreamShapePracticalTargets,
        iterationOrdinal: Int? = nil,
        orderOrdinal: Int? = nil
    ) -> BenchmarkStreamShapeProfileReport {
        let probe = measureStreamShapeProbe(
            profile: profile,
            transportMode: transportMode,
            requestRegion: requestRegion,
            configuration: configuration,
            timeout: timeout,
            idleTimeout: idleTimeout,
            maxSamples: maxSamples,
            durationLimit: durationLimit,
            pacingPolicy: pacingPolicy,
            stimulusMode: stimulusMode,
            stimulusWarmupSeconds: stimulusWarmupSeconds,
            stimulusFrameInterval: stimulusFrameInterval,
            preflightFrames: preflightFrames,
            practicalTargets: practicalTargets
        )
        return BenchmarkStreamShapeProfileReport(
            label: profile.label,
            transportMode: transportMode,
            pacingWindow: pacingWindow,
            requestRegion: requestRegion,
            requestRegionAreaPermille: probe.requestRegionAreaPermille,
            iterationOrdinal: iterationOrdinal,
            orderOrdinal: orderOrdinal,
            firstFrameMilliseconds: probe.firstFrameMilliseconds,
            summary: probe.summary
        )
    }

    private static func streamShapeProfileSchedule(
        profiles: [BenchmarkProfile],
        transportModes: [BenchmarkStreamShapeTransportMode],
        pacingWindows: [BenchmarkStreamShapePacingWindowCandidate],
        requestRegions: [BenchmarkStreamShapeRequestRegion],
        iterations: Int,
        orderMode: BenchmarkStreamShapeProfileOrderMode
    ) -> [ScheduledStreamShapeProfileProbe] {
        let profiles = profiles.isEmpty ? [.localLowLatency] : profiles
        let transportModes = transportModes.isEmpty ? [.requestResponse] : transportModes
        let pacingWindows = pacingWindows.isEmpty
            ? [
                .single(
                    contentFrameInterval: BenchmarkStreamShapePacingPolicy.appBalancedContentFrameInterval,
                    idleFrameInterval: 0.05,
                    emptyBackoffMode: .app
                )
            ]
            : pacingWindows
        let requestRegions = requestRegions.isEmpty ? [.full] : requestRegions
        let iterations = max(iterations, 1)
        return (0..<iterations).flatMap { iteration in
            let scheduledProfiles = rotatedProfiles(
                profiles,
                offset: orderMode == .rotate ? iteration : 0
            )
            let scheduledTransportModes = rotatedTransportModes(
                transportModes,
                offset: orderMode == .rotate ? iteration : 0
            )
            let scheduledPacingWindows = rotatedPacingWindows(
                pacingWindows,
                offset: orderMode == .rotate ? iteration : 0
            )
            let scheduledRequestRegions = rotatedRequestRegions(
                requestRegions,
                offset: orderMode == .rotate ? iteration : 0
            )
            return scheduledProfiles.enumerated().flatMap { profileOffset, profile in
                scheduledTransportModes.enumerated().flatMap { transportOffset, transportMode in
                    scheduledPacingWindows.enumerated().flatMap { pacingOffset, pacingWindow in
                        scheduledRequestRegions.enumerated().map { regionOffset, requestRegion in
                            ScheduledStreamShapeProfileProbe(
                                profile: profile,
                                transportMode: transportMode,
                                pacingWindow: pacingWindow,
                                requestRegion: requestRegion,
                                iterationOrdinal: iteration + 1,
                                orderOrdinal: (
                                    profileOffset * transportModes.count * pacingWindows.count * requestRegions.count
                                        + transportOffset * pacingWindows.count * requestRegions.count
                                        + pacingOffset * requestRegions.count
                                        + regionOffset
                                        + 1
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private static func rotatedProfiles(
        _ profiles: [BenchmarkProfile],
        offset: Int
    ) -> [BenchmarkProfile] {
        guard !profiles.isEmpty else {
            return profiles
        }
        let offset = offset % profiles.count
        guard offset > 0 else {
            return profiles
        }
        return Array(profiles[offset...]) + Array(profiles[..<offset])
    }

    private static func rotatedTransportModes(
        _ transportModes: [BenchmarkStreamShapeTransportMode],
        offset: Int
    ) -> [BenchmarkStreamShapeTransportMode] {
        guard !transportModes.isEmpty else {
            return transportModes
        }
        let offset = offset % transportModes.count
        guard offset > 0 else {
            return transportModes
        }
        return Array(transportModes[offset...]) + Array(transportModes[..<offset])
    }

    private static func rotatedPacingWindows(
        _ pacingWindows: [BenchmarkStreamShapePacingWindowCandidate],
        offset: Int
    ) -> [BenchmarkStreamShapePacingWindowCandidate] {
        guard !pacingWindows.isEmpty else {
            return pacingWindows
        }
        let offset = offset % pacingWindows.count
        guard offset > 0 else {
            return pacingWindows
        }
        return Array(pacingWindows[offset...]) + Array(pacingWindows[..<offset])
    }

    private static func rotatedRequestRegions(
        _ requestRegions: [BenchmarkStreamShapeRequestRegion],
        offset: Int
    ) -> [BenchmarkStreamShapeRequestRegion] {
        guard !requestRegions.isEmpty else {
            return requestRegions
        }
        let offset = offset % requestRegions.count
        guard offset > 0 else {
            return requestRegions
        }
        return Array(requestRegions[offset...]) + Array(requestRegions[..<offset])
    }

    private static func performStreamShapePreflightFrames(
        count: Int,
        pump: RFBFramePump,
        transportMode: BenchmarkStreamShapeTransportMode,
        requestRegion: BenchmarkStreamShapeRequestRegion,
        framebufferWidth: Int,
        framebufferHeight: Int,
        idleTimeout: TimeInterval
    ) {
        guard count > 0 else {
            return
        }
        // Hidden preflight is best-effort warm-up: measured samples remain
        // the source of truth, and failure details stay out of redacted reports.
        var regionTimeoutStreak = 0
        for offset in 0..<count {
            do {
                guard try nextStreamShapeFrame(
                    pump: pump,
                    requestTimeout: idleTimeout,
                    updateMode: transportMode.framePumpUpdateMode,
                    requestRegion: requestRegion,
                    framebufferWidth: framebufferWidth,
                    framebufferHeight: framebufferHeight,
                    incrementalRequestIndex: offset + 1,
                    regionTimeoutStreak: &regionTimeoutStreak
                ) != nil else {
                    return
                }
            } catch RFBNetworkClientError.timedOut {
                return
            } catch RFBNetworkClientError.readTimedOut {
                return
            } catch {
                return
            }
        }
    }

    private static func nextStreamShapeFrame(
        pump: RFBFramePump,
        requestTimeout: TimeInterval,
        updateMode: RFBFramePumpUpdateMode,
        requestRegion: BenchmarkStreamShapeRequestRegion,
        framebufferWidth: Int,
        framebufferHeight: Int,
        incrementalRequestIndex: Int,
        regionTimeoutStreak: inout Int
    ) throws -> RFBFramePumpFrame? {
        let incrementalRequestRegion = requestRegion.region(
            width: framebufferWidth,
            height: framebufferHeight,
            incrementalRequestIndex: incrementalRequestIndex,
            regionTimeoutStreak: regionTimeoutStreak
        )

        do {
            let frame = try pump.nextFrame(
                requestTimeout: requestTimeout,
                updateMode: updateMode,
                requestRegion: incrementalRequestRegion
            )
            if frame?.transportIdleTimedOut == true,
               incrementalRequestRegion != nil,
               requestRegion.allowsRegionTimeoutFullFallback {
                regionTimeoutStreak += 1
                return try requestFullStreamShapeFallbackFrame(
                    pump: pump,
                    requestTimeout: requestTimeout,
                    updateMode: updateMode,
                    regionTimeoutStreak: &regionTimeoutStreak
                )
            }
            regionTimeoutStreak = 0
            return frame
        } catch RFBNetworkClientError.timedOut where incrementalRequestRegion != nil
            && requestRegion.allowsRegionTimeoutFullFallback {
            regionTimeoutStreak += 1
            return try requestFullStreamShapeFallbackFrame(
                pump: pump,
                requestTimeout: requestTimeout,
                updateMode: updateMode,
                regionTimeoutStreak: &regionTimeoutStreak
            )
        } catch RFBNetworkClientError.readTimedOut where incrementalRequestRegion != nil
            && requestRegion.allowsRegionTimeoutFullFallback {
            regionTimeoutStreak += 1
            return try requestFullStreamShapeFallbackFrame(
                pump: pump,
                requestTimeout: requestTimeout,
                updateMode: updateMode,
                regionTimeoutStreak: &regionTimeoutStreak
            )
        }
    }

    private static func requestFullStreamShapeFallbackFrame(
        pump: RFBFramePump,
        requestTimeout: TimeInterval,
        updateMode: RFBFramePumpUpdateMode,
        regionTimeoutStreak: inout Int
    ) throws -> RFBFramePumpFrame? {
        let frame = try pump.nextFrame(
            requestTimeout: requestTimeout,
            updateMode: updateMode,
            requestRegion: nil
        )
        regionTimeoutStreak = 0
        return frame
    }

    private static func startStreamShapeStimulus(
        mode: BenchmarkStreamShapeStimulusMode,
        profile: BenchmarkProfile,
        transportMode: BenchmarkStreamShapeTransportMode,
        maxSamples: Int,
        durationLimit: TimeInterval?,
        idleTimeout: TimeInterval,
        warmupSeconds: TimeInterval,
        frameInterval: TimeInterval
    ) -> StreamShapeStimulusStart {
        switch mode {
        case .off:
            return StreamShapeStimulusStart(runningStimulus: nil, failureLabel: nil)
        case .externalCommand:
            guard
                let command = ProcessInfo.processInfo.environment[BenchmarkStreamShapeStimulusEnvironment.commandKey]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !command.isEmpty
            else {
                return StreamShapeStimulusStart(
                    runningStimulus: nil,
                    failureLabel: streamShapeStimulusCommandMissingLabel
                )
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.environment = BenchmarkStreamShapeStimulusEnvironment.make(
                parent: ProcessInfo.processInfo.environment,
                durationSeconds: formatSeconds(
                    streamShapeStimulusDurationHint(
                        maxSamples: maxSamples,
                        durationLimit: durationLimit,
                        idleTimeout: idleTimeout,
                        warmupSeconds: warmupSeconds
                    )
                ),
                frameIntervalSeconds: String(frameInterval),
                profileLabel: profile.label,
                transportMode: transportMode.rawValue
            )

            let nullOutput = FileHandle(forWritingAtPath: "/dev/null")
            process.standardOutput = nullOutput
            process.standardError = nullOutput

            do {
                try process.run()
                return StreamShapeStimulusStart(
                    runningStimulus: RunningStreamShapeStimulus(process: process, nullOutput: nullOutput),
                    failureLabel: nil
                )
            } catch {
                try? nullOutput?.close()
                return StreamShapeStimulusStart(
                    runningStimulus: nil,
                    failureLabel: streamShapeStimulusCommandLaunchFailedLabel
                )
            }
        }
    }

    private static func streamShapeStimulusDurationHint(
        maxSamples: Int,
        durationLimit: TimeInterval?,
        idleTimeout: TimeInterval,
        warmupSeconds: TimeInterval
    ) -> TimeInterval {
        let streamDuration: TimeInterval
        if let durationLimit {
            streamDuration = durationLimit
        } else {
            streamDuration = Double(max(maxSamples, 1)) * max(idleTimeout, 0.001)
        }
        return max(streamDuration + warmupSeconds + idleTimeout + 1, 1)
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
        let hasZRLEMeasurement = frame.encodingMix.zrleRectangles > 0

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
            firstByteWaitMilliseconds: frame.timing?.firstByteWaitMilliseconds,
            payloadReadMilliseconds: frame.timing?.payloadReadMilliseconds,
            clientProcessingMilliseconds: frame.timing?.clientProcessingMilliseconds,
            zrleInflateMilliseconds: hasZRLEMeasurement ? frame.decodeMetrics.zrleInflateMilliseconds : nil,
            zrleTileApplyMilliseconds: hasZRLEMeasurement ? frame.decodeMetrics.zrleTileApplyMilliseconds : nil,
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
    var streamShapeStimulusMode: BenchmarkStreamShapeStimulusMode = .off
    var streamShapeStimulusWarmupSeconds: TimeInterval = 0.25
    var streamShapeStimulusFrameInterval: TimeInterval = 1.0 / 12.0
    var streamShapePreflightFrames = BenchmarkStreamShapePreflightFrames.defaultValue
    var streamShapePracticalTarget = BenchmarkStreamShapePracticalTargetSelection.defaultSelection
    var streamShapeGatePreset: BenchmarkStreamShapeGatePreset = .none
    var firstFrameProfiles: BenchmarkFirstFrameProfileSelection = .all
    var streamShapeProfiles: StreamShapeProfileSelection = .localLowLatency
    var streamShapeTransportModes: StreamShapeTransportModeSelection = .requestResponse
    var streamShapeProfileIterations = 1
    var streamShapeProfileOrderMode: BenchmarkStreamShapeProfileOrderMode = .fixed
    var streamShapePacingWindowCandidates: [BenchmarkStreamShapePacingWindowCandidate] = []
    var streamShapeRequestRegions: [BenchmarkStreamShapeRequestRegion] = []
    var networkConditionProfile: BenchmarkNetworkConditionProfile = .none
    var timeout: TimeInterval = 5
    var idleTimeout: TimeInterval = 0.75
    var askPassword = false
    var environmentPreflight = false
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
            case "--environment-preflight":
                options.environmentPreflight = true
                index = arguments.index(after: index)
            case "--network-condition":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let profile = BenchmarkNetworkConditionProfile(rawValue: value) else {
                    throw UsageError(
                        "network-condition must be \(BenchmarkNetworkConditionProfile.usageDescription)."
                    )
                }
                options.networkConditionProfile = profile
                index = arguments.index(index, offsetBy: 2)
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
                guard let samples = Int(value), samples >= 0 else {
                    throw UsageError("continuous-update-samples must be a non-negative integer.")
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
            case "--stream-shape-stimulus":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let mode = BenchmarkStreamShapeStimulusMode(rawValue: value) else {
                    throw UsageError(
                        "stream-shape-stimulus must be \(BenchmarkStreamShapeStimulusMode.usageDescription)."
                    )
                }
                options.streamShapeStimulusMode = mode
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-stimulus-warmup-seconds":
                let value = try nextValue(after: index, in: arguments, option: argument)
                options.streamShapeStimulusWarmupSeconds = try nonNegativeTimeInterval(
                    value,
                    option: argument
                )
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-stimulus-frame-interval":
                let value = try nextValue(after: index, in: arguments, option: argument)
                options.streamShapeStimulusFrameInterval = try positiveTimeInterval(
                    value,
                    option: argument
                )
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-preflight-frames":
                let value = try nextValue(after: index, in: arguments, option: argument)
                do {
                    options.streamShapePreflightFrames = try BenchmarkStreamShapePreflightFrames.parse(value)
                } catch let error as BenchmarkStreamShapePreflightFramesError {
                    throw UsageError(error.message)
                }
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-practical-target":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let target = BenchmarkStreamShapePracticalTargetSelection(rawValue: value) else {
                    throw UsageError(
                        "stream-shape-practical-target must be "
                            + BenchmarkStreamShapePracticalTargetSelection.usageDescription
                            + "."
                    )
                }
                options.streamShapePracticalTarget = target
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-gate-preset":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let preset = BenchmarkStreamShapeGatePreset(rawValue: value) else {
                    throw UsageError(
                        "stream-shape-gate-preset must be "
                            + BenchmarkStreamShapeGatePreset.usageDescription
                            + "."
                    )
                }
                options.streamShapeGatePreset = preset
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
            case "--stream-shape-profile-iterations":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let iterations = Int(value), (1...20).contains(iterations) else {
                    throw UsageError("stream-shape-profile-iterations must be an integer from 1 to 20.")
                }
                options.streamShapeProfileIterations = iterations
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-profile-order":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let mode = BenchmarkStreamShapeProfileOrderMode(rawValue: value) else {
                    throw UsageError(
                        "stream-shape-profile-order must be \(BenchmarkStreamShapeProfileOrderMode.usageDescription)."
                    )
                }
                options.streamShapeProfileOrderMode = mode
                index = arguments.index(index, offsetBy: 2)
            case "--stream-shape-request-region":
                let value = try nextValue(after: index, in: arguments, option: argument)
                guard let region = BenchmarkStreamShapeRequestRegion(rawValue: value) else {
                    throw UsageError(
                        "stream-shape-request-region must be "
                            + BenchmarkStreamShapeRequestRegion.usageDescription
                            + "."
                    )
                }
                options.streamShapeRequestRegions = [region]
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

        try options.applyStreamShapeGatePreset()
        return options
    }

    private mutating func applyStreamShapeGatePreset() throws {
        switch streamShapeGatePreset {
        case .none:
            return
        case .sustainedV2Core:
            try applySustainedV2Gate(
                profileSelection: BenchmarkStreamShapeProfileSelection.coreMatrixSelection,
                invalidProfileSelectionMessage: "internal sustained-v2-core preset profile selection is invalid."
            )
        case .sustainedV2RequestResponse:
            try applySustainedV2Gate(
                profileSelection: BenchmarkStreamShapeProfileSelection.coreMatrixSelection,
                invalidProfileSelectionMessage:
                    "internal sustained-v2-request-response preset profile selection is invalid.",
                transportModes: .requestResponse
            )
            continuousUpdateSamples = 0
        case .sustainedV2ZrleIsolation:
            try applySustainedV2Gate(
                profileSelection: BenchmarkStreamShapeProfileSelection.zrleIsolationSelection,
                invalidProfileSelectionMessage:
                    "internal sustained-v2-zrle-isolation preset profile selection is invalid.",
                transportModes: .requestResponse
            )
            continuousUpdateSamples = 0
        case .sustainedV2ZrleZeroDelay:
            try applySustainedV2Gate(
                profileSelection: BenchmarkStreamShapeProfileSelection.zrleIsolationSelection,
                invalidProfileSelectionMessage:
                    "internal sustained-v2-zrle-zero-delay preset profile selection is invalid.",
                transportModes: .requestResponse,
                contentFrameInterval: 0
            )
            continuousUpdateSamples = 0
        case .sustainedV2ZrlePacingSweep:
            try applySustainedV2Gate(
                profileSelection: "zrle-compression-0-clipboard",
                invalidProfileSelectionMessage:
                    "internal sustained-v2-zrle-pacing-sweep preset profile selection is invalid.",
                transportModes: .requestResponse,
                contentFrameInterval: 0
            )
            streamShapePacingWindowCandidates = BenchmarkStreamShapePacingWindowCandidate.requestPacingSweep
            continuousUpdateSamples = 0
        case .sustainedV2ZrleRegionSweep:
            try applySustainedV2Gate(
                profileSelection: "zrle-compression-0-clipboard",
                invalidProfileSelectionMessage:
                    "internal sustained-v2-zrle-region-sweep preset profile selection is invalid.",
                transportModes: .requestResponse,
                contentFrameInterval: 0
            )
            streamShapeRequestRegions = BenchmarkStreamShapeRequestRegion.requestRegionSweep
            continuousUpdateSamples = 0
        case .sustainedV2ZrleViewportRegion:
            try applySustainedV2Gate(
                profileSelection: "zrle-compression-0-clipboard",
                invalidProfileSelectionMessage:
                    "internal sustained-v2-zrle-viewport-region preset profile selection is invalid.",
                transportModes: .requestResponse,
                contentFrameInterval: 0
            )
            streamShapeRequestRegions = BenchmarkStreamShapeRequestRegion.viewportRequestRegionSweep
            continuousUpdateSamples = 0
        case .sustainedV2PixelFormat:
            try applySustainedV2Gate(
                profileSelection: BenchmarkStreamShapeProfileSelection.pixelFormatIsolationSelection,
                invalidProfileSelectionMessage:
                    "internal sustained-v2-pixel-format preset profile selection is invalid."
            )
        }
    }

    private mutating func applySustainedV2Gate(
        profileSelection: String,
        invalidProfileSelectionMessage: String,
        transportModes: StreamShapeTransportModeSelection = .both,
        contentFrameInterval: TimeInterval = 1.0 / 60.0
    ) throws {
        attempts = 1
        fullRefreshSamples = 0
        continuousUpdateSamples = 1
        streamShapeSamples = 0
        streamShapeDuration = 10
        streamShapeFrameInterval = max(contentFrameInterval, 0)
        streamShapeIdleFrameInterval = 0.05
        streamShapeEmptyBackoffMode = .app
        streamShapePowerMode = .normal
        streamShapeClientPressureMode = .app
        streamShapeViewportInteractionMode = .off
        streamShapeStimulusMode = .externalCommand
        streamShapeStimulusWarmupSeconds = 0.25
        streamShapeStimulusFrameInterval = 1.0 / 12.0
        streamShapePreflightFrames = 0
        streamShapePracticalTarget = .iPhoneSustainedUsability
        firstFrameProfiles = .none
        do {
            streamShapeProfiles = try StreamShapeProfileSelection.parse(profileSelection)
        } catch {
            throw UsageError(invalidProfileSelectionMessage)
        }
        streamShapeTransportModes = transportModes
        streamShapeProfileIterations = 5
        streamShapeProfileOrderMode = .rotate
        timeout = 6
        idleTimeout = 1
    }

    func effectiveStreamShapePacingWindowCandidates() -> [BenchmarkStreamShapePacingWindowCandidate] {
        if !streamShapePacingWindowCandidates.isEmpty {
            return streamShapePacingWindowCandidates
        }
        return [
            .single(
                contentFrameInterval: streamShapeFrameInterval,
                idleFrameInterval: streamShapeIdleFrameInterval,
                emptyBackoffMode: streamShapeEmptyBackoffMode
            )
        ]
    }

    func effectiveStreamShapeRequestRegions() -> [BenchmarkStreamShapeRequestRegion] {
        streamShapeRequestRegions.isEmpty ? [.full] : streamShapeRequestRegions
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
        if trimmed == "all"
            || trimmed == BenchmarkProfile.localLowLatency.label
            || trimmed == BenchmarkStreamShapeProfileSelection.coreMatrixSelection
            || trimmed == BenchmarkStreamShapeProfileSelection.zrleIsolationSelection {
            return trimmed
        }
        return selectedLabels.joined(separator: ",")
    }
}

private struct ScheduledStreamShapeProfileProbe {
    let profile: BenchmarkProfile
    let transportMode: BenchmarkStreamShapeTransportMode
    let pacingWindow: BenchmarkStreamShapePacingWindowCandidate
    let requestRegion: BenchmarkStreamShapeRequestRegion
    let iterationOrdinal: Int
    let orderOrdinal: Int
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

    func networkConditioningProxy(
        profile: BenchmarkNetworkConditionProfile
    ) throws -> BenchmarkNetworkConditioningProxy? {
        guard profile != .none else {
            return nil
        }
        return try BenchmarkNetworkConditioningProxy.start(
            upstreamHost: host,
            upstreamPort: port,
            profile: profile
        )
    }

    func conditioned(by proxy: BenchmarkNetworkConditioningProxy?) -> LiveTargetConfiguration {
        guard let proxy else {
            return self
        }
        return LiveTargetConfiguration(
            host: "127.0.0.1",
            port: proxy.localPort,
            password: password
        )
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

private let streamShapeStimulusCommandMissingLabel = "stream-stimulus-command-missing"
private let streamShapeStimulusCommandLaunchFailedLabel = "stream-stimulus-command-launch-failed"
private let streamShapeStimulusTerminationGraceSeconds: TimeInterval = 0.1
private let streamShapeStimulusTerminationPollSeconds: TimeInterval = 0.01

private struct StreamShapeStimulusStart {
    let runningStimulus: RunningStreamShapeStimulus?
    let failureLabel: String?
}

private final class RunningStreamShapeStimulus {
    private let process: Process
    private let nullOutput: FileHandle?

    init(process: Process, nullOutput: FileHandle?) {
        self.process = process
        self.nullOutput = nullOutput
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(streamShapeStimulusTerminationGraceSeconds)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: streamShapeStimulusTerminationPollSeconds)
            }
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        try? nullOutput?.close()
    }
}

private enum BenchmarkProfile: CaseIterable, Equatable {
    case localLowLatency
    case localLowLatencyRGB565
    case tightFirst
    case zrleFirst
    case zrleCompressionZero
    case zrleCompressionZeroRGB565
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
        case .localLowLatencyRGB565:
            "local-low-latency-rgb565"
        case .tightFirst:
            "tight-first"
        case .zrleFirst:
            "zrle-first"
        case .zrleCompressionZero:
            "zrle-compression-0"
        case .zrleCompressionZeroRGB565:
            "zrle-compression-0-rgb565"
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
        case .localLowLatency, .localLowLatencyRGB565:
            return .localLowLatency
        case .tightFirst:
            return RFBEncodingPreference(
                tight: true,
                tightQualityLevel: 8,
                compressionLevel: 1
            )
        case .zrleFirst:
            return .increment2
        case .zrleCompressionZero, .zrleCompressionZeroRGB565:
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

    var pixelFormatPreference: RFBPixelFormat? {
        switch self {
        case .localLowLatencyRGB565, .zrleCompressionZeroRGB565:
            return .rgb565In32LittleEndian
        default:
            return nil
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
    let networkCondition: BenchmarkNetworkConditionProfile
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
    let streamShapeStimulusMode: BenchmarkStreamShapeStimulusMode
    let streamShapeStimulusWarmupSeconds: TimeInterval
    let streamShapeStimulusFrameIntervalSeconds: TimeInterval
    let streamShapeStimulusExpectedFramesPerSecond: Double?
    let streamShapePreflightFrames: Int
    let streamShapePracticalTarget: BenchmarkStreamShapePracticalTargetSelection
    let streamShapeGatePreset: BenchmarkStreamShapeGatePreset
    let streamShapeProfileIterations: Int
    let streamShapeProfileOrderMode: BenchmarkStreamShapeProfileOrderMode
    let streamShapePacingWindows: [BenchmarkStreamShapePacingWindow]
    let streamShapeRequestRegions: [BenchmarkStreamShapeRequestRegion]
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
    let streamShapeProfileAggregates: [BenchmarkStreamShapeProfileAggregateReport]
    let streamShapeProfileGates: [BenchmarkStreamShapeProfileGateReport]
    let streamShapeOptimizationDecision: BenchmarkStreamShapeOptimizationDecision?
    let streamShapeTransportCadenceDiagnosis: BenchmarkStreamShapeTransportCadenceDiagnosis?
    let streamShapeRequestCadenceHealth: BenchmarkStreamShapeRequestCadenceHealth?
    let streamShapeRecommendation: BenchmarkStreamShapeRecommendation?
    let streamShapeOrderNeutralRecommendation: BenchmarkStreamShapeRecommendation?
    let continuousUpdatesProbe: ContinuousUpdatesProbeReport

    init(
        attemptsPerProfile: Int,
        fullRefreshSamplesPerAttempt: Int,
        continuousUpdateSamples: Int,
        networkConditionProfile: BenchmarkNetworkConditionProfile,
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
        streamShapeStimulusMode: BenchmarkStreamShapeStimulusMode,
        streamShapeStimulusWarmupSeconds: TimeInterval,
        streamShapeStimulusFrameInterval: TimeInterval,
        streamShapePreflightFrames: Int,
        streamShapePracticalTarget: BenchmarkStreamShapePracticalTargetSelection,
        streamShapeGatePreset: BenchmarkStreamShapeGatePreset,
        streamShapeProfileIterations: Int,
        streamShapeProfileOrderMode: BenchmarkStreamShapeProfileOrderMode,
        streamShapePacingWindows: [BenchmarkStreamShapePacingWindow],
        streamShapeRequestRegions: [BenchmarkStreamShapeRequestRegion],
        firstFrameProfiles: BenchmarkFirstFrameProfileSelection,
        streamShapeProfiles: StreamShapeProfileSelection,
        streamShapeTransportModes: StreamShapeTransportModeSelection,
        profiles: [ProfileReport],
        idleProbe: IdleProbeReport,
        streamShapeProbe: StreamShapeProbeReport,
        streamShapeProfileProbes: [BenchmarkStreamShapeProfileReport],
        continuousUpdatesProbe: ContinuousUpdatesProbeReport
    ) {
        self.schemaVersion = 55
        self.target = "configured-redacted"
        self.networkCondition = networkConditionProfile
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
        self.streamShapeStimulusMode = streamShapeStimulusMode
        self.streamShapeStimulusWarmupSeconds = streamShapeStimulusWarmupSeconds
        self.streamShapeStimulusFrameIntervalSeconds = streamShapeStimulusFrameInterval
        self.streamShapeStimulusExpectedFramesPerSecond = streamShapeStimulusMode == .externalCommand
            ? 1 / max(streamShapeStimulusFrameInterval, 0.001)
            : nil
        self.streamShapePreflightFrames = BenchmarkStreamShapePreflightFrames.clamped(streamShapePreflightFrames)
        self.streamShapePracticalTarget = streamShapePracticalTarget
        self.streamShapeGatePreset = streamShapeGatePreset
        self.streamShapeProfileIterations = max(streamShapeProfileIterations, 1)
        self.streamShapeProfileOrderMode = streamShapeProfileOrderMode
        self.streamShapePacingWindows = streamShapePacingWindows.isEmpty ? [.single] : streamShapePacingWindows
        self.streamShapeRequestRegions = streamShapeRequestRegions.isEmpty ? [.full] : streamShapeRequestRegions
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
        let streamShapeProfileAggregates = BenchmarkStreamShapeProfileAggregateReport
            .aggregates(from: streamShapeProfileProbes)
        self.safety = [
            "host, password, server name, framebuffer dimensions, pixel payloads, byte counts, cursor pixels, and raw error descriptions are not emitted",
            "stream-shape metrics emit aggregate counts and permille ratios only",
            "renderer upload metrics emit aggregate strategy counts only",
            "receive/network/client-processing timing metrics emit aggregate millisecond summaries only",
            "zrle decode phase timing metrics emit aggregate millisecond summaries only",
            "stream-shape stimulus reports emit only fixed mode labels, warmup seconds, and configured cadence; external command text and command output are not emitted, and target environment variables are not forwarded to the stimulus child",
            "profile-order metrics emit only fixed iteration/order ordinals and aggregate per-profile summaries",
            "stream-shape preflight reports emit only the fixed requested hidden-frame count; hidden preflight frame contents and timings are not emitted",
            "practical target reports emit only fixed target names, fixed verdicts, fixed issue codes, fixed triage labels, and aggregate threshold outcomes",
            "stream-shape hit-rate metrics emit only aggregate sample counts and permille ratios",
            "stream-shape profile gate reports emit only fixed target names, fixed verdicts, fixed issue codes, fixed triage labels, aggregate run counts, and permille ratios",
            "stream-shape transport cadence diagnosis emits only fixed transport/status/action labels and aggregate gate/failure counts",
            "stream-shape request cadence health emits only fixed sample/latency/action labels plus aggregate request-response counts, permille ratios, and millisecond summaries",
            "stream-shape pacing-window comparisons emit only fixed candidate labels plus existing aggregate stream-shape metrics",
            "stream-shape request-region comparisons emit only fixed candidate labels plus existing aggregate stream-shape metrics",
            "request-region traffic-pressure metrics emit only framebuffer-relative area permille ratios, never dimensions, coordinates, bytes, or pixels",
            "network conditioning reports emit only fixed condition labels; proxy ports, upstream hosts, and byte counters are not emitted",
            "stream-shape phase-budget diagnostics emit only fixed phase/subphase labels, aggregate millisecond summaries, and permille shares",
            "pixel-format benchmark profiles emit only fixed profile labels; negotiated framebuffer dimensions, pixels, and byte counts are not emitted",
            "viewport-interaction metrics emit only fixed mode labels, configured pause windows, fixed pacing floors, counts, aggregate paused milliseconds, and permille ratios",
            "reports are written to stdout only"
        ]
        self.profiles = profiles
        self.idleProbe = idleProbe
        self.streamShapeProbe = streamShapeProbe
        self.streamShapeProfileProbes = streamShapeProfileProbes
        self.streamShapeProfileAggregates = streamShapeProfileAggregates
        let streamShapeProfileGates = BenchmarkStreamShapeProfileGateReport.gates(from: streamShapeProfileProbes)
        self.streamShapeProfileGates = streamShapeProfileGates
        self.streamShapeOptimizationDecision = BenchmarkStreamShapeOptimizationDecision.decision(
            from: streamShapeProfileGates
        )
        self.streamShapeTransportCadenceDiagnosis = BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(
            from: streamShapeProfileGates
        )
        self.streamShapeRequestCadenceHealth = BenchmarkStreamShapeRequestCadenceHealth.health(
            from: streamShapeProfileAggregates,
            gates: streamShapeProfileGates,
            targets: streamShapePracticalTarget.targets
        )
        self.streamShapeRecommendation = BenchmarkStreamShapeRecommendation
            .recommendedRequestResponseProfile(from: streamShapeProfileProbes)
        self.streamShapeOrderNeutralRecommendation = BenchmarkStreamShapeRecommendation
            .recommendedOrderNeutralRequestResponseProfile(from: streamShapeProfileAggregates)
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
    let requestRegionAreaPermille: Int?
    let firstFrameMilliseconds: Int?
    let summary: BenchmarkStreamShapeSummary

    init(profileReport: BenchmarkStreamShapeProfileReport) {
        self.transportMode = profileReport.transportMode
        self.requestRegionAreaPermille = profileReport.requestRegionAreaPermille
        self.firstFrameMilliseconds = profileReport.firstFrameMilliseconds
        self.summary = profileReport.summary
    }

    init(
        transportMode: BenchmarkStreamShapeTransportMode,
        requestRegionAreaPermille: Int? = nil,
        requestedSamples: Int,
        attemptedSamples: Int? = nil,
        firstFrameMilliseconds: Int?,
        samples: [BenchmarkStreamShapeSample],
        elapsedMilliseconds: Int?,
        firstTimeoutMilliseconds: Int?,
        failureLabel: String?,
        adaptiveClientPressurePacingSamples: Int = 0,
        viewportInteractionPacingSamples: Int = 0,
        viewportInteractionPausedRequests: Int = 0,
        viewportInteractionPausePolls: Int = 0,
        viewportInteractionPausedMilliseconds: Int = 0,
        practicalTargets: BenchmarkStreamShapePracticalTargets = .iPhonePracticalBaseline
    ) {
        self.transportMode = transportMode
        self.requestRegionAreaPermille = requestRegionAreaPermille.map { min(max($0, 0), 1_000) }
        self.firstFrameMilliseconds = firstFrameMilliseconds
        self.summary = BenchmarkStreamShapeSummary(
            requestedSamples: requestedSamples,
            attemptedSamples: attemptedSamples,
            samples: samples,
            elapsedMilliseconds: elapsedMilliseconds,
            firstTimeoutMilliseconds: firstTimeoutMilliseconds,
            failureLabel: failureLabel,
            adaptiveClientPressurePacingSamples: adaptiveClientPressurePacingSamples,
            viewportInteractionPacingSamples: viewportInteractionPacingSamples,
            viewportInteractionPausedRequestCount: viewportInteractionPausedRequests,
            viewportInteractionPausePollCount: viewportInteractionPausePolls,
            viewportInteractionPausedMilliseconds: viewportInteractionPausedMilliseconds,
            practicalTargets: practicalTargets
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
            requestedSamples: requestedSamples,
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
        requestedSamples: Int,
        emptyUpdateSamples: Int,
        contentUpdateSamples: Int,
        timeoutMilliseconds: Int?,
        failureLabel: String?
    ) -> ContinuousUpdatesProbeStatus {
        if requestedSamples == 0 {
            return .notTested
        }
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
    case notTested = "not-tested"
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
    print("network condition: \(report.networkCondition.rawValue)")
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
    print("stream-shape stimulus: \(report.streamShapeStimulusMode.rawValue)")
    print("stream-shape stimulus warmup seconds: \(formatSeconds(report.streamShapeStimulusWarmupSeconds))")
    print(
        "stream-shape stimulus frame interval seconds: "
            + "\(formatSeconds(report.streamShapeStimulusFrameIntervalSeconds))"
    )
    if let expectedFPS = report.streamShapeStimulusExpectedFramesPerSecond {
        print("stream-shape stimulus expected FPS: \(formatFramesPerSecond(expectedFPS))")
    }
    print("stream-shape preflight frames: \(report.streamShapePreflightFrames)")
    print("stream-shape practical target: \(report.streamShapePracticalTarget.rawValue)")
    print("stream-shape gate preset: \(report.streamShapeGatePreset.rawValue)")
    print("stream-shape profile iterations: \(report.streamShapeProfileIterations)")
    print("stream-shape profile order: \(report.streamShapeProfileOrderMode.rawValue)")
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
    print(
        "stream-shape pacing windows: "
            + report.streamShapePacingWindows.map(\.rawValue).joined(separator: ",")
    )
    print(
        "stream-shape request regions: "
            + report.streamShapeRequestRegions.map(\.rawValue).joined(separator: ",")
    )
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
            let ordinalSuffix: String
            if let iteration = profileProbe.iterationOrdinal, let order = profileProbe.orderOrdinal {
                ordinalSuffix = " iteration \(iteration), order \(order)"
            } else {
                ordinalSuffix = ""
            }
            print(
                "- \(profileProbe.label) [\(profileProbe.transportMode.rawValue), "
                    + "\(profileProbe.pacingWindow.rawValue), "
                    + "\(profileProbe.requestRegion.rawValue)]\(ordinalSuffix):"
            )
            if let requestRegionArea = profileProbe.requestRegionAreaPermille {
                print("  request-region area permille: \(requestRegionArea)")
            }
            renderStreamShapeSummary(
                firstFrameMilliseconds: profileProbe.firstFrameMilliseconds,
                summary: profileProbe.summary,
                indentation: "  "
            )
        }
    }
    if report.streamShapeProfileAggregates.count > 1 {
        print("")
        print("stream-shape profile aggregates:")
        for aggregate in report.streamShapeProfileAggregates {
            print(
                "- \(aggregate.label) [\(aggregate.transportMode.rawValue), "
                    + "\(aggregate.pacingWindow.rawValue), "
                    + "\(aggregate.requestRegion.rawValue)]:"
            )
            print(
                "  runs usable/total/failed: "
                    + "\(aggregate.usableRunCount)/\(aggregate.runCount)/\(aggregate.failedRunCount)"
            )
            if let requestRegionArea = aggregate.averageRequestRegionAreaPermille {
                print("  request-region area permille avg: \(requestRegionArea)")
            }
            if let averageUpdate = aggregate.averageUpdateMilliseconds,
               let maxP95 = aggregate.maxP95UpdateMilliseconds {
                print("  update ms avg/max-p95: \(averageUpdate)/\(maxP95)")
            } else {
                print("  update ms avg/max-p95: n/a")
            }
            if let contentFPS = aggregate.averageContentFramesPerSecond,
               let fullUpload = aggregate.averageRendererFullUploadPermille {
                print(
                    "  content fps avg: \(formatFramesPerSecond(contentFPS)); "
                        + "full-upload permille avg: \(fullUpload); "
                        + "slow/very-slow samples: "
                        + "\(aggregate.slowUpdateSamples)/\(aggregate.verySlowUpdateSamples)"
                )
            } else {
                print("  content fps avg: n/a")
            }
            let networkShare = aggregate.averageNetworkReadSharePermille.map(String.init) ?? "n/a"
            let firstByteShare = aggregate.averageFirstByteWaitSharePermille.map(String.init) ?? "n/a"
            let payloadShare = aggregate.averagePayloadReadSharePermille.map(String.init) ?? "n/a"
            let clientShare = aggregate.averageClientProcessingSharePermille.map(String.init) ?? "n/a"
            let loopShare = aggregate.averageRequestLoopSharePermille.map(String.init) ?? "n/a"
            print(
                "  phase dominant/slow-dominant: "
                    + "\(aggregate.dominantPhase.rawValue)/\(aggregate.slowDominantPhase.rawValue)"
            )
            print(
                "  network-read subphase dominant/slow-dominant: "
                    + "\(aggregate.networkReadDominantSubphase.rawValue)/"
                    + "\(aggregate.slowNetworkReadDominantSubphase.rawValue)"
            )
            print(
                "  phase share permille avg network/client/request-loop: "
                    + "\(networkShare)/\(clientShare)/\(loopShare)"
            )
            print(
                "  network-read split permille avg first-byte/payload: "
                    + "\(firstByteShare)/\(payloadShare)"
            )
            if let firstByteP95 = aggregate.maxFirstByteWaitP95Milliseconds,
               let payloadP95 = aggregate.maxPayloadReadP95Milliseconds {
                print("  network-read split ms max-p95 first-byte/payload: \(firstByteP95)/\(payloadP95)")
            }
            if let receivedRequest = aggregate.averageReceivedSamplePermille,
               let contentRequest = aggregate.averageContentSamplePermille,
               let contentResponse = aggregate.averageContentResponsePermille,
               let unanswered = aggregate.averageUnansweredSamplePermille {
                print(
                    "  hit-rate permille avg received/request content/request content/response unanswered: "
                        + "\(receivedRequest)/\(contentRequest)/\(contentResponse)/\(unanswered)"
                )
            }
        }
    }
    if !report.streamShapeProfileGates.isEmpty {
        print("")
        print("stream-shape profile gates:")
        for gate in report.streamShapeProfileGates {
            print(
                "- \(gate.label) [\(gate.transportMode.rawValue), "
                    + "\(gate.pacingWindow.rawValue), "
                    + "\(gate.requestRegion.rawValue)]: \(gate.verdict.rawValue)"
            )
            if let requestRegionArea = gate.averageRequestRegionAreaPermille {
                print("  request-region area permille avg: \(requestRegionArea)")
            }
            print(
                "  target: \(gate.targetName); runs pass/warning/fail/disabled/total: "
                    + "\(gate.passRunCount)/\(gate.warningRunCount)/\(gate.failRunCount)/"
                    + "\(gate.disabledRunCount)/\(gate.runCount)"
            )
            let issues = gate.issueCodes.map(\.rawValue).joined(separator: ",")
            print("  issues: \(issues.isEmpty ? "none" : issues)")
            print(
                "  primary: "
                    + "\(gate.primaryIssueCode?.rawValue ?? "none") / "
                    + "\(gate.primaryConstraint) / \(gate.recommendedNextProbe)"
            )
            print("  constraint counts: \(formatTriageCounts(gate.primaryConstraintCounts))")
            print("  next-probe counts: \(formatTriageCounts(gate.recommendedNextProbeCounts))")
            print("  failure labels: \(formatTriageCounts(gate.failureLabelCounts))")
            let receivedRequest = gate.averageReceivedSamplePermille.map(String.init) ?? "n/a"
            let contentRequest = gate.averageContentSamplePermille.map(String.init) ?? "n/a"
            let contentResponse = gate.averageContentResponsePermille.map(String.init) ?? "n/a"
            let unanswered = gate.averageUnansweredSamplePermille.map(String.init) ?? "n/a"
            print(
                "  hit-rate permille avg received/request content/request content/response unanswered: "
                    + "\(receivedRequest)/\(contentRequest)/\(contentResponse)/\(unanswered)"
            )
        }
    }
    if let decision = report.streamShapeOptimizationDecision {
        print("")
        print("stream-shape optimization decision:")
        print("- target: \(decision.targetName); verdict: \(decision.verdict.rawValue)")
        print(
            "  gates pass/warning/fail/disabled/blocked/total: "
                + "\(decision.passGateCount)/\(decision.warningGateCount)/"
                + "\(decision.failGateCount)/\(decision.disabledGateCount)/"
                + "\(decision.blockedGateCount)/\(decision.gateCount)"
        )
        print(
            "  primary: "
                + "\(decision.primaryIssueCode?.rawValue ?? "none") / "
                + "\(decision.primaryConstraint) / \(decision.recommendedNextProbe)"
        )
        print("  constraint counts: \(formatTriageCounts(decision.primaryConstraintCounts))")
        print("  next-probe counts: \(formatTriageCounts(decision.recommendedNextProbeCounts))")
        print("  failure labels: \(formatTriageCounts(decision.failureLabelCounts))")
    }
    if let diagnosis = report.streamShapeTransportCadenceDiagnosis {
        print("")
        print("stream-shape transport cadence diagnosis:")
        print("- target: \(diagnosis.targetName)")
        print(
            "  status request-response/continuous-updates: "
                + "\(diagnosis.requestResponseStatus.rawValue)/\(diagnosis.continuousUpdatesStatus.rawValue)"
        )
        print(
            "  gates request-response blocked/total: "
                + "\(diagnosis.requestResponseBlockedGateCount)/\(diagnosis.requestResponseGateCount)"
        )
        print(
            "  gates continuous-updates blocked/total: "
                + "\(diagnosis.continuousUpdatesBlockedGateCount)/\(diagnosis.continuousUpdatesGateCount)"
        )
        print(
            "  recommended transport/action: "
                + "\(diagnosis.recommendedTransportMode?.rawValue ?? "none")/"
                + "\(diagnosis.recommendedNextAction.rawValue)"
        )
        print(
            "  request-response constraints: "
                + "\(formatTriageCounts(diagnosis.requestResponsePrimaryConstraintCounts))"
        )
        print(
            "  continuous-updates constraints: "
                + "\(formatTriageCounts(diagnosis.continuousUpdatesPrimaryConstraintCounts))"
        )
        print(
            "  request-response failure labels: "
                + "\(formatTriageCounts(diagnosis.requestResponseFailureLabelCounts))"
        )
        print(
            "  continuous-updates failure labels: "
                + "\(formatTriageCounts(diagnosis.continuousUpdatesFailureLabelCounts))"
        )
    }
    if let health = report.streamShapeRequestCadenceHealth {
        print("")
        print("stream-shape request cadence health:")
        print("- target: \(health.targetName)")
        print(
            "  sample/latency/action: "
                + "\(health.sampleStatus.rawValue)/"
                + "\(health.latencyStatus.rawValue)/"
                + "\(health.recommendedNextProbe.rawValue)"
        )
        print(
            "  gates blocked/total; aggregates usable-runs/count: "
                + "\(health.requestResponseBlockedGateCount)/\(health.requestResponseGateCount); "
                + "\(health.requestResponseUsableRunCount)/\(health.requestResponseAggregateCount)"
        )
        let received = health.averageReceivedSamplePermille.map(String.init) ?? "n/a"
        let unanswered = health.averageUnansweredSamplePermille.map(String.init) ?? "n/a"
        let contentRequest = health.averageContentSamplePermille.map(String.init) ?? "n/a"
        let contentResponse = health.averageContentResponsePermille.map(String.init) ?? "n/a"
        print(
            "  hit-rate permille avg received/request content/request content/response unanswered: "
                + "\(received)/\(contentRequest)/\(contentResponse)/\(unanswered)"
        )
        let averageUpdate = health.averageUpdateMilliseconds.map(String.init) ?? "n/a"
        let maxP95 = health.maxP95UpdateMilliseconds.map(String.init) ?? "n/a"
        let contentFPS = health.averageContentFramesPerSecond.map(formatFramesPerSecond) ?? "n/a"
        print("  update ms avg/max-p95; content fps avg: \(averageUpdate)/\(maxP95); \(contentFPS)")
        print(
            "  phase dominant/slow-dominant: "
                + "\(health.dominantPhase.rawValue)/\(health.slowDominantPhase.rawValue)"
        )
        let firstByteShare = health.averageFirstByteWaitSharePermille.map(String.init) ?? "n/a"
        let payloadShare = health.averagePayloadReadSharePermille.map(String.init) ?? "n/a"
        print(
            "  network-read subphase dominant/slow-dominant: "
                + "\((health.networkReadDominantSubphase ?? .unknown).rawValue)/"
                + "\((health.slowNetworkReadDominantSubphase ?? .unknown).rawValue)"
        )
        print(
            "  network-read split permille avg first-byte/payload: "
                + "\(firstByteShare)/\(payloadShare)"
        )
        if let firstByteP95 = health.maxFirstByteWaitP95Milliseconds,
           let payloadP95 = health.maxPayloadReadP95Milliseconds {
            print("  network-read split ms max-p95 first-byte/payload: \(firstByteP95)/\(payloadP95)")
        }
        print(
            "  request-response constraints: "
                + "\(formatTriageCounts(health.requestResponsePrimaryConstraintCounts))"
        )
        print(
            "  request-response failure labels: "
                + "\(formatTriageCounts(health.requestResponseFailureLabelCounts))"
        )
    }
    if let recommendation = report.streamShapeRecommendation {
        print("")
        print("stream-shape recommendation:")
        print("- request-response profile: \(recommendation.label)")
        print("  pacing window: \(recommendation.pacingWindow.rawValue)")
        print("  request region: \(recommendation.requestRegion.rawValue)")
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
        if let contentRequest = recommendation.contentSamplePermille,
           let contentResponse = recommendation.contentResponsePermille {
            print("  hit-rate permille content/request content/response: \(contentRequest)/\(contentResponse)")
        }
    }
    if let recommendation = report.streamShapeOrderNeutralRecommendation {
        print("")
        print("stream-shape order-neutral recommendation:")
        print("- request-response profile: \(recommendation.label)")
        print("  pacing window: \(recommendation.pacingWindow.rawValue)")
        print("  request region: \(recommendation.requestRegion.rawValue)")
        print("  reason: \(recommendation.reason)")
        if let usableRunCount = recommendation.usableRunCount,
           let runCount = recommendation.runCount {
            print("  runs usable/total: \(usableRunCount)/\(runCount)")
        }
        print(
            "  update ms avg/max-p95: "
                + "\(recommendation.averageUpdateMilliseconds)/\(recommendation.p95UpdateMilliseconds)"
        )
        print(
            "  content fps avg: \(formatFramesPerSecond(recommendation.contentFramesPerSecond)); "
                + "full-upload permille avg: \(recommendation.rendererFullUploadPermille); "
                + "slow samples: \(recommendation.slowUpdateSamples)/\(recommendation.receivedSamples)"
        )
        if let contentRequest = recommendation.contentSamplePermille,
           let contentResponse = recommendation.contentResponsePermille {
            print("  hit-rate permille content/request content/response: \(contentRequest)/\(contentResponse)")
        }
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

    print(
        "\(indentation)- status: \(summary.status.rawValue), received/attempted/requested: "
            + "\(summary.receivedSamples)/\(summary.attemptedSamples)/\(summary.requestedSamples)"
    )
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
    let phaseBudget = summary.phaseBudget
    if phaseBudget.sampleCount > 0 {
        let networkShare = phaseBudget.networkReadSharePermille.map(String.init) ?? "n/a"
        let firstByteShare = phaseBudget.firstByteWaitSharePermille.map(String.init) ?? "n/a"
        let payloadShare = phaseBudget.payloadReadSharePermille.map(String.init) ?? "n/a"
        let clientShare = phaseBudget.clientProcessingSharePermille.map(String.init) ?? "n/a"
        let loopShare = phaseBudget.requestLoopSharePermille.map(String.init) ?? "n/a"
        print(
            "\(indentation)  phase dominant/slow-dominant: "
                + "\(phaseBudget.dominantPhase.rawValue)/"
                + "\(phaseBudget.slowDominantPhase.rawValue)"
        )
        print(
            "\(indentation)  network-read subphase dominant/slow-dominant: "
                + "\((phaseBudget.networkReadDominantSubphase ?? .unknown).rawValue)/"
                + "\((phaseBudget.slowNetworkReadDominantSubphase ?? .unknown).rawValue)"
        )
        print(
            "\(indentation)  phase share permille network/client/request-loop: "
                + "\(networkShare)/\(clientShare)/\(loopShare)"
        )
        print(
            "\(indentation)  network-read split permille first-byte/payload: "
                + "\(firstByteShare)/\(payloadShare)"
        )
        if let requestLoopLatency = phaseBudget.requestLoopLatency {
            print(
                "\(indentation)  request-loop ms avg/p50/p95/min/max: "
                    + "\(requestLoopLatency.averageMilliseconds)/"
                    + "\(requestLoopLatency.p50Milliseconds)/"
                    + "\(requestLoopLatency.p95Milliseconds)/"
                    + "\(requestLoopLatency.minMilliseconds)/"
                    + "\(requestLoopLatency.maxMilliseconds)"
            )
        }
        if let firstByteLatency = phaseBudget.firstByteWaitLatency {
            print(
                "\(indentation)  first-byte wait ms avg/p50/p95/min/max: "
                    + "\(firstByteLatency.averageMilliseconds)/"
                    + "\(firstByteLatency.p50Milliseconds)/"
                    + "\(firstByteLatency.p95Milliseconds)/"
                    + "\(firstByteLatency.minMilliseconds)/"
                    + "\(firstByteLatency.maxMilliseconds)"
            )
        }
        if let payloadReadLatency = phaseBudget.payloadReadLatency {
            print(
                "\(indentation)  payload read ms avg/p50/p95/min/max: "
                    + "\(payloadReadLatency.averageMilliseconds)/"
                    + "\(payloadReadLatency.p50Milliseconds)/"
                    + "\(payloadReadLatency.p95Milliseconds)/"
                    + "\(payloadReadLatency.minMilliseconds)/"
                    + "\(payloadReadLatency.maxMilliseconds)"
            )
        }
        if phaseBudget.slowUpdateSampleCount > 0 {
            let slowNetwork = phaseBudget.slowNetworkReadSharePermille.map(String.init) ?? "n/a"
            let slowFirstByte = phaseBudget.slowFirstByteWaitSharePermille.map(String.init) ?? "n/a"
            let slowPayload = phaseBudget.slowPayloadReadSharePermille.map(String.init) ?? "n/a"
            let slowClient = phaseBudget.slowClientProcessingSharePermille.map(String.init) ?? "n/a"
            let slowLoop = phaseBudget.slowRequestLoopSharePermille.map(String.init) ?? "n/a"
            print(
                "\(indentation)  slow phase share permille network/client/request-loop: "
                    + "\(slowNetwork)/\(slowClient)/\(slowLoop)"
            )
            print(
                "\(indentation)  slow network-read split permille first-byte/payload: "
                    + "\(slowFirstByte)/\(slowPayload)"
            )
        }
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
    if let firstSlow = summary.tailLatency.firstSlowUpdateOrdinal {
        let contentOrdinal = summary.tailLatency.firstSlowContentUpdateOrdinal
            .map(String.init) ?? "n/a"
        print(
            "\(indentation)  first slow update ordinal/content ordinal: "
                + "\(firstSlow)/\(contentOrdinal)"
        )
    }
    if let firstVerySlow = summary.tailLatency.firstVerySlowUpdateOrdinal {
        let contentOrdinal = summary.tailLatency.firstVerySlowContentUpdateOrdinal
            .map(String.init) ?? "n/a"
        print(
            "\(indentation)  first very-slow update ordinal/content ordinal: "
                + "\(firstVerySlow)/\(contentOrdinal)"
        )
    }
    print("\(indentation)  empty/content/timeouts: \(summary.emptyUpdateSamples)/\(summary.contentUpdateSamples)/\(summary.timedOutSamples)")
    if let received = summary.receivedSamplePermille,
       let contentRequest = summary.contentSamplePermille,
       let contentResponse = summary.contentResponsePermille,
       let unanswered = summary.unansweredSamplePermille {
        let emptyResponse = summary.emptyResponsePermille.map(String.init) ?? "n/a"
        print(
            "\(indentation)  hit-rate permille received/request content/request content/response empty/response unanswered: "
                + "\(received)/\(contentRequest)/\(contentResponse)/\(emptyResponse)/\(unanswered)"
        )
    }
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
    if let firstByteWait = summary.firstByteWaitLatency {
        print(
            "\(indentation)  first-byte wait ms avg/p50/p95/min/max: "
                + "\(firstByteWait.averageMilliseconds)/\(firstByteWait.p50Milliseconds)/"
                + "\(firstByteWait.p95Milliseconds)/\(firstByteWait.minMilliseconds)/"
                + "\(firstByteWait.maxMilliseconds)"
        )
    }
    if let payloadRead = summary.payloadReadLatency {
        print(
            "\(indentation)  payload read ms avg/p50/p95/min/max: "
                + "\(payloadRead.averageMilliseconds)/\(payloadRead.p50Milliseconds)/"
                + "\(payloadRead.p95Milliseconds)/\(payloadRead.minMilliseconds)/"
                + "\(payloadRead.maxMilliseconds)"
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
    if let zrleInflate = summary.zrleInflateLatency {
        print(
            "\(indentation)  zrle inflate ms avg/p50/p95/min/max: "
                + "\(zrleInflate.averageMilliseconds)/\(zrleInflate.p50Milliseconds)/"
                + "\(zrleInflate.p95Milliseconds)/\(zrleInflate.minMilliseconds)/"
                + "\(zrleInflate.maxMilliseconds)"
        )
    }
    if let zrleTileApply = summary.zrleTileApplyLatency {
        print(
            "\(indentation)  zrle tile/apply ms avg/p50/p95/min/max: "
                + "\(zrleTileApply.averageMilliseconds)/\(zrleTileApply.p50Milliseconds)/"
                + "\(zrleTileApply.p95Milliseconds)/\(zrleTileApply.minMilliseconds)/"
                + "\(zrleTileApply.maxMilliseconds)"
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

private func renderText(_ report: BenchmarkLiveEnvironmentPreflightReport) {
    print("\(toolName) environment preflight")
    print("host: \(report.hostStatus.rawValue)")
    print("port: \(report.portStatus.rawValue)")
    print("credential: \(report.credentialStatus.rawValue)")
    print("stream-shape stimulus: \(report.stimulusMode.rawValue)")
    print("stimulus command: \(report.stimulusCommandStatus.rawValue)")
    print("live benchmark runnable: \(report.canRunLiveBenchmark ? "yes" : "no")")
    let issues = report.issueCodes.map(\.rawValue).joined(separator: ",")
    print("issues: \(issues.isEmpty ? "none" : issues)")
    let setupActions = report.setupActionLabels.map(\.rawValue).joined(separator: ",")
    print("setup actions: \(setupActions.isEmpty ? "none" : setupActions)")
    print("safety: target identity, credentials, port value, and stimulus command text are redacted")
}

private func renderJSON(_ report: BenchmarkLiveEnvironmentPreflightReport) throws {
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

private func formatTriageCounts(_ counts: [BenchmarkStreamShapeTriageLabelCount]) -> String {
    let formatted = counts
        .filter { $0.count > 0 }
        .map { "\($0.label)=\($0.count)" }
        .joined(separator: ", ")
    return formatted.isEmpty ? "none" : formatted
}

private func printUsage() {
    print("""
    Usage:
      swift run VNCLiveBenchmark [--environment-preflight] [--network-condition \(BenchmarkNetworkConditionProfile.usageDescription)] [--stream-shape-gate-preset \(BenchmarkStreamShapeGatePreset.usageDescription)] [--attempts N] [--full-refresh-samples N] [--stream-shape-samples N] [--stream-shape-duration-seconds SECONDS] [--stream-shape-frame-interval SECONDS] [--stream-shape-idle-frame-interval SECONDS] [--stream-shape-empty-backoff app|none] [--stream-shape-power-mode normal|low-power] [--stream-shape-client-pressure off|app] [--stream-shape-viewport-interaction off|app] [--stream-shape-stimulus off|external-command] [--stream-shape-stimulus-warmup-seconds SECONDS] [--stream-shape-stimulus-frame-interval SECONDS] [--stream-shape-preflight-frames N] [--stream-shape-practical-target iphone-practical-baseline-v1|iphone-sustained-usability-v2] [--stream-shape-viewport-interaction-pause-seconds SECONDS] [--first-frame-profiles all|local-low-latency|stream-shape-profiles|none] [--stream-shape-profiles \(BenchmarkStreamShapeProfileSelection.usageDescription(allProfileLabels: BenchmarkProfile.allCases.map(\.label)))] [--stream-shape-transport request-response|continuous-updates|both] [--stream-shape-profile-iterations N] [--stream-shape-profile-order fixed|rotate] [--stream-shape-request-region \(BenchmarkStreamShapeRequestRegion.usageDescription)] [--continuous-update-samples N] [--ask-password] [--timeout SECONDS] [--idle-timeout SECONDS] [--json]

    Options:
      --environment-preflight
                                Print a redacted live benchmark environment readiness report and exit without connecting or prompting for a password.
      --network-condition \(BenchmarkNetworkConditionProfile.usageDescription)
                                Optional benchmark-only local TCP conditioning proxy. Defaults to none. Non-none profiles emit only this fixed label and do not report proxy ports, upstream hosts, payloads, coordinates, pixels, or byte counters.
      --stream-shape-gate-preset \(BenchmarkStreamShapeGatePreset.usageDescription)
                                Apply a standard stream-shape gate configuration. sustained-v2-core sets the v2 controlled-stimulus core matrix across both transports; sustained-v2-request-response uses the same core matrix with request/response only; sustained-v2-zrle-isolation uses request/response-only ZRLE extension isolation; sustained-v2-zrle-zero-delay uses the same ZRLE isolation shape with zero post-content request delay; sustained-v2-zrle-pacing-sweep holds zrle-compression-0-clipboard constant and compares fixed request pacing windows; sustained-v2-zrle-region-sweep holds zrle-compression-0-clipboard constant and compares fixed incremental request regions; sustained-v2-zrle-viewport-region holds zrle-compression-0-clipboard constant and compares full requests against fixed phone-portrait viewport-aware regions with heartbeat/fallback candidates; sustained-v2-pixel-format uses the same gate shape with benchmark-only full-color/RGB565 profile pairs across both transports. Presets use 5 rotated iterations, app client-pressure pacing, steady-stream viewport mode, 10 second duration, 12 Hz stimulus cadence, and schema v55 network-condition plus viewport request-region area reporting. Use custom benchmark commands without a preset for active viewport-interaction experiments.
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
      --stream-shape-stimulus \(BenchmarkStreamShapeStimulusMode.usageDescription)
                                Optional dynamic-content stimulus for stream-shape probes. Defaults to off. external-command runs NARU_LIVE_STIMULUS_COMMAND once per stream-shape probe and never emits the command text or output.
      --stream-shape-stimulus-warmup-seconds SECONDS
                                Delay after launching the external stimulus before starting stream-shape samples. Defaults to 0.25 seconds.
      --stream-shape-stimulus-frame-interval SECONDS
                                Configured frame interval passed to the external stimulus child. Defaults to 0.083 seconds, i.e. a 12 Hz controlled stimulus.
      --stream-shape-preflight-frames N
                                Hidden incremental frames to consume after the first stream-shape frame and before measured samples. Defaults to 0; maximum 5.
      --stream-shape-practical-target iphone-practical-baseline-v1|iphone-sustained-usability-v2
                                Practical assessment target. Defaults to iphone-sustained-usability-v2; use v1 only for legacy artifact comparison.
      --stream-shape-viewport-interaction-pause-seconds SECONDS
                                Deprecated compatibility option; current app parity no longer pauses requests during viewport interaction.
      --first-frame-profiles all|local-low-latency|stream-shape-profiles|none
                                Profile set for first-frame/full-refresh probes. Defaults to all for compatibility; use stream-shape-profiles or none for longer stream-shape-only runs.
      --stream-shape-profiles \(BenchmarkStreamShapeProfileSelection.usageDescription(allProfileLabels: BenchmarkProfile.allCases.map(\.label)))
                                Profile set for stream-shape probes. Defaults to local-low-latency; use core-matrix for the practical baseline candidate set, zrle-isolation for ZRLE extension isolation, pixel-format-isolation for benchmark-only full-color/RGB565 pairs, all to compare every encoding profile, or a comma-separated list for targeted long runs.
      --stream-shape-transport request-response|continuous-updates|both
                                Transport mode for stream-shape probes. Defaults to request-response; use both to compare request/response with the ContinuousUpdates overlay.
      --stream-shape-profile-iterations N
                                Repeat stream-shape profile probes this many times. Defaults to 1; maximum 20.
      --stream-shape-profile-order \(BenchmarkStreamShapeProfileOrderMode.usageDescription)
                                Profile order for repeated stream-shape probes. Defaults to fixed; rotate moves a different profile to the front each iteration for order-neutral scoring.
      --stream-shape-request-region \(BenchmarkStreamShapeRequestRegion.usageDescription)
                                Fixed incremental framebuffer request region for stream-shape probes. Defaults to full. Region labels are benchmark-only and do not emit coordinates or dimensions.
      --continuous-update-samples N
                                Maximum pushed updates to sample after enabling continuous updates. Defaults to 1; use 0 to skip the standalone ContinuousUpdates probe.
      --ask-password            Prompt for the VNC password without echoing it instead of reading NARU_LIVE_MAC_PASSWORD.

    Required environment:
      NARU_LIVE_MAC_HOST       redacted from output
      NARU_LIVE_MAC_PASSWORD   redacted from output; optional when --ask-password is used
      NARU_LIVE_MAC_PORT       optional, defaults to 5900
      NARU_LIVE_STIMULUS_COMMAND
                                required only for --stream-shape-stimulus external-command; redacted from output. The child starts with a minimal launch environment plus NARU_LIVE_STIMULUS_DURATION_SECONDS, NARU_LIVE_STIMULUS_FRAME_INTERVAL_SECONDS, NARU_LIVE_STIMULUS_PROFILE_LABEL, and NARU_LIVE_STIMULUS_TRANSPORT_MODE.

    The report intentionally omits target identity, framebuffer dimensions,
    pixel payloads, byte counts, cursor pixels, and raw error descriptions.
    Stream-shape metrics emit aggregate counts and permille ratios only.
    Renderer upload metrics emit aggregate strategy counts only.
    Request-region metrics emit fixed labels only.
    """)
}

private func safeFailureLabel(for error: Error) -> String {
    BenchmarkFailureLabel.safeLabel(for: error)
}

private func safeFailureLabel(for error: Error, phase: BenchmarkFailurePhase) -> String {
    BenchmarkFailureLabel.safeLabel(for: error, phase: phase)
}
