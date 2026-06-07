import XCTest
import NaruHelperKit
import NaruRemoteCore

final class NaruHelperPasteboardTextInserterTests: XCTestCase {
    func testUnicodeEventChunkerPreservesSurrogatePairsAtChunkBoundaries() throws {
        let chunks = try XCTUnwrap(NaruHelperUnicodeEventChunker.chunks(
            for: "ab😊cd",
            maxUTF16UnitsPerEvent: 3,
            maxUTF16UnitsPerRequest: 64
        ))

        XCTAssertEqual(chunks.map(\.count), [2, 3, 1])
        XCTAssertEqual(String(decoding: chunks.flatMap { $0 }, as: UTF16.self), "ab😊cd")
        for chunk in chunks {
            XCTAssertFalse(isHighSurrogate(chunk.last))
            XCTAssertFalse(isLowSurrogate(chunk.first))
        }
    }

    func testUnicodeEventChunkerRejectsOversizedRequest() throws {
        let chunks = NaruHelperUnicodeEventChunker.chunks(
            for: "abcdef",
            maxUTF16UnitsPerEvent: 3,
            maxUTF16UnitsPerRequest: 5
        )

        XCTAssertNil(chunks)
    }

    func testNativeInsertRunsBeforePasteboardFallbackAndDoesNotTouchPasteboard() throws {
        let pasteboard = FakePasteboard(initialString: "previous clipboard")
        let poster = FakePasteCommandPoster()
        let native = FakeNativeTextInserter()
        let request = try makeRequest(text: "한글과 English 😊")
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            nativeTextInserter: native
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(response.status, .sent)
        XCTAssertEqual(response.strategyUsed, .nativeInsert)
        XCTAssertEqual(response.safeFailureCode, .none)
        XCTAssertEqual(native.insertedTexts, ["한글과 English 😊"])
        XCTAssertEqual(pasteboard.stagedStrings, [])
        XCTAssertEqual(pasteboard.restoreCount, 0)
        XCTAssertEqual(poster.postCount, 0)
        XCTAssertEqual(pasteboard.currentString, "previous clipboard")
    }

