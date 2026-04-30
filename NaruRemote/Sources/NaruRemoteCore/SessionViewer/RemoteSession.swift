import Foundation

public enum RemoteSessionState: String, Codable, Equatable, Sendable {
    case connecting
    case authenticating
    case active
    case degraded
    case reconnecting
    case failed
    case closed
}

public struct RemoteViewportState: Codable, Equatable, Sendable {
    public var zoomScale: Double
    public var panX: Double
    public var panY: Double

    public init(zoomScale: Double = 1, panX: Double = 0, panY: Double = 0) {
        self.zoomScale = zoomScale
        self.panX = panX
        self.panY = panY
    }
}

public struct RemoteSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let profileID: ConnectionProfile.ID
    public var state: RemoteSessionState
    public var viewportState: RemoteViewportState
    public var hudMessage: String?
    public var lastFrameAt: Date?
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        profileID: ConnectionProfile.ID,
        state: RemoteSessionState = .connecting,
        viewportState: RemoteViewportState = RemoteViewportState(),
        hudMessage: String? = nil,
        lastFrameAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.state = state
        self.viewportState = viewportState
        self.hudMessage = hudMessage
        self.lastFrameAt = lastFrameAt
        self.lastError = lastError
    }

    public mutating func markFirstFrameReceived(at date: Date = Date()) {
        state = .active
        lastFrameAt = date
        hudMessage = "Connected"
        lastError = nil
    }

    public mutating func markFailed(_ message: String) {
        state = .failed
        hudMessage = message
        lastError = message
    }

    public var hasReceivedFrame: Bool {
        lastFrameAt != nil
    }

    public var allowsPiPWatch: Bool {
        state.allowsPiPWatch && hasReceivedFrame
    }
}
