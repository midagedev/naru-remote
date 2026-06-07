import Foundation
import NaruRemoteCore

public struct NaruHelperPasteboardRepresentationSnapshot: Equatable, Sendable {
    public let typeName: String
    public let data: Data

    public init(typeName: String, data: Data) {
        self.typeName = typeName
        self.data = data
    }
}

public struct NaruHelperPasteboardItemSnapshot: Equatable, Sendable {
    public let representations: [NaruHelperPasteboardRepresentationSnapshot]

    public init(representations: [NaruHelperPasteboardRepresentationSnapshot]) {
        self.representations = representations
    }
}

public struct NaruHelperPasteboardSnapshot: Equatable, Sendable {
    public let stringValue: String?
    public let items: [NaruHelperPasteboardItemSnapshot]

    public init(
        stringValue: String?,
        items: [NaruHelperPasteboardItemSnapshot] = []
    ) {
        self.stringValue = stringValue
        self.items = items
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

public protocol NaruHelperNativeTextInserting {
    var canInsertTextDirectly: Bool { get }
    func insertTextDirectly(_ text: String) throws
}

public enum NaruHelperNativeTextInsertOperationError: Error, Equatable, Sendable {
    case permissionMissing
    case focusUnavailable
    case insertRejected
}

public struct NaruHelperNativeTextInserterChain: NaruHelperNativeTextInserting {
    private let inserters: [any NaruHelperNativeTextInserting]

    public init(_ inserters: [any NaruHelperNativeTextInserting]) {
        self.inserters = inserters
    }

    public var canInsertTextDirectly: Bool {
        inserters.contains { $0.canInsertTextDirectly }
    }

    public func insertTextDirectly(_ text: String) throws {
        var lastFailure: NaruHelperNativeTextInsertOperationError?

        for inserter in inserters where inserter.canInsertTextDirectly {
            do {
                try inserter.insertTextDirectly(text)
                return
            } catch let error as NaruHelperNativeTextInsertOperationError {
                lastFailure = error
            } catch {
                lastFailure = .insertRejected
            }
        }

        throw lastFailure ?? NaruHelperNativeTextInsertOperationError.permissionMissing
    }
}

public enum NaruHelperUnicodeEventChunker {
    public static func chunks(
        for text: String,
        maxUTF16UnitsPerEvent: Int,
        maxUTF16UnitsPerRequest: Int
    ) -> [[UInt16]]? {
        guard maxUTF16UnitsPerEvent > 0,
              maxUTF16UnitsPerRequest > 0,
              !text.isEmpty,
              text.utf16.count <= maxUTF16UnitsPerRequest
        else {
            return nil
        }

        var chunks: [[UInt16]] = []
        var current: [UInt16] = []

        for scalar in text.unicodeScalars {
            let scalarUnits = Array(String(scalar).utf16)
            guard scalarUnits.count <= maxUTF16UnitsPerEvent else {
                return nil
            }

            if current.count + scalarUnits.count > maxUTF16UnitsPerEvent {
                if !current.isEmpty {
                    chunks.append(current)
                }
                current = []
            }

            current.append(contentsOf: scalarUnits)
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }
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
    private let nativeTextInserter: (any NaruHelperNativeTextInserting)?

    public init(
        pasteboard: any NaruHelperPasteboard,
        pasteCommandPoster: any NaruHelperPasteCommandPosting,
        nativeTextInserter: (any NaruHelperNativeTextInserting)? = nil
    ) {
        self.pasteboard = pasteboard
        self.pasteCommandPoster = pasteCommandPoster
        self.nativeTextInserter = nativeTextInserter
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

        let wantsNativeInsert = request.strategyPreference.contains(.nativeInsert)
        let wantsPasteboardFallback = request.strategyPreference.contains(.pasteboardPasteWithRestore)

        if wantsNativeInsert {
            if let nativeResponse = attemptNativeInsert(request: request) {
                if nativeResponse.status == .sent || !wantsPasteboardFallback {
                    return nativeResponse
                }
            } else if !wantsPasteboardFallback {
                return failure(
                    requestID: request.requestID,
                    strategyUsed: .nativeInsert,
                    code: .insertRejected
                )
            }
        }

        guard wantsPasteboardFallback else {
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
        } catch {
            return failure(
                requestID: request.requestID,
                strategyUsed: .pasteboardPasteWithRestore,
                code: .insertRejected
            )
        }

        do {
            try pasteboard.replaceGeneralString(with: request.text)
        } catch {
            if restoreAfterFailure(snapshot) == .restoreFailed {
                return failure(
                    requestID: request.requestID,
                    strategyUsed: .pasteboardPasteWithRestore,
                    code: .restoreFailed
                )
            }
            return failure(
                requestID: request.requestID,
                strategyUsed: .pasteboardPasteWithRestore,
                code: .insertRejected
            )
        }

        do {
            try pasteCommandPoster.postPasteCommand()
        } catch {
            if restoreAfterFailure(snapshot) == .restoreFailed {
                return failure(
                    requestID: request.requestID,
                    strategyUsed: .pasteboardPasteWithRestore,
                    code: .restoreFailed
                )
            }
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

    private func attemptNativeInsert(
        request: NaruHelperInsertTextRequest
    ) -> NaruHelperInsertTextResponse? {
        guard let nativeTextInserter else {
            return nil
        }

        guard nativeTextInserter.canInsertTextDirectly else {
            return failure(
                requestID: request.requestID,
                strategyUsed: .nativeInsert,
                code: .permissionMissing
            )
        }

        do {
            try nativeTextInserter.insertTextDirectly(request.text)
            return NaruHelperInsertTextResponse(
                requestID: request.requestID,
                status: .sent,
                strategyUsed: .nativeInsert,
                safeFailureCode: .none
            )
        } catch let error as NaruHelperNativeTextInsertOperationError {
            return failure(
                requestID: request.requestID,
                strategyUsed: .nativeInsert,
                code: Self.failureCode(for: error)
            )
        } catch {
            return failure(
                requestID: request.requestID,
                strategyUsed: .nativeInsert,
                code: .insertRejected
            )
        }
    }

    private static func failureCode(
        for error: NaruHelperNativeTextInsertOperationError
    ) -> HelperTextBridgeFailureCode {
        switch error {
        case .permissionMissing:
            return .permissionMissing
        case .focusUnavailable:
            return .focusUnavailable
        case .insertRejected:
            return .insertRejected
        }
    }

    private func restoreAfterFailure(
        _ snapshot: NaruHelperPasteboardSnapshot
    ) -> HelperTextBridgeFailureCode {
        do {
            try pasteboard.restoreGeneralString(snapshot)
            return .none
        } catch {
            return .restoreFailed
        }
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
import ApplicationServices
import CoreGraphics

public final class MacGeneralPasteboard: NaruHelperPasteboard {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func saveGeneralString() throws -> NaruHelperPasteboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { pasteboardItem in
            NaruHelperPasteboardItemSnapshot(
                representations: pasteboardItem.types.compactMap { type in
                    pasteboardItem.data(forType: type).map { data in
                        NaruHelperPasteboardRepresentationSnapshot(
                            typeName: type.rawValue,
                            data: data
                        )
                    }
                }
            )
        } ?? []
        return NaruHelperPasteboardSnapshot(
            stringValue: pasteboard.string(forType: .string),
            items: items
        )
    }

    public func replaceGeneralString(with text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw NaruHelperTextInsertOperationError.pasteboardUnavailable
        }
    }

    public func restoreGeneralString(_ snapshot: NaruHelperPasteboardSnapshot) throws {
        pasteboard.clearContents()
        if !snapshot.items.isEmpty {
            let pasteboardItems = snapshot.items.map { snapshotItem in
                let item = NSPasteboardItem()
                for representation in snapshotItem.representations {
                    item.setData(
                        representation.data,
                        forType: NSPasteboard.PasteboardType(representation.typeName)
                    )
                }
                return item
            }
            guard pasteboard.writeObjects(pasteboardItems) else {
                throw NaruHelperTextInsertOperationError.restoreFailed
            }
            return
        }

        guard let stringValue = snapshot.stringValue else {
            return
        }
        guard pasteboard.setString(stringValue, forType: .string) else {
            throw NaruHelperTextInsertOperationError.restoreFailed
        }
    }
}

public struct MacAccessibilityFocusedTextInserter: NaruHelperNativeTextInserting {
    public init() {}

    public var canInsertTextDirectly: Bool {
        AXIsProcessTrusted()
    }

    public func insertTextDirectly(_ text: String) throws {
        guard canInsertTextDirectly else {
            throw NaruHelperNativeTextInsertOperationError.permissionMissing
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            throw NaruHelperNativeTextInsertOperationError.focusUnavailable
        }

        guard let focusedElement = Self.checkedAXUIElement(from: focusedValue) else {
            throw NaruHelperNativeTextInsertOperationError.focusUnavailable
        }

        var currentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValue
        ) == .success,
            let currentString = currentValue as? String
        else {
            throw NaruHelperNativeTextInsertOperationError.focusUnavailable
        }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else {
            throw NaruHelperNativeTextInsertOperationError.focusUnavailable
        }

        guard let selectedAXRange = Self.checkedAXValue(from: rangeValue) else {
            throw NaruHelperNativeTextInsertOperationError.focusUnavailable
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(selectedAXRange, .cfRange, &selectedRange) else {
            throw NaruHelperNativeTextInsertOperationError.focusUnavailable
        }

        let nsString = currentString as NSString
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location <= nsString.length,
              selectedRange.location + selectedRange.length <= nsString.length
        else {
            throw NaruHelperNativeTextInsertOperationError.focusUnavailable
        }

        let replacementRange = NSRange(
            location: selectedRange.location,
            length: selectedRange.length
        )
        let nextString = nsString.replacingCharacters(
            in: replacementRange,
            with: text
        )
        guard AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            nextString as CFString
        ) == .success else {
            throw NaruHelperNativeTextInsertOperationError.insertRejected
        }

        var nextRange = CFRange(
            location: selectedRange.location + (text as NSString).length,
            length: 0
        )
        if let nextAXRange = AXValueCreate(.cfRange, &nextRange) {
            _ = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextRangeAttribute as CFString,
                nextAXRange
            )
        }
    }

    private static func checkedAXUIElement(from value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func checkedAXValue(from value: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXValue.self)
    }
}

public struct MacUnicodeKeyboardTextInserter: NaruHelperNativeTextInserting {
    private static let maxUTF16UnitsPerEvent = 32
    private static let maxUTF16UnitsPerRequest = 4_096

    public init() {}

    public var canInsertTextDirectly: Bool {
        CGPreflightPostEventAccess()
    }

    public func insertTextDirectly(_ text: String) throws {
        guard canInsertTextDirectly else {
            throw NaruHelperNativeTextInsertOperationError.permissionMissing
        }

        guard let chunks = NaruHelperUnicodeEventChunker.chunks(
            for: text,
            maxUTF16UnitsPerEvent: Self.maxUTF16UnitsPerEvent,
            maxUTF16UnitsPerRequest: Self.maxUTF16UnitsPerRequest
        )
        else {
            throw NaruHelperNativeTextInsertOperationError.insertRejected
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        for chunk in chunks {
            guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
            ),
                let keyUp = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: false
                )
            else {
                throw NaruHelperNativeTextInsertOperationError.insertRejected
            }

            chunk.withUnsafeBufferPointer { buffer in
                if let baseAddress = buffer.baseAddress {
                    keyDown.keyboardSetUnicodeString(
                        stringLength: buffer.count,
                        unicodeString: baseAddress
                    )
                }
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

public enum MacNativeTextInserter {
    public static func live() -> any NaruHelperNativeTextInserting {
        NaruHelperNativeTextInserterChain([
            MacAccessibilityFocusedTextInserter(),
            MacUnicodeKeyboardTextInserter()
        ])
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
