import XCTest
@testable import NaruRemoteCore

final class TextInjectionAdapterTests: XCTestCase {
    func testAdapterReportsUnknownWhenPasteCannotBeConfirmed() {
        let client = FakeClipboardClient()
        let adapter = TextInjectionAdapter()
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID)
        draft.updateText("한글과 English 😊를 같이 입력합니다")

        let attempt = adapter.send(
            draft: &draft,
            via: client,
            pasteCommand: .commandV
        )

        XCTAssertEqual(client.clipboardPayloads, ["한글과 English 😊를 같이 입력합니다"])
        XCTAssertEqual(client.pasteCommands, [.commandV])
        XCTAssertEqual(attempt.status, .unknown)
        XCTAssertEqual(attempt.path, .vncClipboardPaste)
        XCTAssertEqual(attempt.remoteClipboardRestore, .unsupported)
        XCTAssertEqual(draft.text, "한글과 English 😊를 같이 입력합니다")
        XCTAssertEqual(draft.sendState, .unknown)
        XCTAssertNil(draft.lastFailureReason)
        XCTAssertEqual(draft.lastStatusMessage, "Paste command sent; remote app confirmation unavailable.")
    }

    func testAdapterWaitsForClipboardSettleBeforePasteCommand() {
        var sleeps: [TimeInterval] = []
        let client = FakeClipboardClient()
        let adapter = TextInjectionAdapter(
            pasteSettleDelay: 0.12,
            sleeper: { sleeps.append($0) }
        )
        var draft = ComposeDraft(sessionID: UUID(), text: "Paste after settle")

        let attempt = adapter.send(
            draft: &draft,
            via: client,
            pasteCommand: .commandV
        )

        XCTAssertEqual(sleeps, [0.12])
        XCTAssertEqual(client.events, [.clipboard("Paste after settle"), .paste(.commandV)])
        XCTAssertEqual(attempt.status, .unknown)
    }

    func testAdapterRetainsDraftWhenClipboardFails() {
        let client = FakeClipboardClient(setClipboardError: FakeClipboardError.clipboardBlocked)
        let adapter = TextInjectionAdapter()
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "원격에 보내려던 문장")

        let attempt = adapter.send(
            draft: &draft,
            via: client,
            pasteCommand: .commandV
        )

        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(draft.text, "원격에 보내려던 문장")
        XCTAssertEqual(draft.sendState, .failed)
        XCTAssertEqual(draft.lastFailureReason, "Text clipboard unavailable: Remote clipboard did not accept text.")
        XCTAssertEqual(draft.lastStatusMessage, draft.lastFailureReason)
        XCTAssertTrue(client.pasteCommands.isEmpty)
    }

    func testAdapterRetainsDraftWhenPasteCommandFails() {
        let client = FakeClipboardClient(pasteError: FakeClipboardError.pasteBlocked)
        let adapter = TextInjectionAdapter()
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "Paste me")

        let attempt = adapter.send(
            draft: &draft,
            via: client,
            pasteCommand: .controlV
        )

        XCTAssertEqual(client.clipboardPayloads, ["Paste me"])
        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(draft.text, "Paste me")
        XCTAssertEqual(draft.sendState, .failed)
        XCTAssertEqual(draft.lastFailureReason, "Paste command failed: Remote paste command could not be delivered.")
        XCTAssertEqual(draft.lastStatusMessage, draft.lastFailureReason)
    }
}

private final class FakeClipboardClient: RemoteClipboardTextClient {
    enum Event: Equatable {
        case clipboard(String)
        case paste(PasteCommand)
    }

    var clipboardPayloads: [String] = []
    var pasteCommands: [PasteCommand] = []
    var events: [Event] = []

    private let setClipboardError: Error?
    private let pasteError: Error?

    init(setClipboardError: Error? = nil, pasteError: Error? = nil) {
        self.setClipboardError = setClipboardError
        self.pasteError = pasteError
    }

    func setClipboardText(_ text: String) throws {
        if let setClipboardError {
            throw setClipboardError
        }
        clipboardPayloads.append(text)
        events.append(.clipboard(text))
    }

    func sendPasteCommand(_ command: PasteCommand) throws {
        if let pasteError {
            throw pasteError
        }
        pasteCommands.append(command)
        events.append(.paste(command))
    }
}

private enum FakeClipboardError: Error {
    case clipboardBlocked
    case pasteBlocked
}
