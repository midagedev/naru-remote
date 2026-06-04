import XCTest
@testable import NaruRemoteCore

final class ComposeDraftTests: XCTestCase {
    func testUnicodeDraftIsPreservedExactly() {
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID)
        let text = "한글과 English 😊를 같이 입력합니다\nTab\tCombining e\u{301}"

        draft.updateText(text)

        XCTAssertEqual(draft.text, text)
        XCTAssertEqual(draft.sendState, .ready)
        XCTAssertTrue(draft.canSend)
    }

    func testFailedSendRetainsDraftText() {
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "한글과 English 😊")

        draft.markFailed(reason: "Paste blocked by remote app")

        XCTAssertEqual(draft.text, "한글과 English 😊")
        XCTAssertEqual(draft.sendState, .failed)
        XCTAssertEqual(draft.lastFailureReason, "Paste blocked by remote app")
        XCTAssertEqual(draft.lastStatusMessage, "Paste blocked by remote app")
    }

    func testUnknownSendRetainsDraftWithoutFailureReason() {
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "한글과 English 😊")

        draft.markUnknown(message: "Confirmation unavailable")

        XCTAssertEqual(draft.text, "한글과 English 😊")
        XCTAssertEqual(draft.sendState, .unknown)
        XCTAssertNil(draft.lastFailureReason)
        XCTAssertEqual(draft.lastStatusMessage, "Confirmation unavailable")
    }

    func testPasteDispatchedClearsDraftForNextInput() {
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "한글과 English 😊")

        draft.markPasteDispatched(message: "Paste command sent")

        XCTAssertEqual(draft.text, "")
        XCTAssertEqual(draft.sendState, .unknown)
        XCTAssertNil(draft.lastFailureReason)
        XCTAssertEqual(draft.lastStatusMessage, "Paste command sent")
    }

    func testSuccessfulSendDoesNotClearByDefault() {
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "Keep until UI confirms")

        draft.markSent()

        XCTAssertEqual(draft.text, "Keep until UI confirms")
        XCTAssertEqual(draft.sendState, .sent)
    }
}
