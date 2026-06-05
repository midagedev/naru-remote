import Foundation
import NaruRemoteCore

public enum BenchmarkStreamShapeEmptyBackoffMode: String, Codable, Equatable, Sendable {
    case app
    case none
}

public enum BenchmarkStreamShapePowerMode: String, Codable, Equatable, Sendable {
    case normal
    case lowPower = "low-power"
}

public enum BenchmarkStreamShapeClientPressureMode: String, Codable, Equatable, Sendable {
    case off
    case app
}

public enum BenchmarkStreamShapeViewportInteractionMode: String, Codable, Equatable, Sendable {
    case off
    case app
}

public struct BenchmarkStreamShapePacingDecision: Equatable, Sendable {
    public let delay: TimeInterval
    public let usesViewportInteractionPacing: Bool

    public init(delay: TimeInterval, usesViewportInteractionPacing: Bool) {
        self.delay = max(delay, 0)
        self.usesViewportInteractionPacing = usesViewportInteractionPacing
    }
}

public struct BenchmarkStreamShapeViewportRequestPauseDecision: Equatable, Sendable {
    public let delay: TimeInterval
    public let pollInterval: TimeInterval

    public init(delay: TimeInterval, pollInterval: TimeInterval) {
        self.delay = max(delay, 0)
        self.pollInterval = max(pollInterval, 0)
    }

    public var shouldPause: Bool {
        delay > 0 && pollInterval > 0
    }
}

public struct BenchmarkStreamShapePacingPolicy: Codable, Equatable, Sendable {
    public static let appBalancedContentFrameInterval = StreamPressurePacingDefaults
        .balancedContentFrameIntervalSeconds
    public static let appMediumEmptyUpdateStreakThreshold = 8
    public static let appLongEmptyUpdateStreakThreshold = 24
    public static let appMediumIdleFrameInterval: TimeInterval = 0.075
    public static let appLongIdleFrameInterval: TimeInterval = 0.125
    public static let appLowPowerContentFrameInterval: TimeInterval = 1.0 / 30.0
    public static let appLowPowerIdleFrameInterval: TimeInterval = 0.125
    public static let appSevereLaggingClientProcessingThresholdMilliseconds = StreamPressurePacingDefaults
        .severeLaggingLocalWorkThresholdMilliseconds
    public static let appConsecutiveSevereLaggingContentFrameThreshold = StreamPressurePacingDefaults
        .consecutiveSevereLaggingContentFrameThreshold
    public static let appSustainedLaggingClientProcessingThresholdMilliseconds = StreamPressurePacingDefaults
        .sustainedLaggingLocalWorkThresholdMilliseconds
    public static let appConsecutiveSustainedLaggingContentFrameThreshold = StreamPressurePacingDefaults
        .consecutiveSustainedLaggingContentFrameThreshold
    public static let appConsecutiveFullUploadContentFrameThreshold = StreamPressurePacingDefaults
        .consecutiveFullUploadContentFrameThreshold
    public static let appLaggingClientProcessingThresholdMilliseconds =
        appSevereLaggingClientProcessingThresholdMilliseconds
    public static let appConsecutiveLaggingContentFrameThreshold =
        appConsecutiveSevereLaggingContentFrameThreshold
    public static let appClientPressureRecoveryUpdateCount = StreamPressurePacingDefaults
        .adaptiveRecoveryUpdateCount
    public static let appViewportInteractionContentFrameInterval: TimeInterval = StreamPressurePacingDefaults
        .viewportInteractionContentFrameIntervalSeconds
    public static let appViewportInteractionIdleFrameInterval: TimeInterval = StreamPressurePacingDefaults
        .viewportInteractionIdleFrameIntervalSeconds
    public static let appViewportInteractionRequestPausePollInterval: TimeInterval = StreamPressurePacingDefaults
        .viewportInteractionRequestPausePollSeconds
    public static let appViewportInteractionSyntheticPauseSeconds: TimeInterval = StreamPressurePacingDefaults
        .viewportInteractionIdleFrameIntervalSeconds
    private static let pacingFloorComparisonTolerance: TimeInterval = 0.000_001

    public let contentFrameInterval: TimeInterval
    public let idleFrameInterval: TimeInterval
    public let emptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode
    public let powerMode: BenchmarkStreamShapePowerMode
    public let clientPressureMode: BenchmarkStreamShapeClientPressureMode
    public let viewportInteractionMode: BenchmarkStreamShapeViewportInteractionMode

    private enum CodingKeys: String, CodingKey {
        case contentFrameInterval
        case idleFrameInterval
        case emptyBackoffMode
        case powerMode
        case clientPressureMode
        case viewportInteractionMode
    }

