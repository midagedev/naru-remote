import Foundation

/// Decision returned when a streamed framebuffer arrives while the
/// user is actively manipulating the local viewport.
public enum ViewportGestureRedrawDecision: Equatable, Sendable {
    case requestNow
    case deferRedraw
}

/// Coalesces expensive framebuffer redraws while a pinch/pan/trackpad
/// viewport gesture is active.
///
/// The visible viewport movement stays on the local transform path;
/// this throttle only controls how often newly-arrived remote frames
/// are uploaded/redrawn during that gesture.  When the gesture ends,
/// any deferred latest frame is flushed once.
public struct ViewportGestureRedrawThrottle: Equatable, Sendable {
    public let minimumInterval: TimeInterval
    public let allowsFirstRedrawDuringGesture: Bool

    private var lastRequestAt: TimeInterval?
    private var hasDeferredRedraw: Bool

    public init(
        minimumInterval: TimeInterval = 1.0 / 15.0,
        allowsFirstRedrawDuringGesture: Bool = true
    ) {
        self.minimumInterval = max(0, minimumInterval)
        self.allowsFirstRedrawDuringGesture = allowsFirstRedrawDuringGesture
        self.lastRequestAt = nil
        self.hasDeferredRedraw = false
    }

    public mutating func recordIncomingFrame(
        isGestureActive: Bool,
        now: TimeInterval
    ) -> ViewportGestureRedrawDecision {
        guard isGestureActive else {
            reset()
            return .requestNow
        }

        guard minimumInterval > 0,
              now.isFinite
        else {
            lastRequestAt = now
            hasDeferredRedraw = false
            return .requestNow
        }

        guard let lastRequestAt else {
            self.lastRequestAt = now
            if allowsFirstRedrawDuringGesture {
                return .requestNow
            }
            hasDeferredRedraw = true
            return .deferRedraw
        }

        guard now - lastRequestAt >= minimumInterval else {
            hasDeferredRedraw = true
            return .deferRedraw
        }

        self.lastRequestAt = now
        hasDeferredRedraw = false
        return .requestNow
    }

    public mutating func flushAfterGesture() -> Bool {
        let shouldFlush = hasDeferredRedraw
        reset()
        return shouldFlush
    }

    public mutating func reset() {
        lastRequestAt = nil
        hasDeferredRedraw = false
    }
}
