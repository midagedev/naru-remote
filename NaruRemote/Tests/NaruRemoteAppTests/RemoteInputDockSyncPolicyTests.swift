import XCTest
@testable import NaruRemoteApp

final class RemoteInputDockSyncPolicyTests: XCTestCase {
    func testAppliesIdenticalExternalText() {
        XCTAssertTrue(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "hello",
                lastAppliedInitialText: "hello",
                currentText: "hello",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: true
            )
        )
    }

    func testDefersNonEmptyExternalTextWhileMarkedTextIsActive() {
        XCTAssertFalse(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "old snapshot",
                lastAppliedInitialText: "prior",
                currentText: "한글 조합",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: true
            )
        )
    }

    func testDefersNonEmptyExternalTextWhileFocusedLocalDraftHasText() {
        XCTAssertFalse(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "server echo",
                lastAppliedInitialText: "prior",
                currentText: "local edit",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: false
            )
        )
    }

    func testDefersExternalClearWhileMarkedTextIsActive() {
        XCTAssertFalse(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "",
                lastAppliedInitialText: "sent text",
                currentText: "한글",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: true
            )
        )
    }

    func testAppliesExternalClearWhenNoMarkedTextIsActive() {
        XCTAssertTrue(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "",
                lastAppliedInitialText: "sent text",
                currentText: "sent text",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: false
            )
        )
    }

    func testAppliesExternalTextWhenEditorIsNotFocused() {
        XCTAssertTrue(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "restored draft",
                lastAppliedInitialText: "prior",
                currentText: "prior",
                isDirectModeActive: false,
                isComposeFieldFocused: false,
                hasMarkedText: false
            )
        )
    }

    func testDirectModeAlwaysAllowsModelDrivenSync() {
        XCTAssertTrue(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "model value",
                lastAppliedInitialText: "prior",
                currentText: "local edit",
                isDirectModeActive: true,
                isComposeFieldFocused: true,
                hasMarkedText: true
            )
        )
    }

    func testResolvedCommittedComposeTextPrefersCommittedText() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCommittedComposeText(
                committedText: "완성된 문장",
                markedTextBeforeCommit: "조합중",
                currentTextBeforeCommit: "이전 값"
            ),
            "완성된 문장"
        )
    }

    func testResolvedCommittedComposeTextFallsBackToMarkedTextWhenUIKitReturnsEmpty() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCommittedComposeText(
                committedText: "",
                markedTextBeforeCommit: "한",
                currentTextBeforeCommit: "stale fallback"
            ),
            "한"
        )
    }

    func testResolvedCommittedComposeTextUsesCurrentTextWhenCommittedSnapshotDropsMarkedText() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCommittedComposeText(
                committedText: "입력느",
                markedTextBeforeCommit: "낌",
                currentTextBeforeCommit: "입력느낌"
            ),
            "입력느낌"
        )
    }

    func testResolvedCommittedComposeTextKeepsCommittedTextWhenMarkedTextIsPresent() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCommittedComposeText(
                committedText: "입력느낌",
                markedTextBeforeCommit: "낌",
                currentTextBeforeCommit: "입력느낌"
            ),
            "입력느낌"
        )
    }

    func testResolvedCommittedComposeTextKeepsEmptyEditorEmpty() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCommittedComposeText(
                committedText: "",
                markedTextBeforeCommit: nil,
                currentTextBeforeCommit: "stale fallback"
            ),
            ""
        )
    }

    func testResolvedCommittedComposeTextUsesCurrentTextWhenViewSnapshotIsMissing() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCommittedComposeText(
                committedText: nil,
                markedTextBeforeCommit: nil,
                currentTextBeforeCommit: "컨트롤러 값"
            ),
            "컨트롤러 값"
        )
    }

    func testResolvedCurrentComposeTextFallsBackToMarkedTextWhenViewSnapshotIsEmpty() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCurrentComposeText(
                viewText: "",
                markedText: "한",
                controllerText: "",
                fallback: ""
            ),
            "한"
        )
    }

    func testResolvedCurrentComposeTextPrefersViewTextWhenAvailable() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCurrentComposeText(
                viewText: "입력느낌",
                markedText: "낌",
                controllerText: "입력느",
                fallback: ""
            ),
            "입력느낌"
        )
    }
}
