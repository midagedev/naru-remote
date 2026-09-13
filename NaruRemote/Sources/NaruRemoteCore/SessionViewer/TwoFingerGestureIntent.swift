import CoreGraphics
import Foundation

/// What a two-finger gesture on the remote screen means.
///
/// Two fingers are overloaded: swiping them is how every touch platform
/// scrolls, and spreading them is how every touch platform zooms. Both
/// recognizers see the same touches, and the viewport used to let both act at
/// once — so a two-finger scroll also nudged the local zoom and pan, which is
/// what the founder hit on a device (2026-08-19): "손가락 두개를 이용한 드래그가
/// 보통 스크롤인데 이게 원격화면 패닝이랑 겹칠거같고."
///
/// Chrome Remote Desktop resolves the same overload by never letting the two
/// compete: a two-finger swipe is *always* the remote scroll wheel, and moving
/// the view is a different gesture entirely (one finger, or the cursor pushing
/// the edge in trackpad mode). This classifier is that rule made explicit —
/// decide once per gesture from the first movement, then hold the decision
/// until the fingers lift, so a gesture never changes meaning underneath the
/// user.
public enum TwoFingerGestureIntent: Equatable, Sendable {
    /// Not enough movement yet to tell. Neither handler should act.
    case undecided
    /// Swipe: remote scroll wheel.
    case scroll
    /// Pinch: local zoom (constitution §I — never sent to the remote).
    case zoom
}

public enum TwoFingerGestureClassifier: Sendable {
    /// How far the fingers' midpoint must travel before a swipe is a swipe.
    /// Low enough that scrolling starts promptly (`straightSwipeUp` resolves
    /// on its 4th sample at 3 pt per callback), high enough that the jitter
    /// of two fingers landing is not read as movement (`slowSwipeWithSpreadJitter`
    /// wobbles ±3 pt without ever pretending to travel).
    public static let translationThreshold: CGFloat = 12

    /// How much the distance between the fingers must change before a pinch is
    /// a pinch. Deliberately larger than `translationThreshold`: fingers
    /// spread slightly during almost every swipe (`slowSwipeWithSpreadJitter`
    /// wobbles ±3 pt; a travelling pair drifts apart by a third of its travel
    /// or less — 18 pt of spread against 60 pt of travel), and treating that
    /// as zoom is the 2026-08-19 defect this type exists to prevent. 24 pt is
    /// above every incidental-drift shape recorded so far and still reached
    /// by the second sample of a deliberate pinch (`symmetricPinchOut` at
    /// 3 pt per callback resolves on its 8th).
    public static let spreadThreshold: CGFloat = 24

    /// - Parameters:
    ///   - spreadDelta: current distance between the fingers minus the distance
    ///     when they landed, in points. Sign is irrelevant — pinching in and
    ///     out are both zoom.
    ///   - translationMagnitude: how far the midpoint between the fingers has
    ///     moved from where it started, in points.
    public static func classify(
        spreadDelta: CGFloat,
        translationMagnitude: CGFloat
    ) -> TwoFingerGestureIntent {
        let spread = abs(spreadDelta)
        let translation = abs(translationMagnitude)

        guard spread.isFinite, translation.isFinite else {
            return .undecided
        }

        // Each intent has to beat BOTH bars: its own threshold and the other
        // signal. The zoom clause always required the spread to out-argue the
        // swipe; before spec 043 the scroll clause did not have its mirror,
        // so a swipe bar crossed at 12 pt won by arriving first even while the
        // spread signal was the bigger one — the founder's pinch with hand
        // drift (2026-09-13: fingers spreading 1.5 pt per callback while the
        // hand drifted 1 pt; sample 12 was spread 18 / translation 12, and the
        // gesture froze as scroll) lost to a swipe the user never made. The
        // mirror clause holds such a gesture undecided until one signal truly
        // dominates; at an exact tie neither is more credible than the other,
        // and the tie is exactly the boundary between the two documented
        // defects (2026-08-19 spread-drift stealing a swipe, 2026-09-13
        // hand-drift stealing a pinch), so waiting for more evidence is the
        // only resolution that cannot resurrect either.
        if spread >= spreadThreshold, spread > translation {
            return .zoom
        }
        if translation >= translationThreshold, translation > spread {
            return .scroll
        }
        return .undecided
    }

