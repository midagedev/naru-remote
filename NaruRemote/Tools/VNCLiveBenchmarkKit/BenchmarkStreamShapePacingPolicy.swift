import Foundation

public enum BenchmarkStreamShapeEmptyBackoffMode: String, Codable, Equatable, Sendable {
    case app
    case none
}

public enum BenchmarkStreamShapePowerMode: String, Codable, Equatable, Sendable {
    case normal
    case lowPower = "low-power"
}

public struct BenchmarkStreamShapePacingPolicy: Codable, Equatable, Sendable {
    public static let appMediumEmptyUpdateStreakThreshold = 8
    public static let appLongEmptyUpdateStreakThreshold = 24
    public static let appMediumIdleFrameInterval: TimeInterval = 0.075
    public static let appLongIdleFrameInterval: TimeInterval = 0.125
    public static let appLowPowerContentFrameInterval: TimeInterval = 1.0 / 30.0
    public static let appLowPowerIdleFrameInterval: TimeInterval = 0.125

    public let contentFrameInterval: TimeInterval
    public let idleFrameInterval: TimeInterval
    public let emptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode
    public let powerMode: BenchmarkStreamShapePowerMode

    public init(
        contentFrameInterval: TimeInterval,
        idleFrameInterval: TimeInterval,
        emptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode = .app,
        powerMode: BenchmarkStreamShapePowerMode = .normal
    ) {
        self.contentFrameInterval = max(contentFrameInterval, 0)
        self.idleFrameInterval = max(idleFrameInterval, 0)
        self.emptyBackoffMode = emptyBackoffMode
        self.powerMode = powerMode
    }

    public func delay(isEmptyUpdate: Bool, emptyUpdateStreak: Int) -> TimeInterval {
        guard isEmptyUpdate else {
            guard contentFrameInterval > 0 else {
                return 0
            }
            return max(contentFrameInterval, lowPowerDelayFloor(isEmptyUpdate: false))
        }
        guard idleFrameInterval > 0 else {
            return 0
        }
        guard emptyBackoffMode == .app else {
            return max(idleFrameInterval, lowPowerDelayFloor(isEmptyUpdate: true))
        }

        let backoffDelay = switch max(emptyUpdateStreak, 0) {
        case 0..<Self.appMediumEmptyUpdateStreakThreshold:
            idleFrameInterval
        case Self.appMediumEmptyUpdateStreakThreshold..<Self.appLongEmptyUpdateStreakThreshold:
            max(idleFrameInterval, Self.appMediumIdleFrameInterval)
        default:
            max(idleFrameInterval, Self.appLongIdleFrameInterval)
        }
        return max(backoffDelay, lowPowerDelayFloor(isEmptyUpdate: true))
    }

    private func lowPowerDelayFloor(isEmptyUpdate: Bool) -> TimeInterval {
        guard powerMode == .lowPower else {
            return 0
        }
        return isEmptyUpdate ? Self.appLowPowerIdleFrameInterval : Self.appLowPowerContentFrameInterval
    }
}