    public init(
        contentFrameInterval: TimeInterval,
        idleFrameInterval: TimeInterval,
        emptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode = .app,
        powerMode: BenchmarkStreamShapePowerMode = .normal,
        clientPressureMode: BenchmarkStreamShapeClientPressureMode = .off,
        viewportInteractionMode: BenchmarkStreamShapeViewportInteractionMode = .off
    ) {
        self.contentFrameInterval = max(contentFrameInterval, 0)
        self.idleFrameInterval = max(idleFrameInterval, 0)
        self.emptyBackoffMode = emptyBackoffMode
        self.powerMode = powerMode
        self.clientPressureMode = clientPressureMode
        self.viewportInteractionMode = viewportInteractionMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            contentFrameInterval: try container.decode(TimeInterval.self, forKey: .contentFrameInterval),
            idleFrameInterval: try container.decode(TimeInterval.self, forKey: .idleFrameInterval),
            emptyBackoffMode: try container.decodeIfPresent(
                BenchmarkStreamShapeEmptyBackoffMode.self,
                forKey: .emptyBackoffMode
            ) ?? .app,
            powerMode: try container.decodeIfPresent(BenchmarkStreamShapePowerMode.self, forKey: .powerMode)
                ?? .normal,
            clientPressureMode: try container.decodeIfPresent(
                BenchmarkStreamShapeClientPressureMode.self,
                forKey: .clientPressureMode
            ) ?? .off,
            viewportInteractionMode: try container.decodeIfPresent(
                BenchmarkStreamShapeViewportInteractionMode.self,
                forKey: .viewportInteractionMode
            ) ?? .off
        )
    }

    public func delay(
        isEmptyUpdate: Bool,
        emptyUpdateStreak: Int,
        usesAdaptiveClientPressure: Bool = false
    ) -> TimeInterval {
        decision(
            isEmptyUpdate: isEmptyUpdate,
            emptyUpdateStreak: emptyUpdateStreak,
            usesAdaptiveClientPressure: usesAdaptiveClientPressure
        ).delay
    }

    public func decision(
        isEmptyUpdate: Bool,
        emptyUpdateStreak: Int,
        usesAdaptiveClientPressure: Bool = false
    ) -> BenchmarkStreamShapePacingDecision {
        guard isEmptyUpdate else {
            guard contentFrameInterval > 0 else {
                return BenchmarkStreamShapePacingDecision(
                    delay: 0,
                    usesViewportInteractionPacing: false
                )
            }
            return decision(
                configuredDelay: contentFrameInterval,
                powerSaverDelayFloor: powerSaverDelayFloor(
                    isEmptyUpdate: false,
                    usesAdaptiveClientPressure: usesAdaptiveClientPressure
                ),
                viewportInteractionDelayFloor: viewportInteractionDelayFloor(isEmptyUpdate: false)
            )
        }
        guard idleFrameInterval > 0 else {
            return BenchmarkStreamShapePacingDecision(
                delay: 0,
                usesViewportInteractionPacing: false
            )
        }

        let configuredDelay = if emptyBackoffMode == .app {
            switch max(emptyUpdateStreak, 0) {
            case 0..<Self.appMediumEmptyUpdateStreakThreshold:
                idleFrameInterval
            case Self.appMediumEmptyUpdateStreakThreshold..<Self.appLongEmptyUpdateStreakThreshold:
                max(idleFrameInterval, Self.appMediumIdleFrameInterval)
            default:
                max(idleFrameInterval, Self.appLongIdleFrameInterval)
            }
        } else {
            idleFrameInterval
        }
        return decision(
            configuredDelay: configuredDelay,
            powerSaverDelayFloor: powerSaverDelayFloor(
                isEmptyUpdate: true,
                usesAdaptiveClientPressure: usesAdaptiveClientPressure
            ),
            viewportInteractionDelayFloor: viewportInteractionDelayFloor(isEmptyUpdate: true)
        )
    }

    public func viewportInteractionRequestPauseDecision(
        visibleFrameAvailable: Bool,
        configuredPauseSeconds: TimeInterval = Self.appViewportInteractionSyntheticPauseSeconds
    ) -> BenchmarkStreamShapeViewportRequestPauseDecision {
        guard viewportInteractionMode == .app,
              visibleFrameAvailable,
              configuredPauseSeconds > 0
        else {
            return BenchmarkStreamShapeViewportRequestPauseDecision(delay: 0, pollInterval: 0)
        }

        return BenchmarkStreamShapeViewportRequestPauseDecision(
            delay: configuredPauseSeconds,
            pollInterval: Self.appViewportInteractionRequestPausePollInterval
        )
    }

    private func decision(
        configuredDelay: TimeInterval,
        powerSaverDelayFloor: TimeInterval,
        viewportInteractionDelayFloor: TimeInterval
    ) -> BenchmarkStreamShapePacingDecision {
        let effectiveDelay = max(
            configuredDelay,
            powerSaverDelayFloor,
            viewportInteractionDelayFloor
        )
        return BenchmarkStreamShapePacingDecision(
            delay: effectiveDelay,
            usesViewportInteractionPacing: viewportInteractionDelayFloor > 0
                && abs(viewportInteractionDelayFloor - effectiveDelay) <= Self.pacingFloorComparisonTolerance
        )
    }

    private func powerSaverDelayFloor(
        isEmptyUpdate: Bool,
        usesAdaptiveClientPressure: Bool
    ) -> TimeInterval {
        guard powerMode == .lowPower || usesAdaptiveClientPressure else {
            return 0
        }
        return isEmptyUpdate ? Self.appLowPowerIdleFrameInterval : Self.appLowPowerContentFrameInterval
    }

    private func viewportInteractionDelayFloor(isEmptyUpdate _: Bool) -> TimeInterval {
        0
    }
}

