import Foundation

public enum PiPWatchState: String, Codable, Equatable, Sendable {
    case unavailable
    case stopped
    case preparing
    case watching
    case stale
    case failed
}

public enum PiPWatchInputPolicy: String, Codable, Equatable, Sendable {
    case watchOnly
}

public enum PiPFrameChangeActivity: String, Codable, Equatable, Sendable {
    case idle
    case moderate
    case high
}

public struct PiPFrameSnapshot: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let capturedAt: Date
    public let changeActivity: PiPFrameChangeActivity

    public init(
        width: Int,
        height: Int,
        capturedAt: Date = Date(),
        changeActivity: PiPFrameChangeActivity = .moderate
    ) {
        self.width = max(width, 0)
        self.height = max(height, 0)
        self.capturedAt = capturedAt
        self.changeActivity = changeActivity
    }

    public var hasRenderableDimensions: Bool {
        width > 0 && height > 0
    }
}

public struct PiPFramePolicy: Codable, Equatable, Sendable {
    public var idleFrameInterval: TimeInterval
    public var moderateFrameInterval: TimeInterval
    public var highFrameInterval: TimeInterval
    public var staleAfter: TimeInterval

    public init(
        idleFrameInterval: TimeInterval = 1.0,
        moderateFrameInterval: TimeInterval = 0.5,
        highFrameInterval: TimeInterval = 1.0 / 12.0,
        staleAfter: TimeInterval = 8.0
    ) {
        self.idleFrameInterval = idleFrameInterval
        self.moderateFrameInterval = moderateFrameInterval
        self.highFrameInterval = highFrameInterval
        self.staleAfter = staleAfter
    }

    public func targetFrameInterval(for activity: PiPFrameChangeActivity) -> TimeInterval {
        switch activity {
        case .idle:
            return idleFrameInterval
        case .moderate:
            return moderateFrameInterval
        case .high:
            return highFrameInterval
        }
    }

    public func isStale(lastFrameAt: Date?, now: Date = Date()) -> Bool {
        guard let lastFrameAt else {
            return false
        }
        return now.timeIntervalSince(lastFrameAt) >= staleAfter
    }
}

public struct PiPWatchSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: RemoteSession.ID
    public var state: PiPWatchState
    public var startedAt: Date?
    public var lastFrame: PiPFrameSnapshot?
    public var safeMessage: String
    public var inputPolicy: PiPWatchInputPolicy
    public var framePolicy: PiPFramePolicy

    public init(
        id: UUID = UUID(),
        sessionID: RemoteSession.ID,
        state: PiPWatchState = .stopped,
        startedAt: Date? = nil,
        lastFrame: PiPFrameSnapshot? = nil,
        safeMessage: String = "PiP Watch is ready.",
        inputPolicy: PiPWatchInputPolicy = .watchOnly,
        framePolicy: PiPFramePolicy = PiPFramePolicy()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.state = state
        self.startedAt = startedAt
        self.lastFrame = lastFrame
        self.safeMessage = safeMessage
        self.inputPolicy = inputPolicy
        self.framePolicy = framePolicy
    }

    public var allowsRemoteInputFromPiP: Bool {
        false
    }

    public mutating func prepare(
        from session: RemoteSession,
        profileAllowsPiPWatch: Bool = true,
        at date: Date = Date()
    ) {
        guard profileAllowsPiPWatch else {
            state = .unavailable
            safeMessage = "PiP Watch is disabled for this profile."
            return
        }

        guard session.id == sessionID, session.state.allowsPiPWatch else {
            state = .unavailable
            safeMessage = "PiP Watch is unavailable for this session state."
            return
        }

        guard session.hasReceivedFrame else {
            state = .unavailable
            safeMessage = "PiP Watch is available after a remote frame is active."
            return
        }

        state = .preparing
        startedAt = date
        safeMessage = "Preparing PiP Watch."
    }

    public mutating func markWatching(frame: PiPFrameSnapshot) {
        guard state == .preparing || state == .watching || state == .stale else {
            state = .failed
            safeMessage = "PiP Watch must be prepared before frames are shown."
            return
        }

        guard frame.hasRenderableDimensions else {
            state = .failed
            safeMessage = "PiP frame cannot be rendered."
            return
        }

        lastFrame = frame
        state = .watching
        safeMessage = "Watching remote desktop in PiP."
    }

    public mutating func refreshStaleness(now: Date = Date()) {
        guard framePolicy.isStale(lastFrameAt: lastFrame?.capturedAt, now: now) else {
            return
        }
        state = .stale
        safeMessage = "PiP frame is stale; main session remains available."
    }

    public mutating func fail(_ message: String) {
        state = .failed
        safeMessage = message
    }

    public mutating func markUnavailable(_ message: String) {
        state = .unavailable
        safeMessage = message
    }

    public mutating func stop() {
        state = .stopped
        safeMessage = "PiP Watch stopped."
    }
}

public extension RemoteSessionState {
    var allowsPiPWatch: Bool {
        switch self {
        case .active, .degraded, .reconnecting:
            return true
        case .connecting, .authenticating, .failed, .closed:
            return false
        }
    }
}
