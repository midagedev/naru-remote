import CoreGraphics
import XCTest
@testable import NaruRemoteCore

/// Spec 043 FR-001: a two-finger pinch that the user perceives as a pinch
/// resolves to `.zoom`, including when the finger midpoint drifts — while a
/// straight swipe stays `.scroll` (the 2026-08-19 defect this classifier was
/// built to prevent) and a decided gesture never changes meaning mid-gesture.
///
/// Founder report 2026-09-13 (physical iPhone): "헬퍼모드에서 줌인아웃 제대로
/// 안되" — H1: a pinch whose midpoint drifts faster than half its spread rate
/// crossed the 12 pt swipe bar before the 24 pt spread bar, and the frozen
/// decision then swallowed the whole gesture.
///
/// ## Contract ↔ assertion table (FR-001 → tests)
///
/// | FR-001 clause | Test |
/// |---|---|
/// | A symmetric pinch (out or in) resolves `.zoom` |
///   `testSymmetricPinchOutResolvesZoom`, `testSymmetricPinchInResolvesZoom` |
/// | A thumb-anchored pinch (spread grows exactly twice the midpoint travel)
///   resolves `.zoom` | `testThumbAnchoredPinchResolvesZoom` |
/// | A pinch whose midpoint drifts ~1 pt per callback while the fingers
///   spread resolves `.zoom`, not `.scroll` |
///   `testPinchWithHandDriftResolvesZoomNotScroll` (**the 2026-09-13 red**) |
/// | A straight swipe resolves `.scroll` (2026-08-19 regression guard) |
///   `testStraightSwipeUpResolvesScroll`, `testDiagonalSwipeResolvesScroll` |
/// | A slow swipe whose spread wobbles ±3 pt resolves `.scroll` |
///   `testSlowSwipeWithSpreadJitterResolvesScroll` |
/// | While neither signal dominates the other the gesture stays `.undecided` |
///   `testEqualSpreadAndTranslationHoldsUndecided`,
///   `testADriftingPinchStaysUndecidedUntilTheSpreadBar` |
/// | Once resolved, the decision holds (`resolve`'s guard is not removed) |
///   `testAResolvedPinchKeepsZoomWhileTheHandKeepsDrifting`,
///   `testAResolvedSwipeKeepsScrollWhenTheFingersSpreadLate` |
/// | The debug summary carries magnitudes and the verdict only — never touch
///   coordinates (constitution §IV) |
///   `testDescribeCarriesMagnitudesAndVerdictWithoutCoordinates` |
final class TwoFingerGestureShapeTests: XCTestCase {

    /// One recorded gesture shape: a per-callback sample stream of the two
    /// signals, exactly as `MetalFramebufferHostingView.updateTwoFingerIntent`
    /// feeds them — cumulative from gesture start.
    struct GestureShape {
        let name: String
        let samples: [(spreadDelta: CGFloat, translationMagnitude: CGFloat)]
        let expected: TwoFingerGestureIntent
    }

    /// Folds a shape through the real entry point the view uses
    /// (`resolve`), so the freeze-on-decision behaviour is exercised in the
    /// same pass as the classification.
    private func resolvedIntent(of shape: GestureShape) -> TwoFingerGestureIntent {
        var intent = TwoFingerGestureIntent.undecided
        for sample in shape.samples {
            intent = TwoFingerGestureClassifier.resolve(
                current: intent,
                spreadDelta: sample.spreadDelta,
                translationMagnitude: sample.translationMagnitude
            )
        }
        return intent
    }

