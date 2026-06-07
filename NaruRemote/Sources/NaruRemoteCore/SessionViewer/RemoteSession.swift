import Foundation

/// Lifecycle state of an active or pending remote session.
///
/// `reconnecting(attempt:of:)` carries the current attempt index and
/// the bounded `ReconnectPolicy.maxAttempts` ceiling so the HUD can
/// show "재연결 중 (1/3)…" without recomputing the policy.  All
/// other cases are scalar — they survived from the original `String`
/// raw-value enum, and the custom `Codable` keeps the same
/// over-the-wire spelling so persisted snapshots round-trip.
public enum RemoteSessionState: Codable, Equatable, Sendable {
    case connecting
    case authenticating
    case active
    case degraded
    /// A streaming connection dropped and the model is sleeping the
    /// policy backoff before the `attempt`-th attempt out of `of`.
    /// On a successful new frame the state returns to `.active`; on
    /// exhaustion it transitions to `.failed`.
    case reconnecting(attempt: Int, of: Int)
    case failed
    case closed

    /// Stable string identifier for analytics, accessibility, and
    /// the HUD subtitle.  Mirrors the original `String` raw value of
    /// the pre-associated-value enum so existing tests and snapshots
    /// keep matching.
    public var identifier: String {
        switch self {
        case .connecting: return "connecting"
        case .authenticating: return "authenticating"
        case .active: return "active"
        case .degraded: return "degraded"
        case .reconnecting: return "reconnecting"
        case .failed: return "failed"
        case .closed: return "closed"
        }
    }

    /// True while asynchronous media pipelines may still mutate
    /// session-owned visual/input state for this session. Once a session has
    /// failed or closed, late network/video callbacks must be treated as stale
    /// even if their session ID still matches.
    public var acceptsSessionScopedMediaCallbacks: Bool {
        switch self {
        case .connecting, .authenticating, .active, .degraded, .reconnecting:
            return true
        case .failed, .closed:
            return false
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind
        case attempt
        case of
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "connecting": self = .connecting
        case "authenticating": self = .authenticating
        case "active": self = .active
        case "degraded": self = .degraded
        case "reconnecting":
            let attempt = try container.decode(Int.self, forKey: .attempt)
            let of = try container.decode(Int.self, forKey: .of)
            self = .reconnecting(attempt: attempt, of: of)
        case "failed": self = .failed
        case "closed": self = .closed
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown RemoteSessionState kind: \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .kind)
        if case let .reconnecting(attempt, of) = self {
            try container.encode(attempt, forKey: .attempt)
            try container.encode(of, forKey: .of)
        }
    }
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

    /// Transition into a bounded auto-reconnect window.  Updates the
    /// HUD message to the catalog string the viewport HUD renders;
    /// callers do NOT pipe raw error text through this surface
    /// (constitution §IV).
    public mutating func markReconnecting(attempt: Int, of total: Int) {
        state = .reconnecting(attempt: attempt, of: total)
        hudMessage = "Reconnecting (\(attempt)/\(total))…"
        // Intentionally leave `lastError` and `lastFrameAt` alone:
        // the most recent frame is still the on-screen content and
        // a user-visible "what last broke" is opaque on purpose.
    }

    public var hasReceivedFrame: Bool {
        lastFrameAt != nil
    }

    public var allowsPiPWatch: Bool {
        state.allowsPiPWatch && hasReceivedFrame
    }
}
