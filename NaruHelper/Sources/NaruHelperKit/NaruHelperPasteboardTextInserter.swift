import Foundation
import NaruRemoteCore

public struct NaruHelperPasteboardSnapshot: Equatable, Sendable {
    public let stringValue: String?

    public init(stringValue: String?) {
        self.stringValue = stringValue
    }
}

public protocol NaruHelperPasteboard: AnyObject {
    func saveGeneralString() throws -> NaruHelperPasteboardSnapshot
    func replaceGeneralString(with text: String) throws
    func restoreGeneralString(_ snapshot: NaruHelperPasteboardSnapshot) throws
}

public protocol NaruHelperPasteCommandPosting {
    var canPostPasteCommand: Bool { get }
    func postPasteCommand() throws
}

public enum NaruHelperTextInsertOperationError: Error, Equatable, Sendable {
    case pasteboardUnavailable
    case pasteCommandUnavailable
    case pasteCommandFailed
    case restoreFailed
}

public struct NaruHelperPasteboardTextInserter {
    private let pasteboard: any NaruHelperPasteboard
    private let pasteCommandPoster: any NaruHelperPasteCommandPosting

    public init(
        pasteboard: any NaruHelperPasteboard,
        pasteCommandPoster: any NaruHelperPasteCommandPosting
    ) {
        self.pasteboard = pasteboard
        self.pasteCommandPoster = pasteCommandPoster
    }

    public func insertText(
        request: NaruHelperInsertTextRequest
    ) -> NaruHelperInsertTextResponse {
        guard request.schemaVersion == naruHelperTextBridgeSchemaVersion else {
            return failure(
                requestID: request.requestID,
                strategyUsed: .unsupported,
                code: .versionUnsupported
            )
        }

        guard !request.text.isEmpty else {
            return failure(
                requestID: request.requestID,
                strategyUsed: .unsupported,
                code: .insertRejected
            )
        }

        guard request.strategyPreference.contains(.pasteboardPasteWithRestore) else {
            return failure(
                requestID: request.requestID,
                strategyUsed: .unsupported,
                code: .insertRejected
            )
        }

        guard pasteCommandPoster.canPostPasteCommand else {
            return failure(
                requestID: request.requestID,
                strategyUsed: .pasteboardPasteWithRestore,
                code: .permissionMissing
            )
        }

        let snapshot: NaruHelperPasteboardSnapshot
        do {
            snapshot = try pasteboard.saveGeneralString()
            try pasteboard.replaceGeneralString(with: request.text)
        } catch {
            return failure(
                requestID: request.requestID,
                strategyUsed: .pasteboardPasteWithRestore,
                code: .insertRejected
            )
        }

        do {
            try pasteCommandPoster.postPasteCommand()
        } catch {
            _ = try? pasteboard.restoreGeneralString(snapshot)
            return failure(
                requestID: request.requestID,
                strategyUsed: .pasteboardPasteWithRestore,
                code: .focusUnavailable
            )
        }

        do {
            try pasteboard.restoreGeneralString(snapshot)
        } catch {
            return failure(
                requestID: request.requestID,
                strategyUsed: .pasteboardPasteWithRestore,
                code: .restoreFailed
            )
        }

        return NaruHelperInsertTextResponse(
            requestID: request.requestID,
            status: .sent,
            strategyUsed: .pasteboardPasteWithRestore,
            safeFailureCode: .none
        )
    }

    private func failure(
        requestID: UUID,
        strategyUsed: HelperTextInsertStrategy,
        code: HelperTextBridgeFailureCode
    ) -> NaruHelperInsertTextResponse {
        NaruHelperInsertTextResponse(
            requestID: requestID,
            status: .failed,
            strategyUsed: strategyUsed,
            safeFailureCode: code
        )
    }
}

#if os(macOS)
import AppKit
import CoreGraphics

public final class MacGeneralPasteboard: NaruHelperPasteboard {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func saveGeneralString() throws -> NaruHelperPasteboardSnapshot {
        NaruHelperPasteboardSnapshot(stringValue: pasteboard.string(forType: .string))
    }

    public func replaceGeneralString(with text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw NaruHelperTextInsertOperationError.pasteboardUnavailable
        }
    }

    public func restoreGeneralString(_ snapshot: NaruHelperPasteboardSnapshot) throws {
        pasteboard.clearContents()
        guard let stringValue = snapshot.stringValue else {
            return
        }
        guard pasteboard.setString(stringValue, forType: .string) else {
            throw NaruHelperTextInsertOperationError.restoreFailed
        }
    }
}

public struct MacPasteCommandPoster: NaruHelperPasteCommandPosting {
    public init() {}

    public var canPostPasteCommand: Bool {
        CGPreflightPostEventAccess()
    }

    public func postPasteCommand() throws {
        guard canPostPasteCommand else {
            throw NaruHelperTextInsertOperationError.pasteCommandUnavailable
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0x09,
            keyDown: true
        ),
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0x09,
            keyDown: false
        ) else {
            throw NaruHelperTextInsertOperationError.pasteCommandFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
#endif