    /// Applies a new reading to a decision already taken. Once a gesture means
    /// something it keeps meaning it until the fingers lift — otherwise a long
    /// scroll that happens to spread at the end would jump into a zoom.
    public static func resolve(
        current: TwoFingerGestureIntent,
        spreadDelta: CGFloat,
        translationMagnitude: CGFloat
    ) -> TwoFingerGestureIntent {
        guard current == .undecided else {
            return current
        }
        return classify(spreadDelta: spreadDelta, translationMagnitude: translationMagnitude)
    }

    /// What the remote scroll path should receive for one two-finger pan
    /// callback (spec 043 FR-002).
    ///
    /// A gesture only resolves after its winning signal clears a bar, and
    /// until then the pan handler returns early — so before spec 043 every
    /// two-finger scroll silently discarded its first `translationThreshold`
    /// points: half a wheel notch on a 24-point notch, and the whole first
    /// notch of a short drag ("스크롤의 양이 엄청 적을때가 있어", 2026-09-13).
    /// This function is the single owner of that delivery rule: on the
    /// callback where the gesture resolves to `.scroll`, the travel
    /// accumulated while it was `.undecided` — including that callback's own
    /// delta — is delivered exactly once; later callbacks deliver their own
    /// delta only, so nothing is double-counted.
    ///
    /// A gesture that resolves to `.zoom` (or never resolves) delivers
    /// nothing, on every callback including the final one — UIKit has already
    /// dropped the touch count to zero by then, so the *instantaneous* touch
    /// count must not be what gates the delivery; `hasTwoFingerBaseline`
    /// (whether a two-finger spread was ever measured this gesture) is. A
    /// hardware trackpad scroll never sets that baseline and is unambiguous,
    /// so it delivers every callback's delta unchanged.
    ///
    /// - Parameters:
    ///   - previousIntent: the decision in force before this callback ran.
    ///   - resolvedIntent: the decision in force after this callback ran.
    ///   - accumulatedTranslation: the gesture's total travel so far, this
    ///     callback's delta included.
    ///   - callbackDelta: this callback's incremental delta.
    ///   - hasTwoFingerBaseline: whether a two-finger touch pair was ever
    ///     measured for this gesture.
    /// - Returns: the delta the scroll path should receive, or `nil` when
    ///   this callback must not scroll.
    public static func scrollDelta(
        previousIntent: TwoFingerGestureIntent,
        resolvedIntent: TwoFingerGestureIntent,
        accumulatedTranslation: CGSize,
        callbackDelta: CGSize,
        hasTwoFingerBaseline: Bool
    ) -> CGSize? {
        if hasTwoFingerBaseline, resolvedIntent != .scroll {
            return nil
        }
        guard resolvedIntent == .scroll, hasTwoFingerBaseline else {
            // No baseline: a hardware trackpad scroll. Unambiguous, always a
            // scroll, and it never resolves through the classifier — so the
            // intents are irrelevant here and every callback delivers its own
            // delta unchanged.
            return callbackDelta
        }
        if previousIntent == .undecided {
            // The resolving callback: the undecided prefix is delivered here,
            // exactly once. Later callbacks see `previousIntent == .scroll`
            // and deliver their own delta, so the prefix is not re-counted.
            return accumulatedTranslation
        }
        return callbackDelta
    }

    /// Distance between two touch points, in points.
    public static func spread(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// One-line summary of a decision, for the debug ring buffer the session
    /// viewport keeps (spec 043 §9): a future "the gesture went the wrong
    /// way" report is answered from the recorded magnitudes and verdicts
    /// instead of a device replay. Inputs are aggregate distances only —
    /// there is no touch coordinate here to leak (constitution §IV).
    public static func describe(
        spreadDelta: CGFloat,
        translationMagnitude: CGFloat
    ) -> String {
        let intent = classify(
            spreadDelta: spreadDelta,
            translationMagnitude: translationMagnitude
        )
        return "spread=\(abs(spreadDelta)) translation=\(abs(translationMagnitude)) -> \(intent)"
    }

    public static func magnitude(_ translation: CGSize) -> CGFloat {
        (translation.width * translation.width + translation.height * translation.height)
            .squareRoot()
    }
}
