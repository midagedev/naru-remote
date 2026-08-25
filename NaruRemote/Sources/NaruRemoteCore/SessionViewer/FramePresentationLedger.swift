import Foundation

/// Why a published content frame did not reach the texture.
///
/// Spec 028. Every early return on the presentation path names one of these.
/// The set is closed and the raw values are fixed labels, because they are
/// published in `SessionStreamStats` and in the diagnostic export, where
/// constitution §IV allows counts and fixed vocabulary only — never
/// coordinates, dimensions, byte counts or user content.
public enum FramePresentationOutcome: String, Codable, Equatable, Sendable, CaseIterable {
    /// Pixels reached the texture. The only success.
    case presented

    /// The frame carried the same signature as the one before it, so there was
    /// nothing new to upload. Terminal and intentional.
    case duplicateSuppressed

    /// A newer frame replaced this one before it was presented. Terminal and
    /// intentional — it is how the pipeline sheds load — but it is counted,
    /// because a session that supersedes everything and presents nothing is
    /// indistinguishable from a freeze without this number.
    case superseded

    /// The staged upload was partial and the texture disagreed about its size,
    /// so the frame was discarded. Terminal and **not** intentional: before
    /// spec 026 a busy frame would have taken the full-upload path and
    /// recreated the texture, which healed this state on its own.
    case abandonedOnSizeMismatch

    /// The staged upload was partial and the texture disagreed about its size,
    /// but the source framebuffer was still held, so it was re-staged as a full
    /// upload rather than discarded. Non-terminal: the frame survives.
    ///
    /// This is the structural closure for `abandonedOnSizeMismatch`. It is
    /// counted separately and not folded into silence, because the recovery
    /// working is not the same as the disagreement never happening — a session
    /// that re-stages constantly still has a defect worth finding.
    case restagedOnSizeMismatch

    /// Presentation is suspended (a viewport gesture holds the latch) and no
    /// bypass was granted. Non-terminal: the frame waits.
    case heldBySuspension

    /// A viewport gesture is active and its strategy defers live publication.
    /// Non-terminal: the frame waits for the gesture to settle.
    case heldByGesture

    /// The redraw throttle deferred this frame to give touch tracking
    /// priority. Non-terminal: the frame waits for the next redraw.
    case heldByThrottle

    /// True when this outcome ends the frame's life, one way or another.
    ///
    /// The conservation law in `FramePresentationLedger` is written over
    /// terminal outcomes only. The held states are gauges: a frame counted as
    /// held is still alive and will later be presented or superseded. Treating
    /// a hold as a loss would make the books disagree with reality on every
    /// pinch; not counting it at all is what let a stuck latch look like
    /// silence.
    public var isTerminal: Bool {
        switch self {
        case .presented, .duplicateSuppressed, .superseded, .abandonedOnSizeMismatch:
            return true
        case .heldBySuspension, .heldByGesture, .heldByThrottle, .restagedOnSizeMismatch:
            return false
        }
    }
}

/// The single owner of the question "why is the picture not updating".
///
/// Spec 028. Before this existed, a content frame could disappear at six
/// independent points between the frame store and the texture, and four of them
/// incremented nothing at all — so the answer was only ever recoverable by
/// reading the render path by hand, which is how the same freeze class was
/// investigated twice (spec 022, then TestFlight build 7).
///
/// The invariant is a conservation law over terminal outcomes:
///
///     published == presented + duplicateSuppressed + superseded
///                            + abandonedOnSizeMismatch
///                            + framesStillInFlight
///
/// `isBalanced` checks it. A ledger that does not balance means a drop site was
/// added without naming itself, which is the exact defect this type exists to
/// make impossible to ship quietly.
public struct FramePresentationLedger: Codable, Equatable, Sendable {
    public private(set) var publishedCount: Int
    private var counts: [String: Int]

    /// Times a presentation-gating latch released itself instead of being
    /// released by the code that set it. Not a drop — an alarm. A healthy
    /// session never increments this; a non-zero value means a gesture ended
    /// without its finish path running, which is a defect wherever it happened.
    public private(set) var watchdogReleaseCount: Int

    public init() {
        publishedCount = 0
        counts = [:]
        watchdogReleaseCount = 0
    }

    public mutating func recordPublished() {
        publishedCount += 1
    }

    public mutating func record(_ outcome: FramePresentationOutcome) {
        counts[outcome.rawValue, default: 0] += 1
    }

    public mutating func recordWatchdogRelease() {
        watchdogReleaseCount += 1
    }

    public func count(_ outcome: FramePresentationOutcome) -> Int {
        counts[outcome.rawValue] ?? 0
    }

    public var terminalCount: Int {
        FramePresentationOutcome.allCases
            .filter(\.isTerminal)
            .reduce(0) { $0 + count($1) }
    }

    /// How many published frames have not yet reached a terminal outcome.
    ///
    /// In a healthy session this sits at 0 or 1 — the frame currently in
    /// flight. A number that climbs without bound is the signature of a
    /// presentation stall, and it is readable directly off the HUD.
    public var framesInFlightCount: Int {
        max(0, publishedCount - terminalCount)
    }

    /// The conservation law. False means a frame vanished without naming
    /// itself, or an outcome was recorded for a frame that was never published.
    public var isBalanced: Bool {
        terminalCount <= publishedCount
    }

    /// True when frames are arriving and none of them are reaching the screen.
    ///
    /// This is the property the founder actually reports ("갱신이 안 돼") and the
    /// one no gate in this repository has ever asserted: the frame pump can run
    /// at full rate while this is true.
    public func isPresentationStalled(minimumPublished: Int) -> Bool {
        publishedCount >= minimumPublished && count(.presented) == 0
    }

    /// The single dominant reason frames are not being presented, or nil when
    /// frames are being presented normally. This is what the HUD shows and what
    /// a failing gate names, so that "the screen froze" arrives already
    /// attributed instead of starting an investigation.
    public var dominantWithholdingReason: FramePresentationOutcome? {
        let candidates: [FramePresentationOutcome] = [
            .heldBySuspension,
            .heldByGesture,
            .heldByThrottle,
            .abandonedOnSizeMismatch,
            .restagedOnSizeMismatch,
            .superseded,
        ]
        let ranked = candidates
            .map { ($0, count($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        guard let leader = ranked.first else {
            return nil
        }
        return leader.0
    }
}
