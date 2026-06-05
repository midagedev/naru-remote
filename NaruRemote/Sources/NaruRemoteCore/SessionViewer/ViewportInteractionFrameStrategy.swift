import Foundation

/// Controls how aggressively the app should publish/upload streamed
/// framebuffer frames while a local viewport gesture owns the screen.
public enum ViewportInteractionFrameStrategy: String, Equatable, Sendable {
    /// Direct pinch/pan/deceleration should feel like local photo
    /// navigation: keep the visible movement on the compositor path and
    /// publish only the latest deferred remote frame when the gesture settles.
    case deferUntilSettled

    /// Trackpad cursor-follow may need bounded live dirty-rect updates so
    /// the actual server cursor/text echo remains visible while zoomed.
    case liveRemoteFrames

    public var allowsLiveFramebufferPublication: Bool {
        self == .liveRemoteFrames
    }
}
