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
    /// Low enough that scrolling starts promptly, high enough that the jitter
    /// of two fingers landing is not read as movement.
    public static let translationThreshold: CGFloat = 12

    /// How much the distance between the fingers must change before a pinch is
    /// a pinch. Deliberately larger than `translationThreshold`: fingers spread
    /// slightly during almost every swipe, and treating that as zoom is the
    /// defect this type exists to prevent.
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

        // Zoom has to out-argue the swipe, not merely clear its own bar: two
        // fingers travelling together across the screen also drift apart a
        // little, and that drift must not win.
        if spread >= spreadThreshold, spread > translation {
            return .zoom
        }
        if translation >= translationThreshold {
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

    /// Distance between two touch points, in points.
    public static func spread(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return (dx * dx + dy * dy).squareRoot()
    }

    public static func magnitude(_ translation: CGSize) -> CGFloat {
        (translation.width * translation.width + translation.height * translation.height)
            .squareRoot()
    }
}
