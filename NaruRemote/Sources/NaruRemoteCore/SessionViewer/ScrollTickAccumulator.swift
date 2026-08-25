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

    public init() {}

    /// Adds one callback's delta and returns the part that is worth whole
    /// notches, keeping the remainder for the next callback.
    ///
    /// A direction reversal on an axis drops that axis's remainder rather than
    /// spending it backwards: motion the user has already abandoned must not
    /// arrive as a notch in the opposite direction.
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

        if pending != 0, (pending < 0) != (delta < 0) {
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
