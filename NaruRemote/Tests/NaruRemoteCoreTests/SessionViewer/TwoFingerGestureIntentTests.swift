import CoreGraphics
import XCTest
@testable import NaruRemoteCore

/// Two fingers mean either scroll or zoom, never both at once (2026-08-19
/// device report: a two-finger scroll was also dragging the viewport).
final class TwoFingerGestureIntentTests: XCTestCase {

    func testAPlainSwipeIsScroll() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 0, translationMagnitude: 40),
            .scroll
        )
    }

    /// The defect this exists for: fingers drift apart during a normal swipe,
    /// and that drift must not be read as a pinch.
    func testASwipeWithIncidentalSpreadIsStillScroll() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 18, translationMagnitude: 60),
            .scroll
        )
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 30, translationMagnitude: 90),
            .scroll,
            "Spread must out-argue the swipe, not merely clear its own threshold"
        )
    }

    func testSpreadingApartIsZoom() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 60, translationMagnitude: 4),
            .zoom
        )
    }

    func testPinchingInIsAlsoZoom() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: -60, translationMagnitude: 4),
            .zoom,
            "Direction is irrelevant — both ways are a zoom"
        )
    }

    func testTinyMovementDecidesNothing() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 3, translationMagnitude: 5),
            .undecided,
            "Two fingers landing jitter; that must not start a scroll"
        )
    }

    func testNonFiniteInputDecidesNothing() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: .nan, translationMagnitude: 40),
            .undecided
        )
        XCTAssertEqual(
            TwoFingerGestureClassifier.classify(spreadDelta: 0, translationMagnitude: .infinity),
            .undecided
        )
    }

    // MARK: - The decision holds

    func testADecisionSurvivesLaterMovementOfTheOtherKind() {
        let scrolling = TwoFingerGestureClassifier.resolve(
            current: .scroll,
            spreadDelta: 200,
            translationMagnitude: 0
        )
        XCTAssertEqual(
            scrolling,
            .scroll,
            "A long scroll that spreads at the end must not jump into a zoom"
        )

        let zooming = TwoFingerGestureClassifier.resolve(
            current: .zoom,
            spreadDelta: 0,
            translationMagnitude: 200
        )
        XCTAssertEqual(zooming, .zoom)
    }

    func testAnUndecidedGestureStillDecides() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.resolve(
                current: .undecided,
                spreadDelta: 0,
                translationMagnitude: 40
            ),
            .scroll
        )
    }

    // MARK: - Geometry helpers

    func testSpreadIsTheDistanceBetweenTheTouches() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.spread(CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4)),
            5,
            accuracy: 0.0001
        )
    }

    func testMagnitudeIsTheTranslationLength() {
        XCTAssertEqual(
            TwoFingerGestureClassifier.magnitude(CGSize(width: -3, height: 4)),
            5,
            accuracy: 0.0001
        )
    }
}
