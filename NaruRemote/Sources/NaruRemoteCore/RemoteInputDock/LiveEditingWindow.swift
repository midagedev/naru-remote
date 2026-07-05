import Foundation

/// A single reconciliation operation the Live editing window emits toward the
/// remote insertion point (spec 009 FR-003/FR-009/FR-010).
///
/// - `insert` carries a committed forward delta (never marked/composing text —
///   FR-002; never a partial grapheme — FR-003).
/// - `deleteBackward` carries a grapheme count, realized as that many remote
///   `BackSpace` key events on the VNC control-key lane (founder D1) — never a
///   helper delete op in v1.
/// - `newline` is a `Return`/`Enter` line boundary, realized as a remote
///   `Return` key event on the VNC control-key lane (FR-010).
public enum LiveTypeThroughOperation: Sendable, Equatable {
    case insert(String)
    case deleteBackward(Int)
    case newline
}

/// The in-memory mirror of what Naru believes it has delivered to the remote
/// insertion point since this window opened (spec 009 Key Entities:
/// `LiveEditingWindow`). Pure value type, no session/UIKit dependency.
///
/// Feed it successive *committed-text* snapshots (the text field content with any
/// marked/composing range excluded) plus whether marked text is currently
/// present. It computes the minimal forward reconciliation via a grapheme-cluster
/// common-prefix diff and enqueues it as pending work. The owner dispatches with
/// single-in-flight semantics: while a chunk is in flight, further commits
/// coalesce into the pending buffer; `takePending()` drains the coalesced buffer
/// as one ordered batch (FR-007/FR-008).
///
/// ## Coalescing and cancel-local
/// Pending work is always recomputed against `deliveredText` (what has actually
/// been handed out for dispatch). Consecutive commits therefore collapse into a
/// single insert, and a delete that only shortens *undispatched* pending inserts
/// cancels them locally instead of emitting a remote delete — e.g. a pending
/// `insert("ab")` followed by `deleteBackward(1)` becomes `insert("a")` with no
/// delete crossing to the remote.
///
/// ## Sealing (FR-011)
/// `seal(reason:)` freezes the window: no further edits are accepted and — per
/// the data-loss safety model — no delete may cross the seal. Deletes issued
/// against a sealed window (or a fresh window's un-owned prefix) are clamped to
/// the window's own deletable graphemes and the excess is reported, never
/// applied to remote content this window did not deliver.
public struct LiveTypeThroughWindow: Sendable, Equatable {
    /// Graphemes handed out for dispatch (assumed at / in flight to the remote).
    public private(set) var deliveredText: String
    /// The local reconciliation target: `deliveredText` plus not-yet-dispatched
    /// committed edits.
    public private(set) var committedText: String
    /// Whether marked/composing text is currently present locally. Recorded for
    /// status only; marked text never enters `committedText` (FR-002).
    public private(set) var hasMarkedText: Bool
    /// Whether the window has sealed (FR-011). Terminal: no further edits.
    public private(set) var isSealed: Bool
    /// The fixed reason this window sealed, if sealed.
    public private(set) var sealReason: LiveWindowSealReason?
    /// The number of backspace graphemes clamped away by the most recent delete
    /// because they would have crossed the seal / this window's boundary.
    public private(set) var lastClampedDeleteExcess: Int

    private var hasPendingNewline: Bool

    public init() {
        deliveredText = ""
        committedText = ""
        hasMarkedText = false
        isSealed = false
        sealReason = nil
        lastClampedDeleteExcess = 0
        hasPendingNewline = false
    }

    // MARK: - Projections

    /// Grapheme count already dispatched for this window.
    public var deliveredGraphemeCount: Int { deliveredText.count }

    /// Grapheme count of the current local target.
    public var committedGraphemeCount: Int { committedText.count }

    /// Whether there is undispatched reconciliation work (inserts, deletes, or a
    /// pending line boundary).
    public var hasPendingWork: Bool {
        deliveredText != committedText || hasPendingNewline
    }

    /// The ordered operations that `takePending()` would return right now,
    /// without mutating the window. Delete precedes insert precedes newline so
    /// the remote never observes reordered content (FR-007).
    public var pendingOperations: [LiveTypeThroughOperation] {
        Self.operations(from: deliveredText, to: committedText, newline: hasPendingNewline)
    }

    // MARK: - Editing

    /// Feed a committed-text snapshot (marked/composing range already excluded)
    /// plus whether marked text is present. Returns `false` and is a no-op if the
    /// window is sealed. Recomputes pending work against `deliveredText`
    /// (coalescing / cancel-local, see type docs).
    @discardableResult
    public mutating func commit(committedText text: String, hasMarkedText marked: Bool) -> Bool {
        hasMarkedText = marked
        guard !isSealed else { return false }
        committedText = text
        return true
    }

    /// Outcome of a `deleteBackward` request.
    public struct DeleteOutcome: Sendable, Equatable {
        /// Graphemes actually removed from this window's target.
        public let applied: Int
        /// Graphemes clamped away because they would have crossed the seal /
        /// this window's boundary (reported, never applied to the remote).
        public let clampedExcess: Int

