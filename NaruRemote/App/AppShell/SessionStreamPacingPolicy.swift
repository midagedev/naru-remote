import Foundation

enum SessionStreamPacingEvent: Equatable, Sendable {
    case contentFrame
    case emptyUpdate
}

struct SessionStreamPacingPolicy: Equatable, Sendable {
    private static let mediumEmptyUpdateStreakThreshold = 8
    private static let longEmptyUpdateStreakThreshold = 24
    private static let mediumEmptyUpdateDelay: TimeInterval = 0.075
    private static let longEmptyUpdateDelay: TimeInterval = 0.125

    static func delay(
        for event: SessionStreamPacingEvent,
        configuredDelay: TimeInterval,
        thermalState: SessionStreamThermalState,
        emptyUpdateStreak: Int = 1
    ) -> TimeInterval {
        let configuredDelay = max(configuredDelay, 0)
        guard configuredDelay > 0 else {
            return 0
        }

        let configuredDelayWithBackoff = backoffDelay(
            for: event,
            configuredDelay: configuredDelay,
            emptyUpdateStreak: emptyUpdateStreak
        )
        let thermalMinimum = minimumDelay(for: event, thermalState: thermalState)
        return max(configuredDelayWithBackoff, thermalMinimum)
    }

    private static func backoffDelay(
        for event: SessionStreamPacingEvent,
        configuredDelay: TimeInterval,
        emptyUpdateStreak: Int
    ) -> TimeInterval {
        guard event == .emptyUpdate else {
            return configuredDelay
        }

        switch max(emptyUpdateStreak, 0) {
        case 0..<mediumEmptyUpdateStreakThreshold:
            return configuredDelay
        case mediumEmptyUpdateStreakThreshold..<longEmptyUpdateStreakThreshold:
            return max(configuredDelay, mediumEmptyUpdateDelay)
        default:
            return max(configuredDelay, longEmptyUpdateDelay)
        }
    }

    private static func minimumDelay(
        for event: SessionStreamPacingEvent,
        thermalState: SessionStreamThermalState
    ) -> TimeInterval {
        switch event {
        case .contentFrame:
            return minimumContentFrameDelay(for: thermalState)
        case .emptyUpdate:
            return minimumEmptyUpdateDelay(for: thermalState)
        }
    }

    private static func minimumContentFrameDelay(
        for thermalState: SessionStreamThermalState
    ) -> TimeInterval {
        switch thermalState {
        case .unknown, .nominal:
            return 0
        case .fair:
            return 1.0 / 24.0
        case .serious:
            return 1.0 / 15.0
        case .critical:
            return 1.0 / 8.0
        }
    }

    private static func minimumEmptyUpdateDelay(
        for thermalState: SessionStreamThermalState
    ) -> TimeInterval {
        switch thermalState {
        case .unknown, .nominal:
            return 0
        case .fair:
            return 0.075
        case .serious:
            return 0.125
        case .critical:
            return 0.25
        }
    }
}
