import Foundation

public enum ComposeSendState: String, Codable, Equatable, CaseIterable, Sendable {
    case idle
    case ready
    case sending
    case sent
    case failed
    case unknown
}

public struct ComposeDraft: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public private(set) var text: String
    public let createdAt: Date
    public private(set) var updatedAt: Date
    public private(set) var sendState: ComposeSendState
    public private(set) var lastInjectionPath: TextInjectionPath?
    public private(set) var lastFailureReason: String?
    public private(set) var lastStatusMessage: String?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        text: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sendState: ComposeSendState = .idle,
        lastInjectionPath: TextInjectionPath? = nil,
        lastFailureReason: String? = nil,
        lastStatusMessage: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sendState = sendState
        self.lastInjectionPath = lastInjectionPath
        self.lastFailureReason = lastFailureReason
        self.lastStatusMessage = lastStatusMessage
    }

    public var canSend: Bool {
        !text.isEmpty && sendState != .sending
    }

    public mutating func updateText(_ text: String, at date: Date = Date()) {
        self.text = text
        self.updatedAt = date
        self.sendState = text.isEmpty ? .idle : .ready
        self.lastFailureReason = nil
        self.lastStatusMessage = nil
    }

    public mutating func markSending(path: TextInjectionPath, at date: Date = Date()) {
        self.sendState = .sending
        self.lastInjectionPath = path
        self.updatedAt = date
        self.lastFailureReason = nil
        self.lastStatusMessage = "Sending through \(path.rawValue)"
    }

    /// Did this outcome consume the draft? (spec 038 FR-004/FR-005)
    ///
    /// Send is a submit since spec 015 v1.1 FR-010 — the draft leaves with a
    /// trailing Return — so text that reached the wire has to leave the field
    /// too. Leaving it there is how the founder came to be looking at a line he
    /// had already run, one tap away from running it twice, which in a terminal
    /// is not a cosmetic mistake.
    ///
    /// `unknown` counts as consumed: the bytes left the device and only the
    /// remote app's reaction is unconfirmable. `failed` does not, because then
    /// the field is the only place the text still exists.
    ///
    /// This is a property of the outcome rather than a flag each caller passes.
    /// It was a `clearAfterSend:` / `clearAfterConfirmation:` parameter
    /// defaulting to false, and all three delivery paths — keystroke, helper,
    /// clipboard — took the default.
    public static func outcomeConsumesDraft(_ state: ComposeSendState) -> Bool {
        switch state {
        case .sent, .unknown:
            return true
        case .idle, .ready, .sending, .failed:
            return false
        }
    }

    public mutating func markSent(
        message: String = "Sent",
        at date: Date = Date()
    ) {
        self.sendState = .sent
        self.updatedAt = date
        self.lastFailureReason = nil
        self.lastStatusMessage = message
        consumeTextIfOutcomeRequires()
    }

    public mutating func markFailed(reason: String, at date: Date = Date()) {
        self.sendState = .failed
        self.updatedAt = date
        self.lastFailureReason = reason
        self.lastStatusMessage = reason
        consumeTextIfOutcomeRequires()
    }

    public mutating func markUnknown(
        message: String,
        at date: Date = Date()
    ) {
        self.sendState = .unknown
        self.updatedAt = date
        self.lastFailureReason = nil
        self.lastStatusMessage = message
        consumeTextIfOutcomeRequires()
    }

    public mutating func markPasteDispatched(message: String, at date: Date = Date()) {
        markUnknown(message: message, at: date)
    }

    private mutating func consumeTextIfOutcomeRequires() {
        guard Self.outcomeConsumesDraft(sendState) else {
            return
        }
        text = ""
    }
}
