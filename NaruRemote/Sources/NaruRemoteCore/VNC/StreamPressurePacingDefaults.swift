import Foundation

/// Shared app/benchmark thresholds for adaptive stream pacing.
///
/// These values are intentionally aggregate-only and contain no host,
/// pixel, coordinate, or payload data. Keeping them in Core lets the
/// live benchmark mirror the app's pressure trigger without drifting
/// when sustained-session tuning changes.
public enum StreamPressurePacingDefaults {
    public static let balancedContentFrameIntervalSeconds: Double = 1.0 / 30.0
    /// While the user is locally pinching/panning the viewport, the app
    /// pauses new framebuffer requests when an existing frame is visible and
    /// defers any in-flight framebuffer publication/upload until gesture end.
    /// These floors are retained for the rare already-in-flight frame that
    /// lands during the gesture.
    public static let viewportInteractionContentFrameIntervalSeconds: Double = 1.0 / 8.0
    public static let viewportInteractionIdleFrameIntervalSeconds: Double = 0.20
    public static let viewportInteractionRequestPausePollSeconds: Double = 1.0 / 60.0
    public static let severeLaggingLocalWorkThresholdMilliseconds = 80
    public static let consecutiveSevereLaggingContentFrameThreshold = 3
    public static let sustainedLaggingLocalWorkThresholdMilliseconds = 34
    public static let consecutiveSustainedLaggingContentFrameThreshold = 8
    public static let consecutiveFullUploadContentFrameThreshold = 30
    public static let adaptiveRecoveryUpdateCount = 120
}
