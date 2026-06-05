import Foundation
import NaruRemoteCore

struct SessionStreamPressurePacingState: Equatable, Sendable {
    static let severeLaggingLocalWorkThresholdMilliseconds = StreamPressurePacingDefaults
        .severeLaggingLocalWorkThresholdMilliseconds
    static let consecutiveSevereLaggingContentFrameThreshold = StreamPressurePacingDefaults
        .consecutiveSevereLaggingContentFrameThreshold
    static let sustainedLaggingLocalWorkThresholdMilliseconds = StreamPressurePacingDefaults
        .sustainedLaggingLocalWorkThresholdMilliseconds
    static let verySlowLocalWorkThresholdMilliseconds = StreamPressurePacingDefaults
        .verySlowLocalWorkThresholdMilliseconds
    static let consecutiveSustainedLaggingContentFrameThreshold = StreamPressurePacingDefaults
        .consecutiveSustainedLaggingContentFrameThreshold
    static let consecutiveFullUploadContentFrameThreshold = StreamPressurePacingDefaults
        .consecutiveFullUploadContentFrameThreshold
    static let laggingClientProcessingThresholdMilliseconds = severeLaggingLocalWorkThresholdMilliseconds
    static let consecutiveLaggingContentFrameThreshold = consecutiveSevereLaggingContentFrameThreshold
    static let verySlowAdaptiveRecoveryUpdateCount = StreamPressurePacingDefaults
        .verySlowAdaptiveRecoveryUpdateCount
    static let adaptiveRecoveryUpdateCount = StreamPressurePacingDefaults.adaptiveRecoveryUpdateCount

    private var consecutiveSevereLaggingContentFrames = 0
    private var consecutiveSustainedLaggingContentFrames = 0
    private var consecutiveFullUploadContentFrames = 0
    private var adaptiveRecoveryUpdatesRemaining = 0

    var usesAdaptivePowerSaverPacing: Bool {
        adaptiveRecoveryUpdatesRemaining > 0
    }

    mutating func record(
        frame: RFBFramePumpFrame,
        appFrameApplyMilliseconds: Int? = nil
    ) {
        // Recovery is bounded by update decisions, not content frames,
        // so a static screen does not keep adaptive pacing enabled forever.
        if adaptiveRecoveryUpdatesRemaining > 0 {
            adaptiveRecoveryUpdatesRemaining -= 1
        }

        if frame.transportIdleTimedOut {
            resetContentPressureStreaks()
            return
        }

        if isEmptyIncrementalUpdate(frame) {
            return
        }

        if requiresFullRendererUpload(frame) {
            consecutiveFullUploadContentFrames += 1
        } else {
            consecutiveFullUploadContentFrames = 0
        }

        let clientProcessingMilliseconds = frame.timing?.clientProcessingMilliseconds
        let appFrameApplyMilliseconds = appFrameApplyMilliseconds.map { max($0, 0) }
        guard clientProcessingMilliseconds != nil || appFrameApplyMilliseconds != nil else {
            activatePowerSaverPacingIfNeeded()
            if !usesAdaptivePowerSaverPacing {
                resetLaggingContentStreaks()
            }
            return
        }

        let localWorkMilliseconds = max(
            clientProcessingMilliseconds ?? 0,
            appFrameApplyMilliseconds ?? 0
        )

        if localWorkMilliseconds >= Self.verySlowLocalWorkThresholdMilliseconds {
            activatePowerSaverPacing(recoveryUpdateCount: Self.verySlowAdaptiveRecoveryUpdateCount)
            return
        }

        if localWorkMilliseconds >= Self.sustainedLaggingLocalWorkThresholdMilliseconds {
            consecutiveSustainedLaggingContentFrames += 1
        } else {
            resetLaggingContentStreaks()
            activatePowerSaverPacingIfNeeded()
            return
        }

        if localWorkMilliseconds >= Self.severeLaggingLocalWorkThresholdMilliseconds {
            consecutiveSevereLaggingContentFrames += 1
        } else {
            consecutiveSevereLaggingContentFrames = 0
        }

        activatePowerSaverPacingIfNeeded()
    }

    private func isEmptyIncrementalUpdate(_ frame: RFBFramePumpFrame) -> Bool {
        frame.isIncremental && frame.changedPixelCount == 0
    }

    private func requiresFullRendererUpload(_ frame: RFBFramePumpFrame) -> Bool {
        guard frame.isIncremental,
              frame.changedPixelCount > 0,
              frame.framebuffer.width > 0,
              frame.framebuffer.height > 0
        else {
            return false
        }
        return FramebufferUploadPlan.plan(
            framebufferWidth: frame.framebuffer.width,
            framebufferHeight: frame.framebuffer.height,
            dirtyRectangles: frame.dirtyRectangles,
            requiresTextureRecreation: false,
            changedPixelCount: frame.changedPixelCount
        ).strategy == .full
    }

    private mutating func activatePowerSaverPacingIfNeeded() {
        guard consecutiveSevereLaggingContentFrames >= Self.consecutiveSevereLaggingContentFrameThreshold
            || consecutiveSustainedLaggingContentFrames >= Self.consecutiveSustainedLaggingContentFrameThreshold
            || consecutiveFullUploadContentFrames >= Self.consecutiveFullUploadContentFrameThreshold
        else {
            return
        }
        activatePowerSaverPacing(recoveryUpdateCount: Self.adaptiveRecoveryUpdateCount)
    }

    private mutating func activatePowerSaverPacing(recoveryUpdateCount: Int) {
        adaptiveRecoveryUpdatesRemaining = max(
            adaptiveRecoveryUpdatesRemaining,
            recoveryUpdateCount
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