    func testNativeInsertFailureFallsBackToPasteboardWhenRequested() throws {
        let pasteboard = FakePasteboard(initialString: "previous clipboard")
        let poster = FakePasteCommandPoster()
        let native = FakeNativeTextInserter(error: .focusUnavailable)
        let request = try makeRequest(text: "한글과 English 😊")
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            nativeTextInserter: native
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.status, .sent)
        XCTAssertEqual(response.strategyUsed, .pasteboardPasteWithRestore)
        XCTAssertEqual(response.safeFailureCode, .none)
        XCTAssertEqual(native.insertedTexts, [])
        XCTAssertEqual(pasteboard.stagedStrings, ["한글과 English 😊"])
        XCTAssertEqual(pasteboard.currentString, "previous clipboard")
        XCTAssertEqual(poster.postCount, 1)
    }

    func testNativeInserterChainUsesSecondNativeStrategyBeforePasteboardFallback() throws {
        let pasteboard = FakePasteboard(initialString: "previous clipboard")
        let poster = FakePasteCommandPoster()
        let firstNative = FakeNativeTextInserter(error: .focusUnavailable)
        let secondNative = FakeNativeTextInserter()
        let nativeChain = NaruHelperNativeTextInserterChain([firstNative, secondNative])
        let request = try makeRequest(text: "한글과 English 😊")
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            nativeTextInserter: nativeChain
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.status, .sent)
        XCTAssertEqual(response.strategyUsed, .nativeInsert)
        XCTAssertEqual(secondNative.insertedTexts, ["한글과 English 😊"])
        XCTAssertEqual(pasteboard.stagedStrings, [])
        XCTAssertEqual(poster.postCount, 0)
        XCTAssertEqual(pasteboard.currentString, "previous clipboard")
    }

    func testNativeOnlyRequestReportsNativeFailureWithoutTouchingPasteboard() throws {
        let pasteboard = FakePasteboard(initialString: "previous clipboard")
        let poster = FakePasteCommandPoster()
        let native = FakeNativeTextInserter(error: .focusUnavailable)
        let request = try makeRequest(
            text: "한글과 English 😊",
            strategyPreference: [.nativeInsert]
        )
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster,
            nativeTextInserter: native
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.strategyUsed, .nativeInsert)
        XCTAssertEqual(response.safeFailureCode, .focusUnavailable)
        XCTAssertEqual(pasteboard.stagedStrings, [])
        XCTAssertEqual(pasteboard.restoreCount, 0)
        XCTAssertEqual(poster.postCount, 0)
        XCTAssertEqual(pasteboard.currentString, "previous clipboard")
    }

    func testNativeOnlyRequestFailsWhenNativeInserterIsUnavailable() throws {
        let pasteboard = FakePasteboard(initialString: nil)
        let poster = FakePasteCommandPoster()
        let request = try makeRequest(
            text: "한글과 English 😊",
            strategyPreference: [.nativeInsert]
        )
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.strategyUsed, .nativeInsert)
        XCTAssertEqual(response.safeFailureCode, .insertRejected)
        XCTAssertEqual(pasteboard.stagedStrings, [])
        XCTAssertEqual(poster.postCount, 0)
    }

    func testPasteboardFallbackStagesTextPostsPasteAndRestoresPreviousText() throws {
        let pasteboard = FakePasteboard(initialString: "previous clipboard")
        let poster = FakePasteCommandPoster()
        let request = try makeRequest(text: "한글과 English 😊")
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(response.status, .sent)
        XCTAssertEqual(response.strategyUsed, .pasteboardPasteWithRestore)
        XCTAssertEqual(response.safeFailureCode, .none)
        XCTAssertEqual(pasteboard.stagedStrings, ["한글과 English 😊"])
        XCTAssertEqual(poster.postCount, 1)
        XCTAssertEqual(pasteboard.currentString, "previous clipboard")
    }

    func testMissingPostEventPermissionDoesNotTouchPasteboard() throws {
        let pasteboard = FakePasteboard(initialString: "previous clipboard")
        let poster = FakePasteCommandPoster(canPostPasteCommand: false)
        let request = try makeRequest(text: "한글과 English 😊")
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.safeFailureCode, .permissionMissing)
        XCTAssertEqual(pasteboard.stagedStrings, [])
        XCTAssertEqual(poster.postCount, 0)
        XCTAssertEqual(pasteboard.currentString, "previous clipboard")
    }

    func testReplaceFailureAttemptsRestoreBeforeReturningInsertRejected() throws {
        let pasteboard = FakePasteboard(initialString: "previous clipboard", replaceFails: true)
        let poster = FakePasteCommandPoster()
        let request = try makeRequest(text: "한글과 English 😊")
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.safeFailureCode, .insertRejected)
        XCTAssertEqual(pasteboard.restoreCount, 1)
        XCTAssertEqual(pasteboard.currentString, "previous clipboard")
        XCTAssertEqual(poster.postCount, 0)
    }

    func testReplaceFailureRestoresNonStringPasteboardSnapshot() throws {
        let imageSnapshot = NaruHelperPasteboardItemSnapshot(
            representations: [
                NaruHelperPasteboardRepresentationSnapshot(
                    typeName: "public.png",
                    data: Data([0x89, 0x50, 0x4e, 0x47])
                )
            ]
        )
        let pasteboard = FakePasteboard(
            initialString: nil,
            initialItems: [imageSnapshot],
            replaceFails: true
        )
        let poster = FakePasteCommandPoster()
        let request = try makeRequest(text: "한글과 English 😊")
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.safeFailureCode, .insertRejected)
        XCTAssertEqual(pasteboard.restoreCount, 1)
        XCTAssertEqual(pasteboard.currentString, nil)
        XCTAssertEqual(pasteboard.currentItems, [imageSnapshot])
        XCTAssertEqual(poster.postCount, 0)
    }

    func testReplaceFailureReportsRestoreFailureWhenRestoreAlsoFails() throws {
        let pasteboard = FakePasteboard(
            initialString: "previous clipboard",
            replaceFails: true,
            restoreFails: true
        )
        let poster = FakePasteCommandPoster()
        let request = try makeRequest(text: "한글과 English 😊")
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.safeFailureCode, .restoreFailed)
        XCTAssertEqual(pasteboard.restoreCount, 1)
        XCTAssertEqual(poster.postCount, 0)
    }

    func testPasteCommandFailureReportsRestoreFailureWhenRestoreFails() throws {
        let pasteboard = FakePasteboard(initialString: "previous clipboard", restoreFails: true)
        let poster = FakePasteCommandPoster(shouldThrow: true)
        let request = try makeRequest(text: "한글과 English 😊")
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.safeFailureCode, .restoreFailed)
        XCTAssertEqual(pasteboard.restoreCount, 1)
        XCTAssertEqual(poster.postCount, 0)
    }

    func testRestoreFailureReturnsFixedRestoreFailureCode() throws {
        let pasteboard = FakePasteboard(initialString: "previous clipboard", restoreFails: true)
        let poster = FakePasteCommandPoster()
        let request = try makeRequest(text: "한글과 English 😊")
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: pasteboard,
            pasteCommandPoster: poster
        )

        let response = inserter.insertText(request: request)

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.strategyUsed, .pasteboardPasteWithRestore)
        XCTAssertEqual(response.safeFailureCode, .restoreFailed)
        XCTAssertEqual(poster.postCount, 1)
    }

    private func makeRequest(
        text: String,
        strategyPreference: [HelperTextInsertStrategy] = [.nativeInsert, .pasteboardPasteWithRestore]
    ) throws -> NaruHelperInsertTextRequest {
        NaruHelperInsertTextRequest(
            requestID: try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
            payloadEncoding: .utf8ExtensionRequired,
            payloadSizeBucket: HelperTextPayloadSizeBucket.bucket(utf8ByteCount: text.utf8.count),
            strategyPreference: strategyPreference,
            text: text
        )
    }
}