        public init(applied: Int, clampedExcess: Int) {
            self.applied = applied
            self.clampedExcess = clampedExcess
        }
    }

    /// Delete `count` graphemes backward from the current target (the reused ⌫
    /// action button, D1). Clamped to this window's own deletable graphemes: a
    /// count exceeding what this window delivered/holds cannot reach into a
    /// prior sealed window and is reported as `clampedExcess` (FR-011). A sealed
    /// window applies nothing and reports the whole count as excess.
    @discardableResult
    public mutating func deleteBackward(_ count: Int) -> DeleteOutcome {
        let requested = max(0, count)
        guard requested > 0, !isSealed else {
            let outcome = DeleteOutcome(applied: 0, clampedExcess: requested)
            lastClampedDeleteExcess = outcome.clampedExcess
            return outcome
        }
        let deletable = committedText.count
        let applied = min(requested, deletable)
        if applied > 0 {
            committedText = String(committedText.dropLast(applied))
        }
        let outcome = DeleteOutcome(applied: applied, clampedExcess: requested - applied)
        lastClampedDeleteExcess = outcome.clampedExcess
        return outcome
    }

    /// Commit a line boundary (Return/Enter): flush pending inserts first, then
    /// the boundary, then seal the window (FR-010). No-op if already sealed. The
    /// pending inserts and the `.newline` remain drainable via `takePending()`;
    /// the owner opens a fresh window afterward.
    public mutating func newline() {
        guard !isSealed else { return }
        hasPendingNewline = true
        seal(reason: .lineCommitted)
    }

    /// Seal the window (FR-011). Terminal: subsequent `commit`/`deleteBackward`
    /// are ignored/clamped. Delivered text stays; marked text is dropped. Already
    /// queued pending work remains drainable (used by `newline()` to flush the
    /// line boundary); the owner suppresses dispatch for non-line seals.
    public mutating func seal(reason: LiveWindowSealReason) {
        guard !isSealed else { return }
        isSealed = true
        sealReason = reason
        hasMarkedText = false
    }

    // MARK: - Dispatch

    /// Drain the coalesced pending buffer as one ordered batch and fold it into
    /// `deliveredText` (optimistic single-in-flight dispatch). On delivery
    /// failure the owner must call `rollBackDelivery(toPreDispatchBaseline:)`
    /// before retaining (FR-006/FR-015) rather than trusting this fold.
    /// Returns the ordered operations (delete, then insert, then newline).
    @discardableResult
    public mutating func takePending() -> [LiveTypeThroughOperation] {
        let ops = Self.operations(from: deliveredText, to: committedText, newline: hasPendingNewline)
        deliveredText = committedText
        hasPendingNewline = false
        return ops
    }

    /// The not-yet-delivered tail of the current target — what a seal retains
    /// locally so nothing committed is lost (FR-015).
    public var retainedTail: String {
        committedText.hasPrefix(deliveredText)
            ? String(committedText.dropFirst(deliveredText.count))
            : committedText
    }

    /// Correct the delivered mirror after a FAILED async delivery. The batch's
    /// deletes rode the key lane and are assumed applied; the insert did not
    /// land. The remote therefore holds the common grapheme prefix of the
    /// pre-dispatch baseline and the folded target — reset `deliveredText` to
    /// that prefix so retention math (`retainedTail` / a subsequent seal) gives
    /// the failed chunk back instead of trusting the optimistic fold (FR-015).
    /// Allowed on sealed windows: it only corrects bookkeeping.
    public mutating func rollBackDelivery(toPreDispatchBaseline baseline: String) {
        let common = Self.commonGraphemePrefixCount(baseline, deliveredText)
        deliveredText = String(deliveredText.prefix(common))
    }

    // MARK: - Diff

    /// Grapheme-cluster common-prefix diff (FR-003 — never splits a cluster).
    /// The remote insertion cursor is end-anchored, so reconciliation is a
    /// tail delete + tail insert; middle edits are represented as delete-to-
    /// divergence then retype.
    static func operations(
        from delivered: String,
        to committed: String,
        newline: Bool
    ) -> [LiveTypeThroughOperation] {
        var ops: [LiveTypeThroughOperation] = []
        let common = commonGraphemePrefixCount(delivered, committed)
        let deleteCount = delivered.count - common
        if deleteCount > 0 {
            ops.append(.deleteBackward(deleteCount))
        }
        let insertText = String(committed.dropFirst(common))
        if !insertText.isEmpty {
            ops.append(.insert(insertText))
        }
        if newline {
            ops.append(.newline)
        }
        return ops
    }

    /// Number of leading grapheme clusters two strings share. `Character`
    /// comparison is canonical-equivalence aware, so composed/decomposed forms
    /// of the same syllable match.
    static func commonGraphemePrefixCount(_ a: String, _ b: String) -> Int {
        var count = 0
        var ai = a.startIndex
        var bi = b.startIndex
        while ai < a.endIndex, bi < b.endIndex, a[ai] == b[bi] {
            ai = a.index(after: ai)
            bi = b.index(after: bi)
            count += 1
        }
        return count
    }
}
