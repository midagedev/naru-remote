import CoreGraphics

/// Carries the leftover of a scroll gesture between callbacks, so a threshold
/// stated in points is a threshold the user can actually cross (spec 037).
///
/// The remote scroll lane is discrete: RFB has no "scroll by 3.4 points", only
/// wheel notches (RFC 6143 §7.5.5 bits 3..6), so the client has to decide when
/// accumulated motion is worth one notch. `NaruRemoteAppModel.scrollTickThreshold`
/// is that decision — 24 points per notch — and the arithmetic that applied it
/// was `floor(|delta| / 24)` on **one callback's delta**.
///
/// That is the defect the founder reported as "scrolling doesn't work". A
/// `UIPanGestureRecognizer` zeroes its translation on every callback, so at
/// 60–120 Hz each delta is a few points; `floor(3 / 24)` is zero, and it is
/// zero again on the next callback, and the motion is thrown away each time. A
/// notch only ever fired when one callback happened to carry the whole 24
/// points — a hard flick — which is exactly the "sometimes it scrolls" shape.
/// The doc comment on `sendScrollAt` even said the caller was expected to
/// accumulate across callbacks. Nothing did.
///
/// So the remainder lives here, next to the threshold that needs it, and every
/// scroll source — finger pan, hardware trackpad, anything added later — gets
/// the same behaviour instead of each one being expected to remember.
public struct ScrollTickAccumulator: Equatable, Sendable {
    /// Motion seen but not yet worth a notch, per axis.
    public private(set) var pendingX: CGFloat = 0
    public private(set) var pendingY: CGFloat = 0

    /// How large a sign-reversing delta must be, in points, before it counts
    /// as a real direction change rather than jitter (spec 043 FR-003).
    ///
    /// Two fingers dragged slowly wobble by a point or two per callback at
    /// 60–120 Hz — on the axis the user is scrolling along, not just the idle
    /// one — and the pre-043 rule dropped the pending remainder on *any*
    /// reversal, so a gentle scroll's credit was reset every second callback
    /// and never reached the 24-point notch ("스크롤의 양이 엄청 적을때가 있어",
    /// 2026-09-13). A reversal of at least this many points against the
    /// pending remainder is a deliberate change of direction (a finger
    /// changing course delivers several points within a callback or two) and
    /// still drops the abandoned credit; below it the remainder is merely
    /// eroded by the wobble, which costs at most this many points of timing
    /// on the eventual opposite notch. An absolute bound, not a fraction of
    /// the threshold: the wobble is a property of fingers on glass, not of
    /// how big a notch is.
    public static let reversalJitterTolerance: CGFloat = 2

    public init() {}

    /// Adds one callback's delta and returns the part that is worth whole
    /// notches, keeping the remainder for the next callback.
    ///
    /// A direction reversal on an axis drops that axis's remainder rather than
    /// spending it backwards: motion the user has already abandoned must not
    /// arrive as a notch in the opposite direction. Reversals within
    /// `reversalJitterTolerance` points are jitter and do not drop anything
    /// (spec 043 FR-003).
    ///
    /// Returns `(0, 0)` while the motion is still below one notch, which is
    /// the common case and deliberately cheap.
    public mutating func accumulate(
        deltaX: CGFloat,
        deltaY: CGFloat,
        threshold: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        guard threshold > 0 else {
            return (0, 0)
        }

        let emitX = advance(&pendingX, by: deltaX, threshold: threshold)
        let emitY = advance(&pendingY, by: deltaY, threshold: threshold)
        return (emitX, emitY)
    }

    /// Forgets the remainder. Called when the gesture ends, so a new gesture
    /// starts from zero instead of inheriting credit from the last one.
    public mutating func reset() {
        pendingX = 0
        pendingY = 0
    }

    private func advance(
        _ pending: inout CGFloat,
        by delta: CGFloat,
        threshold: CGFloat
    ) -> CGFloat {
        guard delta.isFinite, delta != 0 else {
            return 0
        }

        // A reversal large enough to be deliberate drops the abandoned
        // remainder (the spec 037 rule, kept); wobble-scale reversal does
        // not (spec 043 FR-003). See `reversalJitterTolerance`.
        if pending != 0, (pending < 0) != (delta < 0), abs(delta) >= Self.reversalJitterTolerance {
            pending = 0
        }

        pending += delta
        let notches = (abs(pending) / threshold).rounded(.down)
        guard notches >= 1 else {
            return 0
        }

        let emitted = notches * threshold * (pending < 0 ? -1 : 1)
        pending -= emitted
        return emitted
    }
}
