import Foundation
import NaruRemoteCore

enum SessionStreamPacingEvent: Equatable, Sendable {
    case contentFrame
    case emptyUpdate
}

struct SessionStreamPacingDecision: Equatable, Sendable {
    var delay: TimeInterval
    var usesThermalPacing: Bool
    var usesPowerSaverPacing: Bool
    var usesEmptyBackoffPacing: Bool
    var usesViewportInteractionPacing: Bool = false
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
        usesPowerSaverPacing: Bool = false,
        usesViewportInteractionPacing: Bool = false,
        emptyUpdateStreak: Int = 1
    ) -> TimeInterval {
        decision(
            for: event,
            configuredDelay: configuredDelay,
            thermalState: thermalState,
            usesPowerSaverPacing: usesPowerSaverPacing,
            usesViewportInteractionPacing: usesViewportInteractionPacing,
            emptyUpdateStreak: emptyUpdateStreak
        ).delay
    }

    static func decision(
        for event: SessionStreamPacingEvent,
        configuredDelay: TimeInterval,
        thermalState: SessionStreamThermalState,
        usesPowerSaverPacing: Bool = false,
        usesViewportInteractionPacing: Bool = false,
        emptyUpdateStreak: Int = 1
    ) -> SessionStreamPacingDecision {
        let configuredDelay = max(configuredDelay, 0)
        guard configuredDelay > 0 else {
            // Explicit zero-delay streams are opt-in deterministic
            // fake/test paths; they bypass thermal and low-power floors.
            return SessionStreamPacingDecision(
                delay: 0,
                usesThermalPacing: false,
                usesPowerSaverPacing: false,
                usesEmptyBackoffPacing: false,
                usesViewportInteractionPacing: false
            )
        }

        let configuredDelayWithBackoff = backoffDelay(
            for: event,
            configuredDelay: configuredDelay,
            emptyUpdateStreak: emptyUpdateStreak
        )
        let thermalMinimum = minimumDelay(for: event, thermalState: thermalState)
        let powerSaverMinimum = minimumDelayForPowerSaverMode(
            for: event,
            usesPowerSaverPacing: usesPowerSaverPacing
        )
        let viewportInteractionMinimum = minimumDelayForViewportInteraction(
            for: event,
            usesViewportInteractionPacing: usesViewportInteractionPacing
        )
        let effectiveDelay = max(
            configuredDelayWithBackoff,
            thermalMinimum,
            powerSaverMinimum,
            viewportInteractionMinimum
        )
        return SessionStreamPacingDecision(
            delay: effectiveDelay,
            usesThermalPacing: thermalMinimum > 0 && thermalMinimum == effectiveDelay,
            usesPowerSaverPacing: powerSaverMinimum > 0 && powerSaverMinimum == effectiveDelay,
            usesEmptyBackoffPacing: configuredDelayWithBackoff > configuredDelay
                && configuredDelayWithBackoff == effectiveDelay,
            usesViewportInteractionPacing: viewportInteractionMinimum > 0
                && viewportInteractionMinimum == effectiveDelay
        )
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

    private static func minimumDelayForPowerSaverMode(
        for event: SessionStreamPacingEvent,
        usesPowerSaverPacing: Bool
    ) -> TimeInterval {
        guard usesPowerSaverPacing else {
            return 0
        }

        switch event {
        case .contentFrame:
            return 1.0 / 30.0
        case .emptyUpdate:
            return 0.125
        }
    }

    private static func minimumDelayForViewportInteraction(
        for event: SessionStreamPacingEvent,
        usesViewportInteractionPacing: Bool
    ) -> TimeInterval {
        guard usesViewportInteractionPacing else {
            return 0
        }

        switch event {
        case .contentFrame:
            return StreamPressurePacingDefaults.viewportInteractionContentFrameIntervalSeconds
        case .emptyUpdate:
            return StreamPressurePacingDefaults.viewportInteractionIdleFrameIntervalSeconds
        }
    }
}