public struct BenchmarkStreamShapeClientPressureState: Equatable, Sendable {
    private var consecutiveSevereLaggingContentFrames = 0
    private var consecutiveSustainedLaggingContentFrames = 0
    private var consecutiveFullUploadContentFrames = 0
    private var adaptiveRecoveryUpdatesRemaining = 0

    public init() {}

    public var usesAdaptivePowerSaverPacing: Bool {
        adaptiveRecoveryUpdatesRemaining > 0
    }

    public mutating func record(
        sample: BenchmarkStreamShapeSample,
        mode: BenchmarkStreamShapeClientPressureMode
    ) {
        guard mode == .app else {
            resetContentPressureStreaks()
            adaptiveRecoveryUpdatesRemaining = 0
            return
        }

        if adaptiveRecoveryUpdatesRemaining > 0 {
            adaptiveRecoveryUpdatesRemaining -= 1
        }

        guard sample.kind == .contentUpdate else {
            return
        }
        if sample.rendererUploadStrategy == .full {
            consecutiveFullUploadContentFrames += 1
        } else {
            consecutiveFullUploadContentFrames = 0
        }

        guard let clientProcessingMilliseconds = sample.clientProcessingMilliseconds else {
            activatePowerSaverPacingIfNeeded()
            if !usesAdaptivePowerSaverPacing {
                resetLaggingContentStreaks()
            }
            return
        }

        let sustainedLaggingThreshold = BenchmarkStreamShapePacingPolicy
            .appSustainedLaggingClientProcessingThresholdMilliseconds
        if clientProcessingMilliseconds >= sustainedLaggingThreshold {
            consecutiveSustainedLaggingContentFrames += 1
        } else {
            resetLaggingContentStreaks()
            return
        }

        let severeLaggingThreshold = BenchmarkStreamShapePacingPolicy
            .appSevereLaggingClientProcessingThresholdMilliseconds
        if clientProcessingMilliseconds >= severeLaggingThreshold {
            consecutiveSevereLaggingContentFrames += 1
        } else {
            consecutiveSevereLaggingContentFrames = 0
        }

        activatePowerSaverPacingIfNeeded()
    }

    private mutating func activatePowerSaverPacingIfNeeded() {
        let severeActivationThreshold = BenchmarkStreamShapePacingPolicy
            .appConsecutiveSevereLaggingContentFrameThreshold
        let sustainedActivationThreshold = BenchmarkStreamShapePacingPolicy
            .appConsecutiveSustainedLaggingContentFrameThreshold
        let fullUploadActivationThreshold = BenchmarkStreamShapePacingPolicy
            .appConsecutiveFullUploadContentFrameThreshold
        guard consecutiveSevereLaggingContentFrames >= severeActivationThreshold
            || consecutiveSustainedLaggingContentFrames >= sustainedActivationThreshold
            || consecutiveFullUploadContentFrames >= fullUploadActivationThreshold
        else {
            return
        }

        adaptiveRecoveryUpdatesRemaining = max(
            adaptiveRecoveryUpdatesRemaining,
            BenchmarkStreamShapePacingPolicy.appClientPressureRecoveryUpdateCount
        )
        resetContentPressureStreaks()
    }

    private mutating func resetLaggingContentStreaks() {
        consecutiveSevereLaggingContentFrames = 0
        consecutiveSustainedLaggingContentFrames = 0
    }

    private mutating func resetContentPressureStreaks() {
        resetLaggingContentStreaks()
        consecutiveFullUploadContentFrames = 0
    }
}
