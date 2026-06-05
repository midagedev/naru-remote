import Foundation

/// Shared app/benchmark thresholds for adaptive stream pacing.
///
/// These values are intentionally aggregate-only and contain no host,
/// pixel, coordinate, or payload data. Keeping them in Core lets the
/// live benchmark mirror the app's pressure trigger without drifting
/// when sustained-session tuning changes.
public enum StreamPressurePacingDefaults {
    public static let balancedContentFrameIntervalSeconds: Double = 1.0 / 30.0
    /// Localized terminal/cursor/editor damage can be sampled more often during
    /// viewport gestures without paying the full-frame upload cost. This keeps
    /// remote echo alive while the local compositor path owns pinch/pan.
    public static let viewportInteractionPartialContentFrameIntervalSeconds: Double = 1.0 / 15.0
    /// While the user is locally pinching/panning the viewport, keep the
    /// local compositor path in charge while the request loop continues at a
    /// conservative 4 Hz-class bounded cadence. The app can then keep only the
    /// newest deferred frame and flush it when the touch interaction settles,
    /// avoiding decode/upload hitches on physical iPhones without tearing down
    /// stream liveness.
    public static let viewportInteractionContentFrameIntervalSeconds: Double = 1.0 / 4.0
    public static let viewportInteractionIdleFrameIntervalSeconds: Double = 0.20
    public static let viewportInteractionRequestPausePollSeconds: Double = 1.0 / 60.0
    public static let verySlowLocalWorkThresholdMilliseconds = 1_000
    public static let severeLaggingLocalWorkThresholdMilliseconds = 80
    public static let consecutiveSevereLaggingContentFrameThreshold = 3
    public static let sustainedLaggingLocalWorkThresholdMilliseconds = 34
    public static let consecutiveSustainedLaggingContentFrameThreshold = 8
    public static let consecutiveFullUploadContentFrameThreshold = 30
    /// A single 1000 ms-class local-work spike often appears during live
    /// connection/profile warm-up. Cool briefly, but keep the long recovery
    /// window for repeated lag/full-upload pressure below.
    public static let verySlowAdaptiveRecoveryUpdateCount = 8
    public static let adaptiveRecoveryUpdateCount = 120
}
