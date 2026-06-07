import Combine
import Foundation
import NaruRemoteCore

@MainActor
public final class TrackpadCursorStore: ObservableObject {
    @Published public private(set) var cursor: TrackpadCursor

    public init(cursor: TrackpadCursor = TrackpadCursor()) {
        self.cursor = cursor
    }

    public func publish(_ cursor: TrackpadCursor) {
        guard self.cursor != cursor else {
            return
        }
        self.cursor = cursor
    }
}
