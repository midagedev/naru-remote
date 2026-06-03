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

    mutating func record(frame: RFBFramePumpFrame) {
        // Recovery is bounded by update decisions, not content frames,
        // so a static screen does not keep adaptive pacing enabled forever.
        if adaptiveRecoveryUpdatesRemaining > 0 {
            adaptiveRecoveryUpdatesRemaining -= 1
        }

        guard isContentFrame(frame) else {
            consecutiveLaggingContentFrames = 0
            return
        }

        guard let timing = frame.timing else {
            consecutiveLaggingContentFrames = 0
            return
        }

        if timing.clientProcessingMilliseconds >= Self.laggingClientProcessingThresholdMilliseconds {
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

    private func isContentFrame(_ frame: RFBFramePumpFrame) -> Bool {
        guard !frame.transportIdleTimedOut else {
            return false
        }
        return !(frame.isIncremental && frame.changedPixelCount == 0)
    }
}
