import NaruRemoteCore

public struct SessionViewportTrackpadGestureResult: Equatable, Sendable {
    public var transform: ViewportTransform
    public var cursor: TrackpadCursor

    public init(transform: ViewportTransform, cursor: TrackpadCursor) {
        self.transform = transform
        self.cursor = cursor
    }
}
