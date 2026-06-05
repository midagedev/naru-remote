import XCTest
import NaruHelperKit
import NaruRemoteCore

final class NaruHelperPasteboardTextInserterTests: XCTestCase {
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

    func testNativeOnlyRequestFailsUntilNativeInsertIsImplemented() throws {
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
        XCTAssertEqual(response.strategyUsed, .unsupported)
        XCTAssertEqual(response.safeFailureCode, .insertRejected)
        XCTAssertEqual(pasteboard.stagedStrings, [])
        XCTAssertEqual(poster.postCount, 0)
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

private final class FakePasteboard: NaruHelperPasteboard {
    private(set) var currentString: String?
    private(set) var stagedStrings: [String] = []
    private let restoreFails: Bool

    init(initialString: String?, restoreFails: Bool = false) {
        self.currentString = initialString
        self.restoreFails = restoreFails
    }

    func saveGeneralString() throws -> NaruHelperPasteboardSnapshot {
        NaruHelperPasteboardSnapshot(stringValue: currentString)
    }

    func replaceGeneralString(with text: String) throws {
        currentString = text
        stagedStrings.append(text)
    }

    func restoreGeneralString(_ snapshot: NaruHelperPasteboardSnapshot) throws {
        if restoreFails {
            throw NaruHelperTextInsertOperationError.restoreFailed
        }
        currentString = snapshot.stringValue
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
