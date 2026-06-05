import Foundation

public enum TextInjectionPath: String, Codable, Equatable, CaseIterable, Sendable {
    case vncClipboardPaste
    case helperTextBridge
}

public enum PasteCommand: String, Codable, Equatable, CaseIterable, Sendable {
    case commandV
    case controlV
}

public enum RemoteClipboardRestoreStatus: String, Codable, Equatable, CaseIterable, Sendable {
    case notAttempted
    case attempted
    case succeeded
    case failed
    case unsupported
}

public enum TextInjectionStatus: String, Codable, Equatable, CaseIterable, Sendable {
    case sent
    case failed
    case unknown
}

public enum TextInjectionStepStatus: String, Codable, Equatable, CaseIterable, Sendable {
    case notAttempted
    case succeeded
    case failed
}

public enum TextInjectionPayloadEncoding: String, Codable, Equatable, CaseIterable, Sendable {
    case ascii
    case latin1
    case utf8ExtensionRequired

    public static func classify(_ text: String) -> TextInjectionPayloadEncoding {
        guard text.unicodeScalars.allSatisfy({ $0.value <= 0x7f }) else {
            if text.unicodeScalars.allSatisfy({ $0.value <= 0xff }) {
                return .latin1
            }
            return .utf8ExtensionRequired
        }
        return .ascii
    }

    public func unconfirmedPasteMessage(
        transferMode: TextClipboardTransferMode?,
        utf8Support: RemoteClipboardUTF8Support?
    ) -> String {
        switch self {
        case .ascii, .latin1:
            "Paste command sent; remote app confirmation unavailable."
        case .utf8ExtensionRequired:
            switch (transferMode, utf8Support) {
            case (.extendedClipboardUTF8?, .supported?):
                "Paste command sent through UTF-8 clipboard; remote app confirmation unavailable."
            case (_, .unsupported?):
                "Paste command sent through legacy VNC clipboard; this server did not confirm UTF-8 clipboard support, so Korean/CJK text may paste incorrectly."
            default:
                "Paste command sent through legacy VNC clipboard; this server has not confirmed UTF-8 clipboard support, so Korean/CJK text may paste incorrectly."
            }
        }
    }
}

public enum RemoteClipboardUTF8Support: String, Codable, Equatable, CaseIterable, Sendable {
    case unknown
    case supported
    case unsupported
}

public enum TextClipboardTransferMode: String, Codable, Equatable, CaseIterable, Sendable {
    case legacyClientCutText
    case extendedClipboardUTF8

    public static func selected(
        utf8Support: RemoteClipboardUTF8Support
    ) -> TextClipboardTransferMode {
        utf8Support == .supported ? .extendedClipboardUTF8 : .legacyClientCutText
    }
}

public enum TextInjectionClipboardPolicy {
    public static func unsupportedPayloadMessage(
        payloadEncoding: TextInjectionPayloadEncoding,
        utf8Support: RemoteClipboardUTF8Support
    ) -> String? {
        guard payloadEncoding == .utf8ExtensionRequired else {
            return nil
        }

        switch utf8Support {
        case .supported:
            return nil
        case .unknown:
            return nil
        case .unsupported:
            return TextInjectionError
                .clipboardUnavailable(
                "This VNC server reported that UTF-8 clipboard support is unavailable, so Korean/CJK/emoji Compose text cannot be sent reliably."
                )
                .localizedDescription
        }
    }
}

public struct TextInjectionAttempt: Codable, Equatable, Identifiable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case draftID
        case sessionID
        case path
        case pasteCommand
        case payloadEncoding
        case clipboardTransferMode
        case utf8ClipboardSupport
        case startedAt
        case finishedAt
        case status
        case clipboardSetStatus
        case pasteCommandStatus
        case remoteClipboardRestore
        case safeMessage
    }

    public let id: UUID
    public let draftID: ComposeDraft.ID
    public let sessionID: UUID
    public let path: TextInjectionPath
    public var pasteCommand: PasteCommand?
    public var payloadEncoding: TextInjectionPayloadEncoding?
    public var clipboardTransferMode: TextClipboardTransferMode?
    public var utf8ClipboardSupport: RemoteClipboardUTF8Support?
    public let startedAt: Date
    public var finishedAt: Date?
    public var status: TextInjectionStatus
    public var clipboardSetStatus: TextInjectionStepStatus
    public var pasteCommandStatus: TextInjectionStepStatus
    public var remoteClipboardRestore: RemoteClipboardRestoreStatus
    public var safeMessage: String

    public init(
        id: UUID = UUID(),
        draftID: ComposeDraft.ID,
        sessionID: UUID,
        path: TextInjectionPath,
        pasteCommand: PasteCommand? = nil,
        payloadEncoding: TextInjectionPayloadEncoding? = nil,
        clipboardTransferMode: TextClipboardTransferMode? = nil,
        utf8ClipboardSupport: RemoteClipboardUTF8Support? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        status: TextInjectionStatus = .unknown,
        clipboardSetStatus: TextInjectionStepStatus = .notAttempted,
        pasteCommandStatus: TextInjectionStepStatus = .notAttempted,
        remoteClipboardRestore: RemoteClipboardRestoreStatus = .notAttempted,
        safeMessage: String = ""
    ) {
        self.id = id
        self.draftID = draftID
        self.sessionID = sessionID
        self.path = path
        self.pasteCommand = pasteCommand
        self.payloadEncoding = payloadEncoding
        self.clipboardTransferMode = clipboardTransferMode
        self.utf8ClipboardSupport = utf8ClipboardSupport
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.clipboardSetStatus = clipboardSetStatus
        self.pasteCommandStatus = pasteCommandStatus
        self.remoteClipboardRestore = remoteClipboardRestore
        self.safeMessage = safeMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            draftID: try container.decode(ComposeDraft.ID.self, forKey: .draftID),
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            path: try container.decode(TextInjectionPath.self, forKey: .path),
            pasteCommand: try container.decodeIfPresent(PasteCommand.self, forKey: .pasteCommand),
            payloadEncoding: try container.decodeIfPresent(
                TextInjectionPayloadEncoding.self,
                forKey: .payloadEncoding
            ),
            clipboardTransferMode: try container.decodeIfPresent(
                TextClipboardTransferMode.self,
                forKey: .clipboardTransferMode
            ),
            utf8ClipboardSupport: try container.decodeIfPresent(
                RemoteClipboardUTF8Support.self,
                forKey: .utf8ClipboardSupport
            ),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            finishedAt: try container.decodeIfPresent(Date.self, forKey: .finishedAt),
            status: try container.decode(TextInjectionStatus.self, forKey: .status),
            clipboardSetStatus: try container.decodeIfPresent(
                TextInjectionStepStatus.self,
                forKey: .clipboardSetStatus
            ) ?? .notAttempted,
            pasteCommandStatus: try container.decodeIfPresent(
                TextInjectionStepStatus.self,
                forKey: .pasteCommandStatus
            ) ?? .notAttempted,
            remoteClipboardRestore: try container.decode(
                RemoteClipboardRestoreStatus.self,
                forKey: .remoteClipboardRestore
            ),
            safeMessage: try container.decode(String.self, forKey: .safeMessage)
        )
    }
}

