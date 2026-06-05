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

    func testDefersExternalClearWhileFocusedLocalDraftIsAheadOfModel() {
        XCTAssertFalse(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "",
                lastAppliedInitialText: "",
                currentText: "입력느낌",
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

    func testPropagatesLocalComposeTextToModelWhileMarkedTextIsActive() {
        XCTAssertTrue(
            RemoteInputDockView.shouldPropagateLocalComposeTextToModel(
                isDirectModeActive: false,
                hasMarkedText: true
            )
        )
    }

    func testPropagatesLocalComposeTextAfterMarkedTextCommits() {
        XCTAssertTrue(
            RemoteInputDockView.shouldPropagateLocalComposeTextToModel(
                isDirectModeActive: false,
                hasMarkedText: false
            )
        )
    }

    func testSkipsDuplicateLocalComposeTextPropagation() {
        XCTAssertFalse(
            RemoteInputDockView.shouldPropagateLocalComposeTextToModel(
                newValue: "입력느낌",
                lastPropagatedText: "입력느낌",
                isDirectModeActive: false,
                hasMarkedText: false
            )
        )
    }

    func testPropagatesCommittedComposeTextOnceItDiffersFromLastPropagation() {
        XCTAssertTrue(
            RemoteInputDockView.shouldPropagateLocalComposeTextToModel(
                newValue: "입력느낌",
                lastPropagatedText: "입력느",
                isDirectModeActive: false,
                hasMarkedText: false
            )
        )
    }

    func testDoesNotPropagateHiddenComposeTextWhileDirectModeIsActive() {
        XCTAssertFalse(
            RemoteInputDockView.shouldPropagateLocalComposeTextToModel(
                isDirectModeActive: true,
                hasMarkedText: false
            )
        )
    }

    func testDetectsMarkedTextCommitTransition() {
        XCTAssertTrue(
            RemoteInputDockView.didCommitMarkedComposeText(
                previouslyHadMarkedText: true,
                hasMarkedText: false
            )
        )
    }

    func testDoesNotTreatOngoingMarkedTextAsCommitted() {
        XCTAssertFalse(
            RemoteInputDockView.didCommitMarkedComposeText(
                previouslyHadMarkedText: true,
                hasMarkedText: true
            )
        )
    }

    func testDoesNotTreatPlainTypingAsMarkedTextCommit() {
        XCTAssertFalse(
            RemoteInputDockView.didCommitMarkedComposeText(
                previouslyHadMarkedText: false,
                hasMarkedText: false
            )
        )
    }

    func testAdoptsUIKitComposeTextChangeWhileMarkedTextUpdatesLocalBinding() {
        XCTAssertTrue(
            RemoteInputDockView.shouldAdoptUIKitComposeTextChange(
                resolvedText: "입력느낌",
                currentBindingText: "입력느"
            )
        )
    }

    func testSkipsDuplicateUIKitComposeTextAdoption() {
        XCTAssertFalse(
            RemoteInputDockView.shouldAdoptUIKitComposeTextChange(
                resolvedText: "입력느낌",
                currentBindingText: "입력느낌"
            )
        )
    }

    func testDefersUIKitBindingWriteWhileMarkedTextIsActive() {
        XCTAssertTrue(
            RemoteInputDockView.shouldDeferUIKitComposeBindingWrite(
                hasMarkedText: true,
                isFirstResponder: true,
                proposedText: "입력느",
                lastAppliedBindingText: "입력느",
                currentUIKitText: "입력느낌"
            )
        )
    }

    func testDefersStaleUIKitBindingWriteAfterMarkedTextCommit() {
        XCTAssertTrue(
            RemoteInputDockView.shouldDeferUIKitComposeBindingWrite(
                hasMarkedText: false,
                isFirstResponder: true,
                proposedText: "입력느",
                lastAppliedBindingText: "입력느",
                currentUIKitText: "입력느낌"
            )
        )
    }

    func testDefersExternalUIKitBindingClearWhileFocusedEditorHasLocalText() {
        XCTAssertTrue(
            RemoteInputDockView.shouldDeferUIKitComposeBindingWrite(
                hasMarkedText: false,
                isFirstResponder: true,
                proposedText: "",
                lastAppliedBindingText: "입력느",
                currentUIKitText: "입력느낌"
            )
        )
    }

    func testDefersExternalUIKitBindingPrefixWhileFocusedEditorHasSuffix() {
        XCTAssertTrue(
            RemoteInputDockView.shouldDeferUIKitComposeBindingWrite(
                hasMarkedText: false,
                isFirstResponder: true,
                proposedText: "입력느",
                lastAppliedBindingText: "입력느",
                currentUIKitText: "입력느낌"
            )
        )
    }

    func testAllowsUIKitBindingWriteWhenFocusedEditorAlreadyMatchesShorterText() {
        XCTAssertFalse(
            RemoteInputDockView.shouldDeferUIKitComposeBindingWrite(
                hasMarkedText: false,
                isFirstResponder: true,
                proposedText: "입력느",
                lastAppliedBindingText: "입력느낌",
                currentUIKitText: "입력느"
            )
        )
    }

    func testAllowsPlainUIKitBindingWriteWhenTextViewMatchesModel() {
        XCTAssertFalse(
            RemoteInputDockView.shouldDeferUIKitComposeBindingWrite(
                hasMarkedText: false,
                isFirstResponder: true,
                proposedText: "hello",
                lastAppliedBindingText: "hello",
                currentUIKitText: "hello"
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

    func testResolvedCommittedComposeTextKeepsCurrentTextWhenCommittedSnapshotIsPrefix() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCommittedComposeText(
                committedText: "입력느",
                markedTextBeforeCommit: nil,
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

    func testResolvedCommittedComposeTextKeepsCurrentTextWhenMarkedCommitSnapshotIsEmpty() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCommittedComposeText(
                committedText: "",
                markedTextBeforeCommit: "낌",
                currentTextBeforeCommit: "입력느낌"
            ),
            "입력느낌"
        )
    }

    func testResolvedCommittedComposeTextKeepsCurrentTextWhenMarkedCommitSnapshotIsMissing() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCommittedComposeText(
                committedText: nil,
                markedTextBeforeCommit: "낌",
                currentTextBeforeCommit: "입력느낌"
            ),
            "입력느낌"
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

    func testResolvedCurrentComposeTextKeepsControllerWhenMarkedSuffixIsMissingFromView() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCurrentComposeText(
                viewText: "입력느",
                markedText: "낌",
                controllerText: "입력느낌",
                fallback: "입력느"
            ),
            "입력느낌"
        )
    }

    func testResolvedCurrentComposeTextCombinesFallbackPrefixWithMarkedSuffix() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCurrentComposeText(
                viewText: "입력느",
                markedText: "낌",
                controllerText: "",
                fallback: "입력느"
            ),
            "입력느낌"
        )
    }

    func testResolvedMarkedCommitKeepsFallbackSuffixWhenUIKitCommitSnapshotIsShort() {
        let beforeCommit = RemoteInputDockView.resolvedCurrentComposeText(
            viewText: "입력느",
            markedText: "낌",
            controllerText: "입력느",
            fallback: "입력느"
        )

        XCTAssertEqual(
            RemoteInputDockView.resolvedCommittedComposeText(
                committedText: "입력느",
                markedTextBeforeCommit: "낌",
                currentTextBeforeCommit: beforeCommit
            ),
            "입력느낌"
        )
    }

    func testResolvedStabilizedComposeTextKeepsImmediateWhenNextSnapshotDropsSuffix() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedStabilizedComposeText(
                immediateText: "입력느낌",
                stabilizedText: "입력느"
            ),
            "입력느낌"
        )
    }

    func testResolvedStabilizedComposeTextUsesNextSnapshotWhenItHasCommittedCandidate() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedStabilizedComposeText(
                immediateText: "입력느",
                stabilizedText: "입력느낌"
            ),
            "입력느낌"
        )
    }

    func testResolvedStabilizedComposeTextFallsBackWhenNextSnapshotIsEmpty() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedStabilizedComposeText(
                immediateText: "입력느낌",
                stabilizedText: ""
            ),
            "입력느낌"
        )
    }

    func testResolvedStabilizedComposeTextUsesMostCompleteDelayedSnapshot() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedStabilizedComposeText(
                immediateText: "입력느",
                stabilizedSnapshots: ["", "입력느", "입력느낌"]
            ),
            "입력느낌"
        )
    }

    func testResolvedStabilizedComposeTextDoesNotReplaceCompleteTextWithDelayedPrefix() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedStabilizedComposeText(
                immediateText: "입력느낌",
                stabilizedSnapshots: ["입력느", ""]
            ),
            "입력느낌"
        )
    }

    func testResolvedStabilizedComposeTextDoesNotReplaceCompleteTextWithDelayedFragment() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedStabilizedComposeText(
                immediateText: "입력느낌",
                stabilizedText: "느낌"
            ),
            "입력느낌"
        )
    }

    func testResolvedStabilizedComposeTextUsesShorterSnapshotWhenItIsARealEdit() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedStabilizedComposeText(
                immediateText: "입력느낌",
                stabilizedText: "수정"
            ),
            "수정"
        )
    }

    func testComposeSendStabilizationWindowCoversDelayedIMECommit() {
        XCTAssertGreaterThanOrEqual(RemoteInputDockView.composeSendStabilizationSnapshotCount, 20)
        XCTAssertGreaterThanOrEqual(
            RemoteInputDockView.composeSendStabilizationDelayNanoseconds,
            16_000_000
        )
        let delayedCommitSnapshots = Array(
            repeating: "입력느",
            count: RemoteInputDockView.composeSendStabilizationSnapshotCount - 1
        ) + ["입력느낌"]
        XCTAssertEqual(
            delayedCommitSnapshots.count,
            RemoteInputDockView.composeSendStabilizationSnapshotCount
        )
        XCTAssertEqual(
            RemoteInputDockView.resolvedStabilizedComposeText(
                immediateText: "입력느",
                stabilizedSnapshots: delayedCommitSnapshots
            ),
            "입력느낌"
        )
    }

    func testCompactStatusHidesDefaultReadyCopy() {
        XCTAssertFalse(
            RemoteInputDockView.shouldShowCompactStatusText(
                hasStatus: false,
                statusText: "Ready to compose locally"
            )
        )
    }

    func testCompactStatusShowsActionableSendState() {
        XCTAssertTrue(
            RemoteInputDockView.shouldShowCompactStatusText(
                hasStatus: true,
                statusText: "Paste command sent; remote app confirmation unavailable."
            )
        )
    }
}
