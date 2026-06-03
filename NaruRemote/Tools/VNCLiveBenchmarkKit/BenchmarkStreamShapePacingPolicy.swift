import Foundation

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
    public static let appLaggingClientProcessingThresholdMilliseconds = 80
    public static let appConsecutiveLaggingContentFrameThreshold = 3
    public static let appClientPressureRecoveryUpdateCount = 120

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
    private var consecutiveLaggingContentFrames = 0
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
            consecutiveLaggingContentFrames = 0
            adaptiveRecoveryUpdatesRemaining = 0
            return
        }

        if adaptiveRecoveryUpdatesRemaining > 0 {
            adaptiveRecoveryUpdatesRemaining -= 1
        }

        guard sample.kind == .contentUpdate else {
            return
        }
        guard let clientProcessingMilliseconds = sample.clientProcessingMilliseconds else {
            consecutiveLaggingContentFrames = 0
            return
        }

        let laggingThreshold = BenchmarkStreamShapePacingPolicy
            .appLaggingClientProcessingThresholdMilliseconds
        if clientProcessingMilliseconds >= laggingThreshold {
            consecutiveLaggingContentFrames += 1
        } else {
            consecutiveLaggingContentFrames = 0
        }

        let activationThreshold = BenchmarkStreamShapePacingPolicy
            .appConsecutiveLaggingContentFrameThreshold
        guard consecutiveLaggingContentFrames >= activationThreshold else {
            return
        }

        adaptiveRecoveryUpdatesRemaining = max(
            adaptiveRecoveryUpdatesRemaining,
            BenchmarkStreamShapePacingPolicy.appClientPressureRecoveryUpdateCount
        )
        consecutiveLaggingContentFrames = 0
    }
}