public protocol RemoteClipboardTextClient: AnyObject {
    var utf8ClipboardSupport: RemoteClipboardUTF8Support { get }

    func setClipboardText(_ text: String) throws
    func sendPasteCommand(_ command: PasteCommand) throws

    /// Reads the next RFB `ServerCutText` (server-to-client clipboard text)
    /// message from the active connection and returns the decoded UTF-8
    /// payload.
    ///
    /// Mirrors the existing synchronous "request the next protocol event"
    /// style used by the framebuffer-update path: callers drive the receive
    /// loop on a detached task and re-enter the main actor when the value
    /// is available.
    ///
    /// The default implementation throws
    /// ``TextInjectionError/clipboardUnavailable(_:)`` so existing in-process
    /// fakes (used only for the outgoing send-side path) keep compiling
    /// without opting in to the receive side.
    func receiveServerCutText(timeout: TimeInterval) throws -> String
}

public extension RemoteClipboardTextClient {
    var utf8ClipboardSupport: RemoteClipboardUTF8Support { .unknown }

    func receiveServerCutText(timeout: TimeInterval) throws -> String {
        throw TextInjectionError.clipboardUnavailable(
            "Remote clipboard receive is not supported by this client."
        )
    }
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
    private let pasteSettleDelay: TimeInterval
    private let sleeper: (TimeInterval) -> Void

    public init(
        pasteSettleDelay: TimeInterval = 0,
        sleeper: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.pasteSettleDelay = max(0, pasteSettleDelay)
        self.sleeper = sleeper
    }

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
                pasteCommand: pasteCommand,
                startedAt: now,
                finishedAt: now,
                status: .failed,
                safeMessage: TextInjectionError.emptyDraft.localizedDescription
            )
        }

        let utf8Support = client.utf8ClipboardSupport
        let transferMode = TextClipboardTransferMode.selected(utf8Support: utf8Support)
        let payloadEncoding = TextInjectionPayloadEncoding.classify(draft.text)

        if let message = TextInjectionClipboardPolicy.unsupportedPayloadMessage(
            payloadEncoding: payloadEncoding,
            utf8Support: utf8Support
        ) {
            draft.markFailed(reason: message, at: now)
            return TextInjectionAttempt(
                draftID: draft.id,
                sessionID: draft.sessionID,
                path: .vncClipboardPaste,
                pasteCommand: pasteCommand,
                payloadEncoding: payloadEncoding,
                clipboardTransferMode: transferMode,
                utf8ClipboardSupport: utf8Support,
                startedAt: now,
                finishedAt: now,
                status: .failed,
                remoteClipboardRestore: .unsupported,
                safeMessage: message
            )
        }

        draft.markSending(path: .vncClipboardPaste, at: now)

        var attempt = TextInjectionAttempt(
            draftID: draft.id,
            sessionID: draft.sessionID,
            path: .vncClipboardPaste,
            pasteCommand: pasteCommand,
            payloadEncoding: payloadEncoding,
            clipboardTransferMode: transferMode,
            utf8ClipboardSupport: utf8Support,
            startedAt: now,
            remoteClipboardRestore: .unsupported
        )

        do {
            try client.setClipboardText(draft.text)
            attempt.clipboardSetStatus = .succeeded
        } catch {
            let message = safeClipboardFailureMessage(from: error)
            draft.markFailed(reason: message, at: now)
            attempt.finishedAt = now
            attempt.status = .failed
            attempt.clipboardSetStatus = .failed
            attempt.safeMessage = message
            return attempt
        }

        if pasteSettleDelay > 0 {
            sleeper(pasteSettleDelay)
        }

        do {
            try client.sendPasteCommand(pasteCommand)
            attempt.pasteCommandStatus = .succeeded
        } catch {
            let message = safePasteFailureMessage(from: error)
            draft.markFailed(reason: message, at: now)
            attempt.finishedAt = now
            attempt.status = .failed
            attempt.pasteCommandStatus = .failed
            attempt.safeMessage = message
            return attempt
        }

        let message = attempt.payloadEncoding?.unconfirmedPasteMessage(
            transferMode: attempt.clipboardTransferMode,
            utf8Support: attempt.utf8ClipboardSupport
        )
            ?? "Paste command sent; remote app confirmation unavailable."
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
