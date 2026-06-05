import XCTest
@testable import NaruRemoteCore

final class TextInjectionAdapterTests: XCTestCase {
    func testPayloadEncodingClassificationDoesNotExposeDraftText() {
        XCTAssertEqual(TextInjectionPayloadEncoding.classify("plain ASCII"), .ascii)
        XCTAssertEqual(TextInjectionPayloadEncoding.classify("café"), .latin1)
        XCTAssertEqual(TextInjectionPayloadEncoding.classify("한글과 😊"), .utf8ExtensionRequired)
    }

    func testAdapterReportsUnknownWhenASCIIPasteCannotBeConfirmed() {
        let client = FakeClipboardClient()
        let adapter = TextInjectionAdapter()
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID)
        draft.updateText("plain ASCII input")

        let attempt = adapter.send(
            draft: &draft,
            via: client,
            pasteCommand: .commandV
        )

        XCTAssertEqual(client.clipboardPayloads, ["plain ASCII input"])
        XCTAssertEqual(client.pasteCommands, [.commandV])
        XCTAssertEqual(attempt.status, .unknown)
        XCTAssertEqual(attempt.path, .vncClipboardPaste)
        XCTAssertEqual(attempt.pasteCommand, .commandV)
        XCTAssertEqual(attempt.payloadEncoding, .ascii)
        XCTAssertEqual(attempt.clipboardTransferMode, .legacyClientCutText)
        XCTAssertEqual(attempt.utf8ClipboardSupport, .unknown)
        XCTAssertEqual(attempt.clipboardSetStatus, .succeeded)
        XCTAssertEqual(attempt.pasteCommandStatus, .succeeded)
        XCTAssertEqual(attempt.remoteClipboardRestore, .unsupported)
        XCTAssertEqual(draft.text, "plain ASCII input")
        XCTAssertEqual(draft.sendState, .unknown)
        XCTAssertNil(draft.lastFailureReason)
        XCTAssertEqual(
            draft.lastStatusMessage,
            "Paste command sent; remote app confirmation unavailable."
        )
    }

    func testAdapterAllowsBestEffortUTF8ComposeWhenServerSupportIsUnknown() {
        let client = FakeClipboardClient()
        let adapter = TextInjectionAdapter()
        var draft = ComposeDraft(sessionID: UUID(), text: "한글과 English 😊")

        let attempt = adapter.send(
            draft: &draft,
            via: client,
            pasteCommand: .commandV
        )

        XCTAssertEqual(client.clipboardPayloads, ["한글과 English 😊"])
        XCTAssertEqual(client.pasteCommands, [.commandV])
        XCTAssertEqual(attempt.status, .unknown)
        XCTAssertEqual(attempt.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(attempt.clipboardTransferMode, .legacyClientCutText)
        XCTAssertEqual(attempt.utf8ClipboardSupport, .unknown)
        XCTAssertEqual(attempt.clipboardSetStatus, .succeeded)
        XCTAssertEqual(attempt.pasteCommandStatus, .succeeded)
        XCTAssertEqual(draft.sendState, .unknown)
        XCTAssertNil(draft.lastFailureReason)
        XCTAssertEqual(
            draft.lastStatusMessage,
            "Paste command sent through legacy VNC clipboard; this server has not confirmed UTF-8 clipboard support, so Korean/CJK text may paste incorrectly."
        )
    }

    func testAdapterRejectsUTF8ComposeWhenServerReportsUnsupportedClipboard() {
        let client = FakeClipboardClient(utf8ClipboardSupport: .unsupported)
        let adapter = TextInjectionAdapter()
        var draft = ComposeDraft(sessionID: UUID(), text: "한글과 English 😊")

        let attempt = adapter.send(
            draft: &draft,
            via: client,
            pasteCommand: .commandV
        )

        XCTAssertTrue(client.clipboardPayloads.isEmpty)
        XCTAssertTrue(client.pasteCommands.isEmpty)
        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(attempt.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(attempt.clipboardTransferMode, .legacyClientCutText)
        XCTAssertEqual(attempt.utf8ClipboardSupport, .unsupported)
        XCTAssertEqual(attempt.clipboardSetStatus, .notAttempted)
        XCTAssertEqual(attempt.pasteCommandStatus, .notAttempted)
        XCTAssertEqual(draft.sendState, .failed)
        XCTAssertEqual(
            draft.lastFailureReason,
            "Text clipboard unavailable: This VNC server reported that UTF-8 clipboard support is unavailable, so Korean/CJK/emoji Compose text cannot be sent reliably."
        )
    }

    func testAdapterReportsExtendedClipboardWhenServerConfirmsUTF8Support() {
        let client = FakeClipboardClient(utf8ClipboardSupport: .supported)
        let adapter = TextInjectionAdapter()
        var draft = ComposeDraft(sessionID: UUID(), text: "한글 Extended 😊")

        let attempt = adapter.send(
            draft: &draft,
            via: client,
            pasteCommand: .commandV
        )

        XCTAssertEqual(attempt.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(attempt.clipboardTransferMode, .extendedClipboardUTF8)
        XCTAssertEqual(attempt.utf8ClipboardSupport, .supported)
        XCTAssertEqual(draft.lastStatusMessage, "Paste command sent through UTF-8 clipboard; remote app confirmation unavailable.")
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
        XCTAssertEqual(attempt.payloadEncoding, .ascii)
        XCTAssertEqual(attempt.clipboardSetStatus, .succeeded)
        XCTAssertEqual(attempt.pasteCommandStatus, .succeeded)
    }

    func testAdapterRetainsDraftWhenClipboardFails() {
        let client = FakeClipboardClient(setClipboardError: FakeClipboardError.clipboardBlocked)
        let adapter = TextInjectionAdapter()
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "Clipboard should fail")

        let attempt = adapter.send(
            draft: &draft,
            via: client,
            pasteCommand: .commandV
        )

        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(attempt.clipboardSetStatus, .failed)
        XCTAssertEqual(attempt.pasteCommandStatus, .notAttempted)
        XCTAssertEqual(draft.text, "Clipboard should fail")
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
        XCTAssertEqual(attempt.clipboardSetStatus, .succeeded)
        XCTAssertEqual(attempt.pasteCommandStatus, .failed)
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
    let utf8ClipboardSupport: RemoteClipboardUTF8Support

    private let setClipboardError: Error?
    private let pasteError: Error?

    init(
        utf8ClipboardSupport: RemoteClipboardUTF8Support = .unknown,
        setClipboardError: Error? = nil,
        pasteError: Error? = nil
    ) {
        self.utf8ClipboardSupport = utf8ClipboardSupport
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
