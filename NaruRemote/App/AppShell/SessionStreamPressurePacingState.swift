import Foundation
import NaruRemoteCore

struct SessionStreamPressurePacingState: Equatable, Sendable {
    static let severeLaggingLocalWorkThresholdMilliseconds = 80
    static let consecutiveSevereLaggingContentFrameThreshold = 3
    static let sustainedLaggingLocalWorkThresholdMilliseconds = 34
    static let consecutiveSustainedLaggingContentFrameThreshold = 8
    static let laggingClientProcessingThresholdMilliseconds = severeLaggingLocalWorkThresholdMilliseconds
    static let consecutiveLaggingContentFrameThreshold = consecutiveSevereLaggingContentFrameThreshold
    static let adaptiveRecoveryUpdateCount = 120

    private var consecutiveSevereLaggingContentFrames = 0
    private var consecutiveSustainedLaggingContentFrames = 0
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
            resetLaggingContentStreaks()
            return
        }

        if isEmptyIncrementalUpdate(frame) {
            return
        }

        let clientProcessingMilliseconds = frame.timing?.clientProcessingMilliseconds
        let appFrameApplyMilliseconds = appFrameApplyMilliseconds.map { max($0, 0) }
        guard clientProcessingMilliseconds != nil || appFrameApplyMilliseconds != nil else {
            resetLaggingContentStreaks()
            return
        }

        let localWorkMilliseconds = max(
            clientProcessingMilliseconds ?? 0,
            appFrameApplyMilliseconds ?? 0
        )

        if localWorkMilliseconds >= Self.sustainedLaggingLocalWorkThresholdMilliseconds {
            consecutiveSustainedLaggingContentFrames += 1
        } else {
            resetLaggingContentStreaks()
            return
        }

        if localWorkMilliseconds >= Self.severeLaggingLocalWorkThresholdMilliseconds {
            consecutiveSevereLaggingContentFrames += 1
        } else {
            consecutiveSevereLaggingContentFrames = 0
        }

        guard consecutiveSevereLaggingContentFrames >= Self.consecutiveSevereLaggingContentFrameThreshold
            || consecutiveSustainedLaggingContentFrames >= Self.consecutiveSustainedLaggingContentFrameThreshold
        else {
            return
        }
        adaptiveRecoveryUpdatesRemaining = max(
            adaptiveRecoveryUpdatesRemaining,
            Self.adaptiveRecoveryUpdateCount
        )
        resetLaggingContentStreaks()
    }

    private func isEmptyIncrementalUpdate(_ frame: RFBFramePumpFrame) -> Bool {
        frame.isIncremental && frame.changedPixelCount == 0
    }

    private mutating func resetLaggingContentStreaks() {
        consecutiveSevereLaggingContentFrames = 0
        consecutiveSustainedLaggingContentFrames = 0
    }
}
