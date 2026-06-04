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

public struct BenchmarkStreamShapePacingPolicy: Codable, Equatable, Sendable {
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

    public let contentFrameInterval: TimeInterval
    public let idleFrameInterval: TimeInterval
    public let emptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode
    public let powerMode: BenchmarkStreamShapePowerMode
    public let clientPressureMode: BenchmarkStreamShapeClientPressureMode

    public init(
        contentFrameInterval: TimeInterval,
        idleFrameInterval: TimeInterval,
        emptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode = .app,
        powerMode: BenchmarkStreamShapePowerMode = .normal,
        clientPressureMode: BenchmarkStreamShapeClientPressureMode = .off
    ) {
        self.contentFrameInterval = max(contentFrameInterval, 0)
        self.idleFrameInterval = max(idleFrameInterval, 0)
        self.emptyBackoffMode = emptyBackoffMode
        self.powerMode = powerMode
        self.clientPressureMode = clientPressureMode
    }

    public func delay(
        isEmptyUpdate: Bool,
        emptyUpdateStreak: Int,
        usesAdaptiveClientPressure: Bool = false
    ) -> TimeInterval {
        guard isEmptyUpdate else {
            guard contentFrameInterval > 0 else {
                return 0
            }
            return max(
                contentFrameInterval,
                powerSaverDelayFloor(
                    isEmptyUpdate: false,
                    usesAdaptiveClientPressure: usesAdaptiveClientPressure
                )
            )
        }
        guard idleFrameInterval > 0 else {
            return 0
        }
        guard emptyBackoffMode == .app else {
            return max(
                idleFrameInterval,
                powerSaverDelayFloor(
                    isEmptyUpdate: true,
                    usesAdaptiveClientPressure: usesAdaptiveClientPressure
                )
            )
        }

        let backoffDelay = switch max(emptyUpdateStreak, 0) {
        case 0..<Self.appMediumEmptyUpdateStreakThreshold:
            idleFrameInterval
        case Self.appMediumEmptyUpdateStreakThreshold..<Self.appLongEmptyUpdateStreakThreshold:
            max(idleFrameInterval, Self.appMediumIdleFrameInterval)
        default:
            max(idleFrameInterval, Self.appLongIdleFrameInterval)
        }
        return max(
            backoffDelay,
            powerSaverDelayFloor(
                isEmptyUpdate: true,
                usesAdaptiveClientPressure: usesAdaptiveClientPressure
            )
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