    private func assertShape(
        _ shape: GestureShape,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            resolvedIntent(of: shape),
            shape.expected,
            "\(shape.name) resolved to the wrong intent",
            file: file,
            line: line
        )
    }

    // MARK: - The recorded shapes (FR-001's table)

    /// Both fingers move symmetrically apart, 3 pt per callback; the midpoint
    /// does not move.
    private static let symmetricPinchOut = GestureShape(
        name: "symmetricPinchOut",
        samples: (1...10).map { (CGFloat($0) * 3, CGFloat(0)) },
        expected: .zoom
    )

    /// Both fingers move symmetrically together (pinch in); direction of the
    /// spread change is irrelevant.
    private static let symmetricPinchIn = GestureShape(
        name: "symmetricPinchIn",
        samples: (1...10).map { (CGFloat($0) * -3, CGFloat(0)) },
        expected: .zoom
    )

    /// Thumb anchored, index finger pulling away: the spread grows exactly
    /// twice as fast as the midpoint (the midpoint is the average of the two
    /// fingers, so it moves at half the travelling finger's speed).
    private static let thumbAnchoredPinch = GestureShape(
        name: "thumbAnchoredPinch",
        samples: (1...14).map { (CGFloat($0) * 2, CGFloat($0)) },
        expected: .zoom
    )

    /// The founder's failed pinch (2026-09-13): fingers spreading 1.5 pt per
    /// callback while the whole hand drifts 1 pt per callback. The spread
    /// signal is 1.5× the drift — a user watching their fingers fly apart
    /// calls this a pinch. Under the pre-043 rule the swipe bar (12 pt) was
    /// crossed at sample 12 while the spread (18 pt) was still short of its
    /// 24 pt bar, so the gesture froze as `.scroll` and the zoom never ran.
    private static let pinchWithHandDrift = GestureShape(
        name: "pinchWithHandDrift",
        samples: (1...18).map { (CGFloat($0) * 1.5, CGFloat($0)) },
        expected: .zoom
    )

    /// Two fingers travelling straight up, 3 pt per callback, spread constant.
    private static let straightSwipeUp = GestureShape(
        name: "straightSwipeUp",
        samples: (1...8).map { (CGFloat(0), CGFloat($0) * -3) },
        expected: .scroll
    )

    /// A slow swipe (1.5 pt per callback) whose measured spread wobbles
    /// ±3 pt around its landing value — two fingers are never rigid.
    private static let slowSwipeWithSpreadJitter = GestureShape(
        name: "slowSwipeWithSpreadJitter",
        samples: [
            (+2, 1.5), (-1, 3), (+3, 4.5), (-2, 6), (+1, 7.5),
            (+2, 9), (-1, 10.5), (+3, 12), (-2, 13.5), (+1, 15),
            (+2, 16.5), (-1, 18),
        ].map { (CGFloat($0.0), CGFloat($0.1)) },
        expected: .scroll
    )

    /// Midpoint moves diagonally (magnitude grows 4 pt per callback), fingers
    /// rigid relative to each other.
    private static let diagonalSwipe = GestureShape(
        name: "diagonalSwipe",
        samples: (1...6).map { (CGFloat(0), CGFloat($0) * 4) },
        expected: .scroll
    )

    private static let allShapes: [GestureShape] = [
        symmetricPinchOut,
        symmetricPinchIn,
        thumbAnchoredPinch,
        pinchWithHandDrift,
        straightSwipeUp,
        slowSwipeWithSpreadJitter,
        diagonalSwipe,
    ]

    func testSymmetricPinchOutResolvesZoom() {
        assertShape(Self.symmetricPinchOut)
    }

    func testSymmetricPinchInResolvesZoom() {
        assertShape(Self.symmetricPinchIn)
    }

    func testThumbAnchoredPinchResolvesZoom() {
        assertShape(Self.thumbAnchoredPinch)
    }

    func testPinchWithHandDriftResolvesZoomNotScroll() {
        assertShape(Self.pinchWithHandDrift)
    }

    func testStraightSwipeUpResolvesScroll() {
        assertShape(Self.straightSwipeUp)
    }

    func testSlowSwipeWithSpreadJitterResolvesScroll() {
        assertShape(Self.slowSwipeWithSpreadJitter)
    }

    func testDiagonalSwipeResolvesScroll() {
        assertShape(Self.diagonalSwipe)
    }

    /// Every recorded shape resolves — none of them may hold `.undecided`
    /// to the end, or the gesture would do nothing at all.
    func testEveryRecordedShapeResolves() {
        for shape in Self.allShapes {
            XCTAssertNotEqual(
                resolvedIntent(of: shape),
                .undecided,
                "\(shape.name) never resolved; a real gesture must not end undecided",
            )
        }
    }

    // MARK: - The mirror-rule boundary

    /// At an exact tie (spread == translation) neither intent out-argues the
    /// other, so the gesture keeps waiting. This is the one point where the
    /// two documented defects (2026-08-19 spread-drift stealing a swipe;
    /// 2026-09-13 hand-drift stealing a pinch) meet, and the only safe
    /// resolution is more evidence.
    func testEqualSpreadAndTranslationHoldsUndecided() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 24, translationMagnitude: 24),
            .undecided
        )
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 12, translationMagnitude: 12),
            .undecided
        )
    }

    /// The drift pinch mid-flight: the swipe bar is crossed (12 pt) but the
    /// spread signal is bigger — still undecided, waiting for the spread bar.
    func testADriftingPinchStaysUndecidedUntilTheSpreadBar() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 18, translationMagnitude: 12),
            .undecided,
            "A gesture whose spread out-argues its travel must not be stolen by the swipe bar"
        )
    }

    /// A swipe whose fingers drift apart by less than the travel is a swipe.
    /// These are the pre-existing pins from the 2026-08-19 defect, restated
    /// beside the new rule so the mirror clause is seen to preserve them.
    func testASwipeWithIncidentalSpreadIsStillScrollUnderTheMirrorRule() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 18, translationMagnitude: 60),
            .scroll
        )
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 30, translationMagnitude: 90),
            .scroll
        )
    }

    // MARK: - The decision holds (resolve's guard stays)

    func testAResolvedPinchKeepsZoomWhileTheHandKeepsDrifting() {
        var intent = TwoFingerGestureIntent.undecided
        for sample in Self.pinchWithHandDrift.samples {
            intent = TwoFingerGestureClassifier.resolve(
                current: intent,
                spreadDelta: sample.spreadDelta,
                translationMagnitude: sample.translationMagnitude
            )
        }
        // The hand keeps travelling after the pinch was claimed.
        XCTAssertEqual(
            TwoFingerGestureClassifier.resolve(
                current: intent,
                spreadDelta: 27,
                translationMagnitude: 120
            ),
            .zoom,
            "A claimed zoom must not jump into a scroll when the hand keeps moving"
        )
    }

    func testAResolvedSwipeKeepsScrollWhenTheFingersSpreadLate() {
        var intent = TwoFingerGestureIntent.undecided
        for sample in Self.straightSwipeUp.samples {
            intent = TwoFingerGestureClassifier.resolve(
                current: intent,
                spreadDelta: sample.spreadDelta,
                translationMagnitude: sample.translationMagnitude
            )
        }
        XCTAssertEqual(intent, .scroll)
        XCTAssertEqual(
            TwoFingerGestureClassifier.resolve(
                current: intent,
                spreadDelta: 200,
                translationMagnitude: 24
            ),
            .scroll,
            "A long scroll that spreads at the end must not jump into a zoom"
        )
    }

    // MARK: - Debuggability (spec 043 §9 layer 3)

    /// The classifier's debug summary names the two magnitudes and the
    /// verdict. Its inputs are aggregate distances by construction — there is
    /// no touch coordinate in it to leak (constitution §IV).
    func testDescribeCarriesMagnitudesAndVerdictWithoutCoordinates() {
        let summary = TwoFingerGestureClassifier.describe(
            spreadDelta: 18,
            translationMagnitude: 12
        )
        XCTAssertTrue(summary.contains("spread"), "the summary names the spread signal")
        XCTAssertTrue(summary.contains("translation"), "the summary names the translation signal")
        XCTAssertTrue(
            summary.contains("undecided") || summary.contains("scroll") || summary.contains("zoom"),
            "the summary names the verdict"
        )
    }
}
