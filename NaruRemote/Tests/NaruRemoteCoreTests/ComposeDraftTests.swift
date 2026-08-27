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

    /// Contract changed by spec 038 FR-004 (2026-08-27), on the founder's
    /// report that Send left the line in the field. It previously asserted the
    /// opposite — "retains draft" — on the reasoning that an unconfirmed send
    /// should stay retryable. That reasoning traded one risk for a worse one:
    /// the keystroke path, which is the default delivery, can *never* be
    /// confirmed, so "keep until confirmed" meant "never clear", and the retry
    /// it protected re-runs a command in a terminal that already ran.
    func testAnUnconfirmedSendStillEmptiesTheDraft() {
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "한글과 English 😊")

        draft.markUnknown(message: "Confirmation unavailable")

        XCTAssertEqual(
            draft.text,
            "",
            "The bytes left the device; only the remote app's reaction is unknown"
        )
        XCTAssertEqual(draft.sendState, .unknown)
        XCTAssertNil(draft.lastFailureReason)
        XCTAssertEqual(draft.lastStatusMessage, "Confirmation unavailable")
    }

    /// Same change, through the paste-specific entry point (spec 038 FR-004).
    func testPasteDispatchedEmptiesTheDraft() {
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "한글과 English 😊")

        draft.markPasteDispatched(message: "Paste command sent")

        XCTAssertEqual(draft.text, "")
        XCTAssertEqual(draft.sendState, .unknown)
        XCTAssertNil(draft.lastFailureReason)
        XCTAssertEqual(draft.lastStatusMessage, "Paste command sent")
    }

    /// Spec 038 FR-004: Send is a submit (spec 015 v1.1 FR-010), so a
    /// confirmed send empties the field. Previously
    /// `testSuccessfulSendDoesNotClearByDefault`.
    func testASuccessfulSendEmptiesTheDraft() {
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "Keep until UI confirms")

        draft.markSent()

        XCTAssertEqual(draft.text, "")
        XCTAssertEqual(draft.sendState, .sent)
    }

    /// The other half of the rule, and the one that makes it safe: a failure is
    /// the only outcome where the field is the only copy (spec 038 FR-004).
    func testAFailedSendKeepsTheDraftBecauseNothingElseHasIt() {
        let sessionID = UUID()
        var draft = ComposeDraft(sessionID: sessionID, text: "rm -rf nothing")

        draft.markFailed(reason: "Paste blocked by remote app")

        XCTAssertEqual(draft.text, "rm -rf nothing")
        XCTAssertFalse(ComposeDraft.outcomeConsumesDraft(.failed))
        XCTAssertTrue(ComposeDraft.outcomeConsumesDraft(.sent))
        XCTAssertTrue(ComposeDraft.outcomeConsumesDraft(.unknown))
        XCTAssertFalse(ComposeDraft.outcomeConsumesDraft(.sending))
    }
}
