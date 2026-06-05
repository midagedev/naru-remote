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
        viewportInteractionContentFrameInterval: TimeInterval = StreamPressurePacingDefaults.viewportInteractionContentFrameIntervalSeconds,
        emptyUpdateStreak: Int = 1
    ) -> TimeInterval {
        decision(
            for: event,
            configuredDelay: configuredDelay,
            thermalState: thermalState,
            usesPowerSaverPacing: usesPowerSaverPacing,
            usesViewportInteractionPacing: usesViewportInteractionPacing,
            viewportInteractionContentFrameInterval: viewportInteractionContentFrameInterval,
            emptyUpdateStreak: emptyUpdateStreak
        ).delay
    }

    static func decision(
        for event: SessionStreamPacingEvent,
        configuredDelay: TimeInterval,
        thermalState: SessionStreamThermalState,
        usesPowerSaverPacing: Bool = false,
        usesViewportInteractionPacing: Bool = false,
        viewportInteractionContentFrameInterval: TimeInterval = StreamPressurePacingDefaults.viewportInteractionContentFrameIntervalSeconds,
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
            usesViewportInteractionPacing: usesViewportInteractionPacing,
            contentFrameInterval: viewportInteractionContentFrameInterval
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
        usesViewportInteractionPacing: Bool,
        contentFrameInterval: TimeInterval
    ) -> TimeInterval {
        guard usesViewportInteractionPacing else {
            return 0
        }

        switch event {
        case .contentFrame:
            return max(contentFrameInterval, 0)
        case .emptyUpdate:
            return StreamPressurePacingDefaults.viewportInteractionIdleFrameIntervalSeconds
        }
    }
}

struct ViewportInteractionFramePublishPolicy: Equatable, Sendable {
    static let partialUploadContentFrameIntervalSeconds: TimeInterval =
        StreamPressurePacingDefaults.viewportInteractionPartialContentFrameIntervalSeconds
    static let fullUploadContentFrameIntervalSeconds: TimeInterval =
        StreamPressurePacingDefaults.viewportInteractionContentFrameIntervalSeconds

    static func uploadPlan(
        for frame: RFBFramePumpFrame,
        currentFramebuffer: RFBRawFramebuffer?
    ) -> FramebufferUploadPlan {
        FramebufferUploadPlan.plan(
            framebufferWidth: frame.framebuffer.width,
            framebufferHeight: frame.framebuffer.height,
            dirtyRectangles: frame.isIncremental ? frame.dirtyRectangles : nil,
            requiresTextureRecreation: currentFramebuffer.map { current in
                current.width != frame.framebuffer.width || current.height != frame.framebuffer.height
            } ?? true,
            changedPixelCount: frame.isIncremental ? frame.changedPixelCount : nil
        )
    }

    static func contentFrameInterval(for uploadPlan: FramebufferUploadPlan) -> TimeInterval {
        switch uploadPlan.strategy {
        case .partial:
            return partialUploadContentFrameIntervalSeconds
        case .full, .none:
            return fullUploadContentFrameIntervalSeconds
        }
    }

    static func shouldPublish(
        uploadPlan: FramebufferUploadPlan,
        capturedAt: Date,
        lastPublishedAt: Date?,
        interactionStartedAt: Date?
    ) -> Bool {
        if let lastPublishedAt {
            return capturedAt.timeIntervalSince(lastPublishedAt) >= contentFrameInterval(for: uploadPlan)
        }

        if uploadPlan.strategy == .partial {
            return true
        }

        guard uploadPlan.strategy == .full,
              let interactionStartedAt
        else {
            return false
        }

        return capturedAt.timeIntervalSince(interactionStartedAt)
            >= contentFrameInterval(for: uploadPlan)
    }
}
