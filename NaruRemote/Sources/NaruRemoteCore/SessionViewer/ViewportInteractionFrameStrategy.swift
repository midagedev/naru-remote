import Foundation

/// Controls how aggressively the app should publish/upload streamed
/// framebuffer frames while a local viewport gesture owns the screen.
public enum ViewportInteractionFrameStrategy: String, Equatable, Sendable {
    /// Direct pinch/pan/deceleration should feel like local photo
    /// navigation: keep the visible movement on the compositor path,
    /// defer heavyweight remote frame publication, but still sample the
    /// viewport transform so view-aware traffic follows the visible region.
    case deferUntilSettled

    /// Trackpad cursor-follow may need bounded live dirty-rect updates so
    /// the actual server cursor/text echo remains visible while zoomed.
    case liveRemoteFrames

    public var allowsLiveFramebufferPublication: Bool {
        self == .liveRemoteFrames
    }

    /// View-aware traffic should follow the visible viewport for every
    /// interaction strategy, even when heavyweight framebuffer publication
    /// is deferred until the gesture settles.
    public var publishesLiveViewportStateForViewAwareTraffic: Bool { true }
}
