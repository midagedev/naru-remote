import Foundation

public enum TextInjectionPath: String, Codable, Equatable, Sendable {
    case vncClipboardPaste
}

public enum PasteCommand: String, Codable, Equatable, Sendable {
    case commandV
    case controlV
}

public enum RemoteClipboardRestoreStatus: String, Codable, Equatable, Sendable {
    case notAttempted
    case attempted
    case succeeded
    case failed
    case unsupported
}

public enum TextInjectionStatus: String, Codable, Equatable, Sendable {
    case sent
    case failed
    case unknown
}

public struct TextInjectionAttempt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let draftID: ComposeDraft.ID
    public let sessionID: UUID
    public let path: TextInjectionPath
    public let startedAt: Date
    public var finishedAt: Date?
    public var status: TextInjectionStatus
    public var remoteClipboardRestore: RemoteClipboardRestoreStatus
    public var safeMessage: String

    public init(
        id: UUID = UUID(),
        draftID: ComposeDraft.ID,
        sessionID: UUID,
        path: TextInjectionPath,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        status: TextInjectionStatus = .unknown,
        remoteClipboardRestore: RemoteClipboardRestoreStatus = .notAttempted,
        safeMessage: String = ""
    ) {
        self.id = id
        self.draftID = draftID
        self.sessionID = sessionID
        self.path = path
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.remoteClipboardRestore = remoteClipboardRestore
        self.safeMessage = safeMessage
    }
}

public protocol RemoteClipboardTextClient {
    func setClipboardText(_ text: String) throws
    func sendPasteCommand(_ command: PasteCommand) throws
}

public enum TextInjectionError: Error, Equatable, LocalizedError {
    case emptyDraft
    case clipboardUnavailable(String)
    case pasteCommandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDraft:
            "There is no text to send."
        case .clipboardUnavailable(let reason):
            "Text clipboard unavailable: \(reason)"
        case .pasteCommandFailed(let reason):
            "Paste command failed: \(reason)"
        }
    }
}

public struct TextInjectionAdapter {
    public init() {}

    public func send(
        draft: inout ComposeDraft,
        via client: RemoteClipboardTextClient,
        pasteCommand: PasteCommand,
        now: Date = Date()
    ) -> TextInjectionAttempt {
        guard draft.canSend else {
            draft.markFailed(reason: TextInjectionError.emptyDraft.localizedDescription, at: now)
            return TextInjectionAttempt(
                draftID: draft.id,
                sessionID: draft.sessionID,
                path: .vncClipboardPaste,
                startedAt: now,
                finishedAt: now,
                status: .failed,
                safeMessage: TextInjectionError.emptyDraft.localizedDescription
            )
        }

        draft.markSending(path: .vncClipboardPaste, at: now)

        var attempt = TextInjectionAttempt(
            draftID: draft.id,
            sessionID: draft.sessionID,
            path: .vncClipboardPaste,
            startedAt: now,
            remoteClipboardRestore: .unsupported
        )

        do {
            try client.setClipboardText(draft.text)
        } catch {
            let message = safeClipboardFailureMessage(from: error)
            draft.markFailed(reason: message, at: now)
            attempt.finishedAt = now
            attempt.status = .failed
            attempt.safeMessage = message
            return attempt
        }

        do {
            try client.sendPasteCommand(pasteCommand)
        } catch {
            let message = safePasteFailureMessage(from: error)
            draft.markFailed(reason: message, at: now)
            attempt.finishedAt = now
            attempt.status = .failed
            attempt.safeMessage = message
            return attempt
        }

        let message = "Paste command sent; remote app confirmation unavailable."
        draft.markUnknown(message: message, at: now)
        attempt.finishedAt = now
        attempt.status = .unknown
        attempt.safeMessage = message
        return attempt
    }

    private func safeClipboardFailureMessage(from error: Error) -> String {
        if let error = error as? TextInjectionError {
            return error.localizedDescription
        }

        return TextInjectionError
            .clipboardUnavailable("Remote clipboard did not accept text.")
            .localizedDescription
    }

    private func safePasteFailureMessage(from error: Error) -> String {
        if let error = error as? TextInjectionError {
            return error.localizedDescription
        }

        return TextInjectionError
            .pasteCommandFailed("Remote paste command could not be delivered.")
            .localizedDescription
    }
}