private func isHighSurrogate(_ value: UInt16?) -> Bool {
    guard let value else { return false }
    return (0xD800...0xDBFF).contains(value)
}

private func isLowSurrogate(_ value: UInt16?) -> Bool {
    guard let value else { return false }
    return (0xDC00...0xDFFF).contains(value)
}

private final class FakeNativeTextInserter: NaruHelperNativeTextInserting {
    private(set) var insertedTexts: [String] = []
    var canInsertTextDirectly: Bool
    private let error: NaruHelperNativeTextInsertOperationError?

    init(
        canInsertTextDirectly: Bool = true,
        error: NaruHelperNativeTextInsertOperationError? = nil
    ) {
        self.canInsertTextDirectly = canInsertTextDirectly
        self.error = error
    }

    func insertTextDirectly(_ text: String) throws {
        if let error {
            throw error
        }
        insertedTexts.append(text)
    }
}

private final class FakePasteboard: NaruHelperPasteboard {
    private(set) var currentString: String?
    private(set) var currentItems: [NaruHelperPasteboardItemSnapshot]
    private(set) var stagedStrings: [String] = []
    private(set) var restoreCount = 0
    private let replaceFails: Bool
    private let restoreFails: Bool

    init(
        initialString: String?,
        initialItems: [NaruHelperPasteboardItemSnapshot] = [],
        replaceFails: Bool = false,
        restoreFails: Bool = false
    ) {
        self.currentString = initialString
        self.currentItems = initialItems
        self.replaceFails = replaceFails
        self.restoreFails = restoreFails
    }

    func saveGeneralString() throws -> NaruHelperPasteboardSnapshot {
        NaruHelperPasteboardSnapshot(stringValue: currentString, items: currentItems)
    }

    func replaceGeneralString(with text: String) throws {
        if replaceFails {
            currentString = nil
            currentItems = []
            throw NaruHelperTextInsertOperationError.pasteboardUnavailable
        }
        currentString = text
        currentItems = []
        stagedStrings.append(text)
    }

    func restoreGeneralString(_ snapshot: NaruHelperPasteboardSnapshot) throws {
        restoreCount += 1
        if restoreFails {
            throw NaruHelperTextInsertOperationError.restoreFailed
        }
        currentString = snapshot.stringValue
        currentItems = snapshot.items
    }
}

private struct FakePasteCommandPoster: NaruHelperPasteCommandPosting {
    var canPostPasteCommand: Bool
    private let shouldThrow: Bool
    private let recorder: Recorder

    init(canPostPasteCommand: Bool = true, shouldThrow: Bool = false) {
        self.canPostPasteCommand = canPostPasteCommand
        self.shouldThrow = shouldThrow
        self.recorder = Recorder()
    }

    var postCount: Int { recorder.postCount }

    func postPasteCommand() throws {
        if shouldThrow {
            throw NaruHelperTextInsertOperationError.pasteCommandFailed
        }
        recorder.postCount += 1
    }

    private final class Recorder {
        var postCount = 0
    }
}
