import Foundation
import NaruRemoteCore

struct SessionStreamPressurePacingState: Equatable, Sendable {
    static let laggingClientProcessingThresholdMilliseconds = 80
    static let consecutiveLaggingContentFrameThreshold = 3
    static let adaptiveRecoveryUpdateCount = 120

    private var consecutiveLaggingContentFrames = 0
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
            consecutiveLaggingContentFrames = 0
            return
        }

        if isEmptyIncrementalUpdate(frame) {
            return
        }

        let clientProcessingMilliseconds = frame.timing?.clientProcessingMilliseconds
        let appFrameApplyMilliseconds = appFrameApplyMilliseconds.map { max($0, 0) }
        guard clientProcessingMilliseconds != nil || appFrameApplyMilliseconds != nil else {
            consecutiveLaggingContentFrames = 0
            return
        }

        let hasLaggingLocalWork =
            clientProcessingMilliseconds.map { $0 >= Self.laggingClientProcessingThresholdMilliseconds } ?? false
            || appFrameApplyMilliseconds.map { $0 >= Self.laggingClientProcessingThresholdMilliseconds } ?? false

        if hasLaggingLocalWork {
            consecutiveLaggingContentFrames += 1
        } else {
            consecutiveLaggingContentFrames = 0
        }

        guard consecutiveLaggingContentFrames >= Self.consecutiveLaggingContentFrameThreshold else {
            return
        }
        adaptiveRecoveryUpdatesRemaining = max(
            adaptiveRecoveryUpdatesRemaining,
            Self.adaptiveRecoveryUpdateCount
        )
        consecutiveLaggingContentFrames = 0
    }

    private func isEmptyIncrementalUpdate(_ frame: RFBFramePumpFrame) -> Bool {
        frame.isIncremental && frame.changedPixelCount == 0
    }
}
