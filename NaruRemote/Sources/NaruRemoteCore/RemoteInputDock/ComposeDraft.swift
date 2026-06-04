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

    public mutating func markSent(clearAfterConfirmation: Bool = false, at date: Date = Date()) {
        self.sendState = .sent
        self.updatedAt = date
        self.lastFailureReason = nil
        self.lastStatusMessage = "Sent"
        if clearAfterConfirmation {
            self.text = ""
        }
    }

    public mutating func markFailed(reason: String, at date: Date = Date()) {
        self.sendState = .failed
        self.updatedAt = date
        self.lastFailureReason = reason
        self.lastStatusMessage = reason
    }

    public mutating func markUnknown(
        message: String,
        clearAfterSend: Bool = false,
        at date: Date = Date()
    ) {
        self.sendState = .unknown
        self.updatedAt = date
        self.lastFailureReason = nil
        self.lastStatusMessage = message
        if clearAfterSend {
            self.text = ""
        }
    }

    public mutating func markPasteDispatched(message: String, at date: Date = Date()) {
        markUnknown(message: message, clearAfterSend: false, at: date)
    }
}
