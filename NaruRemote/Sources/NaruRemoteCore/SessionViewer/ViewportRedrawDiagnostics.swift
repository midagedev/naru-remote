import Foundation

/// Safe aggregate counters for local viewport redraw work.
///
/// These values describe viewer-side scheduling only. They intentionally do not
/// include framebuffer dimensions, coordinates, pixels, host identity, raw
/// timestamps, or user content.
public struct ViewportRedrawDiagnostics: Equatable, Sendable {
    public var interactionCount: Int
    public var gestureSampleCount: Int
    public var gestureLongFrameCount: Int
    public var gestureMaxIntervalMilliseconds: Int
    public var incomingFrameDeferredCount: Int
    public var redrawRequestCount: Int
    public var redrawFlushCount: Int
    public var decelerationFrameCount: Int
    public var observedMaximumFramesPerSecond: Int

    public init(
        interactionCount: Int = 0,
        gestureSampleCount: Int = 0,
        gestureLongFrameCount: Int = 0,
        gestureMaxIntervalMilliseconds: Int = 0,
        incomingFrameDeferredCount: Int = 0,
        redrawRequestCount: Int = 0,
        redrawFlushCount: Int = 0,
        decelerationFrameCount: Int = 0,
        observedMaximumFramesPerSecond: Int = 0
    ) {
        self.interactionCount = max(interactionCount, 0)
        self.gestureSampleCount = max(gestureSampleCount, 0)
        self.gestureLongFrameCount = max(gestureLongFrameCount, 0)
        self.gestureMaxIntervalMilliseconds = max(gestureMaxIntervalMilliseconds, 0)
        self.incomingFrameDeferredCount = max(incomingFrameDeferredCount, 0)
        self.redrawRequestCount = max(redrawRequestCount, 0)
        self.redrawFlushCount = max(redrawFlushCount, 0)
        self.decelerationFrameCount = max(decelerationFrameCount, 0)
        self.observedMaximumFramesPerSecond = max(observedMaximumFramesPerSecond, 0)
    }

    public var hasSamples: Bool {
        interactionCount > 0
            || gestureSampleCount > 0
            || gestureLongFrameCount > 0
            || gestureMaxIntervalMilliseconds > 0
            || incomingFrameDeferredCount > 0
            || redrawRequestCount > 0
            || redrawFlushCount > 0
            || decelerationFrameCount > 0
            || observedMaximumFramesPerSecond > 0
    }

    public mutating func merge(_ other: ViewportRedrawDiagnostics) {
        interactionCount += max(other.interactionCount, 0)
        gestureSampleCount += max(other.gestureSampleCount, 0)
        gestureLongFrameCount += max(other.gestureLongFrameCount, 0)
        gestureMaxIntervalMilliseconds = max(
            gestureMaxIntervalMilliseconds,
            max(other.gestureMaxIntervalMilliseconds, 0)
        )
        incomingFrameDeferredCount += max(other.incomingFrameDeferredCount, 0)
        redrawRequestCount += max(other.redrawRequestCount, 0)
        redrawFlushCount += max(other.redrawFlushCount, 0)
        decelerationFrameCount += max(other.decelerationFrameCount, 0)
        observedMaximumFramesPerSecond = max(
            observedMaximumFramesPerSecond,
            other.observedMaximumFramesPerSecond
        )
    }
}
