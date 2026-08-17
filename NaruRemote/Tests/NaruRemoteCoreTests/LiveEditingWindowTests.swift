import XCTest
@testable import NaruRemoteCore

final class LiveEditingWindowTests: XCTestCase {

    // MARK: - Marked text is never sent (FR-002)

    func testMarkedTextYieldsNoOperations() {
        var window = LiveTypeThroughWindow()
        // App feeds an empty committed snapshot while composition is marked.
        XCTAssertTrue(window.commit(committedText: "", hasMarkedText: true))
        XCTAssertTrue(window.hasMarkedText)
        XCTAssertFalse(window.hasPendingWork)
        XCTAssertEqual(window.pendingOperations, [])
        XCTAssertEqual(window.takePending(), [])
        XCTAssertEqual(window.deliveredText, "")
    }

    func testCommitAfterMarkEmitsOnlyCommittedUnit() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "", hasMarkedText: true)   // composing "ㅇ"/"아"...
        XCTAssertEqual(window.pendingOperations, [])
        window.commit(committedText: "안", hasMarkedText: false) // syllable committed
        XCTAssertFalse(window.hasMarkedText)
        XCTAssertEqual(window.pendingOperations, [.insert("안")])
    }

    // MARK: - Diff correctness: forward typing

    func testForwardTypingEmitsSuffixInsert() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "h", hasMarkedText: false)
        XCTAssertEqual(window.takePending(), [.insert("h")])
        window.commit(committedText: "he", hasMarkedText: false)
        XCTAssertEqual(window.takePending(), [.insert("e")])
        window.commit(committedText: "hey", hasMarkedText: false)
        XCTAssertEqual(window.takePending(), [.insert("y")])
        XCTAssertEqual(window.deliveredText, "hey")
    }

    // MARK: - Hangul jamo -> syllable commit sequence

    func testHangulSyllableCommitSequence() {
        var window = LiveTypeThroughWindow()
        // "" -> "안" -> "안녕" as syllables finalize out of IME composition.
        window.commit(committedText: "", hasMarkedText: true)
        XCTAssertEqual(window.pendingOperations, [])
        window.commit(committedText: "안", hasMarkedText: false)
        XCTAssertEqual(window.takePending(), [.insert("안")])
        window.commit(committedText: "안", hasMarkedText: true) // composing next syllable
        XCTAssertEqual(window.pendingOperations, [])
        window.commit(committedText: "안녕", hasMarkedText: false)
        XCTAssertEqual(window.takePending(), [.insert("녕")])
        XCTAssertEqual(window.deliveredText, "안녕")
    }

    func testHangulBackspaceDeletesOneSyllableGrapheme() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "안녕", hasMarkedText: false)
        _ = window.takePending()
        XCTAssertEqual(window.deliveredText, "안녕")
        let outcome = window.deleteBackward(1)
        XCTAssertEqual(outcome.applied, 1)
        XCTAssertEqual(outcome.clampedExcess, 0)
        XCTAssertEqual(window.committedText, "안")
        XCTAssertEqual(window.takePending(), [.deleteBackward(1)])
        XCTAssertEqual(window.deliveredText, "안")
    }

    // MARK: - US3 independent test: hte -> backspace -> e -> Return

    func testTypoCorrectionSequenceEmitsOrderedOpsAndSeals() {
        var window = LiveTypeThroughWindow()
        // Type h, t, e (dispatched as one coalesced insert since no take between).
        window.commit(committedText: "h", hasMarkedText: false)
        window.commit(committedText: "ht", hasMarkedText: false)
        window.commit(committedText: "hte", hasMarkedText: false)
        XCTAssertEqual(window.takePending(), [.insert("hte")])

        // Backspace once (the reused ⌫ button), dispatched.
        let del = window.deleteBackward(1)
        XCTAssertEqual(del.applied, 1)
        XCTAssertEqual(window.takePending(), [.deleteBackward(1)])
        XCTAssertEqual(window.deliveredText, "ht")

        // Retype e, dispatched.
        window.commit(committedText: "hte", hasMarkedText: false)
        XCTAssertEqual(window.takePending(), [.insert("e")])

        // Return flushes (nothing pending) + newline + seal.
        window.newline()
        XCTAssertTrue(window.isSealed)
        XCTAssertEqual(window.sealReason, .lineCommitted)
        XCTAssertEqual(window.takePending(), [.newline])
    }

    // MARK: - Coalescing (adjacent inserts merge)

    func testConsecutiveCommitsCoalesceIntoSingleInsert() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "a", hasMarkedText: false)
        window.commit(committedText: "ab", hasMarkedText: false)
        window.commit(committedText: "abc", hasMarkedText: false)
        // Nothing dispatched between commits: one coalesced insert.
        XCTAssertEqual(window.pendingOperations, [.insert("abc")])
        XCTAssertEqual(window.takePending(), [.insert("abc")])
    }

    // MARK: - Delete cancels undispatched pending inserts locally (cancel-local)

    func testDeleteCancelsPendingInsertLocallyWithoutRemoteDelete() {
        var window = LiveTypeThroughWindow()
        // Pending insert "ab" (never dispatched) + delete 1 => insert "a".
        window.commit(committedText: "ab", hasMarkedText: false)
        _ = window.deleteBackward(1)
        XCTAssertEqual(window.committedText, "a")
        XCTAssertEqual(window.pendingOperations, [.insert("a")])
        XCTAssertEqual(window.takePending(), [.insert("a")])
        XCTAssertEqual(window.deliveredText, "a")
    }

    func testDeleteBeyondPendingEmitsRemoteDeleteForDispatchedRemainder() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "ab", hasMarkedText: false)
        XCTAssertEqual(window.takePending(), [.insert("ab")]) // dispatched
        window.commit(committedText: "abcd", hasMarkedText: false) // pending "cd"
        // Delete 3: cancels pending "cd" locally, then 1 real delete of "b".
        _ = window.deleteBackward(3)
        XCTAssertEqual(window.committedText, "a")
        XCTAssertEqual(window.pendingOperations, [.deleteBackward(1)])
        XCTAssertEqual(window.takePending(), [.deleteBackward(1)])
        XCTAssertEqual(window.deliveredText, "a")
    }

    // MARK: - FIFO ordering: delete precedes insert in one batch

    func testDeleteThenRetypeInSingleBatchOrdersDeleteBeforeInsert() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "the", hasMarkedText: false)
        XCTAssertEqual(window.takePending(), [.insert("the")]) // dispatched
        // Backspace to "th" then type "x" -> "thx", all before next dispatch.
        _ = window.deleteBackward(1)          // committed "th"
        window.commit(committedText: "thx", hasMarkedText: false)
        XCTAssertEqual(window.pendingOperations, [.deleteBackward(1), .insert("x")])
        XCTAssertEqual(window.takePending(), [.deleteBackward(1), .insert("x")])
        XCTAssertEqual(window.deliveredText, "thx")
    }

    // MARK: - Grapheme integrity: emoji + combining marks (FR-003)

    func testEmojiDeliveredAsWholeGraphemeAndDeletedWhole() {
        let family = "👨‍👩‍👧‍👦" // single ZWJ grapheme cluster
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "a\(family)", hasMarkedText: false)
        XCTAssertEqual(window.takePending(), [.insert("a\(family)")])
        XCTAssertEqual(window.committedGraphemeCount, 2)
        // One backspace removes the whole cluster, not a scalar.
        let outcome = window.deleteBackward(1)
        XCTAssertEqual(outcome.applied, 1)
        XCTAssertEqual(window.committedText, "a")
        XCTAssertEqual(window.takePending(), [.deleteBackward(1)])
    }

    func testCombiningMarkClusterIsNotSplit() {
        let decomposed = "e\u{0301}" // "é" as base + combining acute (one grapheme)
        var window = LiveTypeThroughWindow()
        window.commit(committedText: decomposed, hasMarkedText: false)
        XCTAssertEqual(window.committedGraphemeCount, 1)
        XCTAssertEqual(window.takePending(), [.insert(decomposed)])
        let outcome = window.deleteBackward(1)
        XCTAssertEqual(outcome.applied, 1)
        XCTAssertEqual(window.committedText, "")
    }

    func testComposedAndDecomposedFormsShareGraphemePrefix() {
        // delivered "é" (NFC), target "é" + "!" via NFD base -> common prefix 1.
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "\u{00E9}", hasMarkedText: false) // NFC é
        XCTAssertEqual(window.takePending(), [.insert("\u{00E9}")])
        window.commit(committedText: "e\u{0301}!", hasMarkedText: false) // NFD é + !
        // Canonical equivalence => only "!" is a new insert.
        XCTAssertEqual(window.pendingOperations, [.insert("!")])
    }

    // MARK: - Sealing: no delete crosses the seal (FR-011)

    func testSealBlocksFurtherEditsAndClampsDelete() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "abc", hasMarkedText: false)
        _ = window.takePending()
        window.seal(reason: .pointerInteraction)
        XCTAssertTrue(window.isSealed)
        XCTAssertEqual(window.sealReason, .pointerInteraction)

        // Commit is ignored on a sealed window.
        XCTAssertFalse(window.commit(committedText: "abcd", hasMarkedText: false))
        XCTAssertEqual(window.committedText, "abc")

        // Delete on a sealed window applies nothing; full count is clamped excess.
        let outcome = window.deleteBackward(2)
        XCTAssertEqual(outcome.applied, 0)
        XCTAssertEqual(outcome.clampedExcess, 2)
        XCTAssertEqual(window.lastClampedDeleteExcess, 2)
        XCTAssertEqual(window.committedText, "abc")
    }

    func testFreshWindowAfterSealClampsBackspaceAtItsOwnBoundary() {
        // Simulate: a window sealed with delivered content; a fresh window opens
        // and the user immediately backspaces more than it owns.
        var fresh = LiveTypeThroughWindow()
        // Fresh window delivered nothing; backspacing 3 cannot reach prior window.
        let outcome = fresh.deleteBackward(3)
        XCTAssertEqual(outcome.applied, 0)
        XCTAssertEqual(outcome.clampedExcess, 3)
        XCTAssertEqual(fresh.pendingOperations, [])
        // After typing 1 grapheme, only that one is deletable.
        fresh.commit(committedText: "x", hasMarkedText: false)
        _ = fresh.takePending()
        let second = fresh.deleteBackward(2)
        XCTAssertEqual(second.applied, 1)
        XCTAssertEqual(second.clampedExcess, 1)
    }

    func testNewlineSealsWithLineCommittedReason() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "ls", hasMarkedText: false)
        window.newline()
        XCTAssertTrue(window.isSealed)
        XCTAssertEqual(window.sealReason, .lineCommitted)
        // Pending inserts flush before the newline in one batch.
        XCTAssertEqual(window.takePending(), [.insert("ls"), .newline])
        // Further newline / edits are no-ops after seal.
        window.newline()
        XCTAssertEqual(window.takePending(), [])
    }

    func testSealDropsMarkedTextFlag() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "a", hasMarkedText: true)
        window.seal(reason: .modeSwitch)
        XCTAssertFalse(window.hasMarkedText)
    }

    // MARK: - Static diff helper

    func testOperationsHelperOrdersDeleteInsertNewline() {
        let ops = LiveTypeThroughWindow.operations(from: "abc", to: "abX", newline: true)
        XCTAssertEqual(ops, [.deleteBackward(1), .insert("X"), .newline])
    }

    func testCommonGraphemePrefixCountCountsClusters() {
        XCTAssertEqual(LiveTypeThroughWindow.commonGraphemePrefixCount("안녕", "안"), 1)
        XCTAssertEqual(LiveTypeThroughWindow.commonGraphemePrefixCount("abc", "abc"), 3)
        XCTAssertEqual(LiveTypeThroughWindow.commonGraphemePrefixCount("abc", "xyz"), 0)
    }

    // MARK: - Delivery ladder policy table (FR-004/FR-005)

    func testLadderHelperAlwaysWinsForBothPayloadKinds() {
        let caps = LiveDeliveryLadder.Capabilities(
            helperReachable: true,
            utf8ClipboardConfirmed: false
        )
        XCTAssertEqual(LiveDeliveryLadder.insertTier(for: .ascii, capabilities: caps), .helperNativeInsert)
        XCTAssertEqual(LiveDeliveryLadder.insertTier(for: .unicode, capabilities: caps), .helperNativeInsert)
    }

    func testLadderNoHelperUsesClipboardWhenUtf8Confirmed() {
        let caps = LiveDeliveryLadder.Capabilities(
            helperReachable: false,
            utf8ClipboardConfirmed: true
        )
        XCTAssertEqual(LiveDeliveryLadder.insertTier(for: .ascii, capabilities: caps), .clipboardChunk)
        XCTAssertEqual(LiveDeliveryLadder.insertTier(for: .unicode, capabilities: caps), .clipboardChunk)
    }

    func testLadderAsciiFallsToKeyEventWhenNoHelperNoClipboard() {
        let caps = LiveDeliveryLadder.Capabilities(
            helperReachable: false,
            utf8ClipboardConfirmed: false
        )
        XCTAssertEqual(LiveDeliveryLadder.insertTier(for: .ascii, capabilities: caps), .keyEvent)
    }

    func testLadderUnicodeFallsToKeyEventKeysymStreamWhenNoHelperNoClipboard() {
        let caps = LiveDeliveryLadder.Capabilities(
            helperReachable: false,
            utf8ClipboardConfirmed: false
        )
        // Spec 011 / constitution §I (2026-08-17): Unicode rides the X11
        // Unicode-keysym stream on the keyEvent tier — live-measured
        // 2026-07-13 to render on macOS Screen Sharing.
        XCTAssertEqual(LiveDeliveryLadder.insertTier(for: .unicode, capabilities: caps), .keyEvent)
    }

    func testControlOperationTierIsAlwaysKeyEvent() {
        XCTAssertEqual(LiveDeliveryLadder.controlOperationTier, .keyEvent)
    }

    func testPayloadClassification() {
        XCTAssertEqual(LiveInsertPayloadKind.classify("hello 123!"), .ascii)
        XCTAssertEqual(LiveInsertPayloadKind.classify("안녕"), .unicode)
        XCTAssertEqual(LiveInsertPayloadKind.classify("café"), .unicode)   // é > 0x7F
        XCTAssertEqual(LiveInsertPayloadKind.classify("👍"), .unicode)
    }

    func testTierDisclosureProperties() {
        XCTAssertTrue(LiveTypeThroughAdapterTier.helperNativeInsert.deliversObservedConfirmation)
        XCTAssertFalse(LiveTypeThroughAdapterTier.clipboardChunk.deliversObservedConfirmation)
        XCTAssertTrue(LiveTypeThroughAdapterTier.clipboardChunk.carriesSettleLatency)
        XCTAssertTrue(LiveTypeThroughAdapterTier.clipboardChunk.overwritesRemoteClipboard)
        XCTAssertTrue(LiveTypeThroughAdapterTier.keyEvent.isMultilingualCapable)
        XCTAssertEqual(LiveTypeThroughAdapterTier.helperNativeInsert.successStatus, .deliveredObserved)
        XCTAssertEqual(LiveTypeThroughAdapterTier.clipboardChunk.successStatus, .unconfirmedClipboard)
        XCTAssertEqual(LiveTypeThroughAdapterTier.keyEvent.successStatus, .asciiLastResort)
    }

    // MARK: - Mode reset to Compose default (FR-016)

    func testModeResetsToComposeDefault() {
        var mode = LiveTypeThroughMode(
            isActive: true,
            selectedTier: .helperNativeInsert,
            lastStatus: .deliveredObserved,
            lastSealReason: .disconnect,
            hasShownEntryDisclosureThisSession: true
        )
        mode.resetForNewSession()
        XCTAssertEqual(mode, .composeDefault)
        XCTAssertFalse(mode.isActive)
        XCTAssertNil(mode.selectedTier)
        XCTAssertEqual(mode.lastStatus, .idle)
        XCTAssertNil(mode.lastSealReason)
        XCTAssertFalse(mode.hasShownEntryDisclosureThisSession)
    }

    func testModeCodableRoundTripAndForwardCompatibility() throws {
        let mode = LiveTypeThroughMode(
            isActive: true,
            selectedTier: .clipboardChunk,
            lastStatus: .unconfirmedClipboard,
            lastSealReason: .pointerInteraction,
            hasShownEntryDisclosureThisSession: true
        )
        let data = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(LiveTypeThroughMode.self, from: data)
        XCTAssertEqual(decoded, mode)

        // Empty JSON decodes to the Compose default (decodeIfPresent pattern).
        let empty = try JSONDecoder().decode(LiveTypeThroughMode.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, .composeDefault)
    }

    // MARK: - Failed-delivery rollback (FR-015)

    func testRollBackDeliveryRestoresFailedInsertToRetainedTail() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "안녕", hasMarkedText: false)
        let baseline = window.deliveredText
        _ = window.takePending()
        XCTAssertEqual(window.deliveredText, "안녕", "optimistic fold")
        XCTAssertEqual(window.retainedTail, "")

        window.rollBackDelivery(toPreDispatchBaseline: baseline)
        XCTAssertEqual(window.deliveredText, "")
        XCTAssertEqual(window.retainedTail, "안녕", "failed chunk re-enters the retained tail")
    }

    func testRollBackDeliveryKeepsKeyLaneDeletesAppliedOnMixedBatch() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "abcd", hasMarkedText: false)
        _ = window.takePending()

        // Middle edit → one batch of [deleteBackward(2), insert("X")]. The
        // deletes ride the key lane and land; the insert fails.
        window.commit(committedText: "abX", hasMarkedText: false)
        let baseline = window.deliveredText
        let ops = window.takePending()
        XCTAssertEqual(ops, [.deleteBackward(2), .insert("X")])

        window.rollBackDelivery(toPreDispatchBaseline: baseline)
        // Remote now holds the common prefix "ab"; "X" is retained locally.
        XCTAssertEqual(window.deliveredText, "ab")
        XCTAssertEqual(window.retainedTail, "X")
    }

    func testRollBackDeliveryIsAllowedOnSealedWindowForRetentionMath() {
        var window = LiveTypeThroughWindow()
        window.commit(committedText: "h", hasMarkedText: false)
        let baseline = window.deliveredText
        _ = window.takePending()
        window.seal(reason: .pointerInteraction)

        window.rollBackDelivery(toPreDispatchBaseline: baseline)
        XCTAssertEqual(window.retainedTail, "h", "sealed windows still correct their bookkeeping")
    }
}
