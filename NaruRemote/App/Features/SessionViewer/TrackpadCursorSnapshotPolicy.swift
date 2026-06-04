import NaruRemoteCore

enum TrackpadCursorSnapshotPolicy {
    /// Block only late SwiftUI cursor snapshots during an active hot-path
    /// drag; mode switches and settled drags must still resync from the model.
    nonisolated static func shouldAdoptPublishedCursor(
        pointerControlMode: PointerControlMode,
        didChangePointerControlMode: Bool,
        isTrackpadDragActive: Bool
    ) -> Bool {
        if didChangePointerControlMode {
            return true
        }
        if !pointerControlMode.isTrackpad {
            return true
        }
        return !isTrackpadDragActive
    }
}
