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

    func testAppliesModelEchoMatchingFocusedLocalDraft() {
        XCTAssertTrue(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "입력느낌",
                lastAppliedInitialText: "",
                currentText: "입력느낌",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: false
            )
        )
    }

    func testDefersModelEchoMatchingFocusedMarkedText() {
        XCTAssertFalse(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "입력느낌",
                lastAppliedInitialText: "",
                currentText: "입력느낌",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: true
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

    func testDefersLocalComposeTextPropagationWhileMarkedTextIsActive() {
        XCTAssertFalse(
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

    func testDefersFocusedCommittedComposeTextPropagationUntilExplicitBoundary() {
        XCTAssertFalse(
            RemoteInputDockView.shouldPropagateLocalComposeTextToModel(
                newValue: "입력느낌",
                lastPropagatedText: "입력느",
                isDirectModeActive: false,
                hasMarkedText: false,
                isComposeFieldFocused: true
            ),
            "A just-committed Korean syllable should remain owned by UITextView while the editor is focused."
        )
    }

    func testForcePropagatesFocusedComposeTextAtExplicitBoundary() {
        XCTAssertTrue(
            RemoteInputDockView.shouldPropagateLocalComposeTextToModel(
                newValue: "입력느낌",
                lastPropagatedText: "입력느",
                isDirectModeActive: false,
                hasMarkedText: false,
                isComposeFieldFocused: true,
                force: true
            ),
            "Focus loss, Send, and Direct-mode entry are explicit boundaries that persist the local draft."
        )
    }

    func testForceStillSkipsDuplicateComposeTextPropagation() {
        XCTAssertFalse(
            RemoteInputDockView.shouldPropagateLocalComposeTextToModel(
                newValue: "입력느낌",
                lastPropagatedText: "입력느낌",
                isDirectModeActive: false,
                hasMarkedText: false,
                isComposeFieldFocused: true,
                force: true
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

    func testSkipsMarkedComposeTextPropagationEvenWhenItDiffersFromModel() {
        XCTAssertFalse(
            RemoteInputDockView.shouldPropagateLocalComposeTextToModel(
                newValue: "입력느낌",
                lastPropagatedText: "입력느",
                isDirectModeActive: false,
                hasMarkedText: true
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

    func testDefersUIKitComposeTextChangeWhileMarkedTextUpdatesTextView() {
        XCTAssertFalse(
            RemoteInputDockView.shouldAdoptUIKitComposeTextChange(
                resolvedText: "입력느낌",
                currentBindingText: "입력느",
                hasMarkedText: true
            )
        )
    }

    func testAdoptsUIKitComposeTextChangeAfterMarkedTextCommits() {
        XCTAssertTrue(
            RemoteInputDockView.shouldAdoptUIKitComposeTextChange(
                resolvedText: "입력느낌",
                currentBindingText: "입력느",
                hasMarkedText: false
            )
        )
    }

    func testDoesNotMirrorFocusedUIKitComposeTextIntoSwiftUIBinding() {
        XCTAssertFalse(
            RemoteInputDockView.shouldAdoptUIKitComposeTextChange(
                resolvedText: "입력느낌",
                currentBindingText: "입력느",
                hasMarkedText: false,
                isFirstResponder: true
            ),
            "Focused Compose text is owned by UITextView until send, focus loss, or mode switch."
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
        XCTAssertLessThan(
            RemoteInputDockView.composeSendFastSnapshotCount,
            RemoteInputDockView.composeSendStabilizationSnapshotCount
        )
        XCTAssertEqual(RemoteInputDockView.composeSendFastDelayNanoseconds, 0)
        XCTAssertGreaterThanOrEqual(RemoteInputDockView.composeSendStabilizationSnapshotCount, 30)
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

    // QW1: event-driven stabilization. Already-committed text (no marked
    // range, steady snapshots) must exit after just two reads instead of
    // draining the full ~480ms window — near-zero added latency for the
    // common Compose Send.
    func testComposeStabilizationExitsEarlyOnAlreadyCommittedText() {
        let outcome = RemoteInputDockView.simulateComposeStabilization(
            fallback: "입력느낌",
            snapshotCount: RemoteInputDockView.composeSendStabilizationSnapshotCount,
            snapshots: Array(
                repeating: (text: "입력느낌", hasMarkedText: false),
                count: RemoteInputDockView.composeSendStabilizationSnapshotCount
            )
        )

        XCTAssertEqual(outcome.text, "입력느낌")
        XCTAssertEqual(
            outcome.snapshotsTaken,
            2,
            "Committed text with no marked range settles after two identical reads."
        )
    }

    func testComposeStabilizationExitEarlyDecisionRequiresNoMarkedTextAndTwoIdenticalSnapshots() {
        XCTAssertFalse(
            RemoteInputDockView.composeStabilizationShouldExitEarly(
                hasMarkedText: true,
                previousSnapshot: "입력느낌",
                currentSnapshot: "입력느낌"
            ),
            "Marked text still in flight must never exit early."
        )
        XCTAssertFalse(
            RemoteInputDockView.composeStabilizationShouldExitEarly(
                hasMarkedText: false,
                previousSnapshot: nil,
                currentSnapshot: "입력느낌"
            ),
            "A single snapshot is not enough to confirm the text stopped changing."
        )
        XCTAssertFalse(
            RemoteInputDockView.composeStabilizationShouldExitEarly(
                hasMarkedText: false,
                previousSnapshot: "입력느",
                currentSnapshot: "입력느낌"
            ),
            "Two differing snapshots mean the text is still moving."
        )
        XCTAssertTrue(
            RemoteInputDockView.composeStabilizationShouldExitEarly(
                hasMarkedText: false,
                previousSnapshot: "입력느낌",
                currentSnapshot: "입력느낌"
            )
        )
    }

    // QW1 guardrail (preserves the T015y/T015ad delayed-IME-commit
    // guarantee): while the marked range is live we keep polling, and a
    // commit that lands late within the window is still captured, not lost.
    func testComposeStabilizationKeepsPollingWhileMarkedTextRemainsThenCapturesDelayedCommit() {
        var snapshots: [(text: String, hasMarkedText: Bool)] = Array(
            repeating: (text: "입력느", hasMarkedText: true),
            count: 5
        )
        snapshots.append((text: "입력느낌", hasMarkedText: false))
        snapshots.append((text: "입력느낌", hasMarkedText: false))

        let outcome = RemoteInputDockView.simulateComposeStabilization(
            fallback: "입력느",
            snapshotCount: RemoteInputDockView.composeSendStabilizationSnapshotCount,
            snapshots: snapshots
        )

        XCTAssertEqual(outcome.text, "입력느낌")
        XCTAssertEqual(
            outcome.snapshotsTaken,
            7,
            "Five marked reads never exit; the commit lands on read 6 and settles on read 7."
        )
    }

    func testComposeStabilizationNeverExceedsSnapshotCountUpperBound() {
        // Text that changes every read (never two identical in a row) must
        // still terminate at the upper bound rather than spin forever.
        let churningSnapshots = (0..<40).map { index in
            (text: "입력\(index)", hasMarkedText: false)
        }
        let outcome = RemoteInputDockView.simulateComposeStabilization(
            fallback: "입력",
            snapshotCount: RemoteInputDockView.composeSendStabilizationSnapshotCount,
            snapshots: churningSnapshots
        )

        XCTAssertEqual(
            outcome.snapshotsTaken,
            RemoteInputDockView.composeSendStabilizationSnapshotCount
        )
    }

    func testComposeSendPreparationPlanUsesFastPathWhenNoMarkedTextWasActive() {
        let plan = RemoteInputDockView.composeSendPreparationPlan(hadMarkedTextBeforeSend: false)

        XCTAssertEqual(plan.mode, .fastSnapshot)
        XCTAssertEqual(plan.snapshotCount, RemoteInputDockView.composeSendFastSnapshotCount)
        XCTAssertEqual(plan.snapshotDelayNanoseconds, RemoteInputDockView.composeSendFastDelayNanoseconds)
    }

    func testComposeSendPreparationPlanUsesStabilizationAfterRecentMarkedCommit() {
        let plan = RemoteInputDockView.composeSendPreparationPlan(
            hadMarkedTextBeforeSend: false,
            needsMarkedCommitStabilization: true
        )

        XCTAssertEqual(plan.mode, .markedTextStabilization)
        XCTAssertEqual(plan.snapshotCount, RemoteInputDockView.composeSendStabilizationSnapshotCount)
        XCTAssertEqual(
            plan.snapshotDelayNanoseconds,
            RemoteInputDockView.composeSendStabilizationDelayNanoseconds
        )
    }

    func testComposeSendPreparationPlanUsesStabilizationForMarkedText() {
        let plan = RemoteInputDockView.composeSendPreparationPlan(hadMarkedTextBeforeSend: true)

        XCTAssertEqual(plan.mode, .markedTextStabilization)
        XCTAssertEqual(plan.snapshotCount, RemoteInputDockView.composeSendStabilizationSnapshotCount)
        XCTAssertEqual(
            plan.snapshotDelayNanoseconds,
            RemoteInputDockView.composeSendStabilizationDelayNanoseconds
        )
    }

    func testFocusedComposeSendButtonStaysEnabledWithoutSwiftUITextMirror() {
        XCTAssertFalse(
            RemoteInputDockView.composeSendDisabled(
                isPreparingComposeSend: false,
                isComposeFieldFocused: true,
                currentText: ""
            ),
            "Focused Compose reads final text directly from UITextView on send, so the button cannot depend on mirrored SwiftUI text."
        )
    }

    func testUnfocusedEmptyComposeStillDisablesSendButton() {
        XCTAssertTrue(
            RemoteInputDockView.composeSendDisabled(
                isPreparingComposeSend: false,
                isComposeFieldFocused: false,
                currentText: ""
            )
        )
    }

    func testComposeSendButtonDisablesWhilePreparingSend() {
        XCTAssertTrue(
            RemoteInputDockView.composeSendDisabled(
                isPreparingComposeSend: true,
                isComposeFieldFocused: true,
                currentText: "입력"
            )
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

    func testCompactStatusFallsBackToHelperStateWhenNoSendStatusExists() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCompactStatusText(
                hasStatus: false,
                statusText: "Ready to compose locally",
                helperStatusText: "Korean/CJK/emoji needs Mac helper setup"
            ),
            "Korean/CJK/emoji needs Mac helper setup"
        )
    }

    func testCompactStatusPrefersSendStateOverHelperState() {
        XCTAssertEqual(
            RemoteInputDockView.resolvedCompactStatusText(
                hasStatus: true,
                statusText: "Send failed; draft kept locally",
                helperStatusText: "Helper ready for multilingual Compose"
            ),
            "Send failed; draft kept locally"
        )
    }
}
