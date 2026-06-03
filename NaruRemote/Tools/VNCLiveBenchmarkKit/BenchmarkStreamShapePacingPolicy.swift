import Foundation

public enum BenchmarkStreamShapeEmptyBackoffMode: String, Codable, Equatable, Sendable {
    case app
    case none
}

public struct BenchmarkStreamShapePacingPolicy: Codable, Equatable, Sendable {
    public static let appMediumEmptyUpdateStreakThreshold = 8
    public static let appLongEmptyUpdateStreakThreshold = 24
    public static let appMediumIdleFrameInterval: TimeInterval = 0.075
    public static let appLongIdleFrameInterval: TimeInterval = 0.125

    public let contentFrameInterval: TimeInterval
    public let idleFrameInterval: TimeInterval
    public let emptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode

    public init(
        contentFrameInterval: TimeInterval,
        idleFrameInterval: TimeInterval,
        emptyBackoffMode: BenchmarkStreamShapeEmptyBackoffMode = .app
    ) {
        self.contentFrameInterval = max(contentFrameInterval, 0)
        self.idleFrameInterval = max(idleFrameInterval, 0)
        self.emptyBackoffMode = emptyBackoffMode
    }

    public func delay(isEmptyUpdate: Bool, emptyUpdateStreak: Int) -> TimeInterval {
        guard isEmptyUpdate else {
            return contentFrameInterval
        }
        guard idleFrameInterval > 0 else {
            return 0
        }
        guard emptyBackoffMode == .app else {
            return idleFrameInterval
        }

        switch max(emptyUpdateStreak, 0) {
        case 0..<Self.appMediumEmptyUpdateStreakThreshold:
            return idleFrameInterval
        case Self.appMediumEmptyUpdateStreakThreshold..<Self.appLongEmptyUpdateStreakThreshold:
            return max(idleFrameInterval, Self.appMediumIdleFrameInterval)
        default:
            return max(idleFrameInterval, Self.appLongIdleFrameInterval)
        }
    }
}
