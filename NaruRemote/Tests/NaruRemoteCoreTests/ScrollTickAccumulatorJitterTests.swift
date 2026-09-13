import CoreGraphics
import XCTest
@testable import NaruRemoteCore

/// Spec 043 FR-003: `ScrollTickAccumulator` must not discard the pending
/// remainder on jitter-scale sign reversals; a reversal that represents a real
/// direction change still does.
///
/// Founder report 2026-09-13 (physical iPhone): "vnc모드에서 두손가락 드래그
/// 스크롤의 양이 엄청 적을때가 있어" — H3: `advance` zeroed an axis's pending
/// remainder on *any* sign reversal, and two fingers dragged slowly wobble by
/// a point or two per callback, so the remainder was repeatedly discarded
/// before it could reach a notch — worst exactly when the user scrolls
/// gently.
///
/// ## Contract ↔ assertion table (FR-003 → tests)
///
/// | FR-003 clause | Test |
/// |---|---|
/// | Jitter-scale reversals (below `reversalJitterTolerance` points against
///   the pending remainder) keep the remainder |
///   `testJitterScaleReversalsStillReachANotch` (**the 2026-09-13 red**),
///   `testBothSidesOfTheJitterBoundary` (below-tolerance side),
///   `testJitterOnTheIdleAxisDoesNotDisturbTheScrollingAxis` |
/// | A real direction change still drops the abandoned remainder |
///   `testBothSidesOfTheJitterBoundary` (at-tolerance side),
///   `testASlowRealReversalDropsTheRemainderOnceItsMagnitudeIsReal` |
/// | A gesture end still clears everything (spec 037 FR-004 unchanged) |
///   `testResetStillForgetsTheRemainder` |
final class ScrollTickAccumulatorJitterTests: XCTestCase {

    private let threshold: CGFloat = 24

    // MARK: - The founder's slow drag (FR-003's red)

    /// A slow two-finger drag at 60–120 Hz: ~2 pt of travel per callback with
    /// ±1 pt of wobble. Under the pre-043 rule every wobble reset the
    /// accumulator, so the pending remainder cycled 2 → −1 → 2 → −1 and never
    /// reached the 24 pt notch — a drag of any length scrolled nothing.
    func testJitterScaleReversalsStillReachANotch() {
        var accumulator = ScrollTickAccumulator()
        var emittedNotches: [CGFloat] = []

        // 24 callback pairs: +2 of travel, then −1 of wobble. Net travel is
        // 24 points — one notch — but the signal crosses zero on every
        // second callback.
        for _ in 0..<24 {
            for delta in [CGFloat(2), CGFloat(-1)] {
                let emitted = accumulator.accumulate(deltaX: 0, deltaY: delta, threshold: threshold)
                if emitted.y != 0 {
                    emittedNotches.append(emitted.y)
                }
            }
        }

        XCTAssertEqual(
            emittedNotches,
            [threshold],
            "24 net points of wobbly travel are one notch; jitter must not reset the credit"
        )
    }

    // MARK: - The boundary, both sides

    /// The reversal boundary is `reversalJitterTolerance` points (2 pt):
    /// a reversal of 1.9 pt against a 20-point remainder is jitter (kept);
    /// a reversal of 2 pt is a real direction change (dropped).
    func testBothSidesOfTheJitterBoundary() {
        // Below tolerance — jitter: the remainder survives, eroded by the
        // wobble rather than discarded.
        var jittery = ScrollTickAccumulator()
        _ = jittery.accumulate(deltaX: 0, deltaY: 20, threshold: threshold)
        let jitterEmitted = jittery.accumulate(deltaX: 0, deltaY: -1.9, threshold: threshold)
        XCTAssertEqual(jitterEmitted.y, 0)
        XCTAssertEqual(
            jittery.pendingY,
            18.1,
            accuracy: 0.0001,
            "A 1.9-point reversal is wobble; the 20-point remainder is eroded, not dropped"
        )

        // At tolerance — real: the abandoned remainder is gone, not spent
        // backwards.
        var decisive = ScrollTickAccumulator()
        _ = decisive.accumulate(deltaX: 0, deltaY: 20, threshold: threshold)
        let realEmitted = decisive.accumulate(deltaX: 0, deltaY: -2, threshold: threshold)
        XCTAssertEqual(realEmitted.y, 0)
        XCTAssertEqual(
            decisive.pendingY,
            -2,
            accuracy: 0.0001,
            "A 2-point reversal is a direction change; the abandoned 20 points are dropped"
        )
    }

    /// A finger pair wobbles on both axes while the user scrolls along one.
    /// The idle axis's jitter must not disturb the scrolling axis's credit
    /// (spec 037's axis independence, restated beside the jitter rule). The
    /// 25 callbacks below carry 50 points of vertical travel — two notches —
    /// against ±1 pt of horizontal wobble.
    func testJitterOnTheIdleAxisDoesNotDisturbTheScrollingAxis() {
        var accumulator = ScrollTickAccumulator()
        var emittedY: CGFloat = 0
        var emittedX: CGFloat = 0

        for _ in 0..<12 {
            for delta in [(CGFloat(1), CGFloat(2)), (CGFloat(-1), CGFloat(2))] {
                let emitted = accumulator.accumulate(
                    deltaX: delta.0,
                    deltaY: delta.1,
                    threshold: threshold
                )
                emittedY += emitted.y
                emittedX += emitted.x
            }
        }
        let tail = accumulator.accumulate(deltaX: 1, deltaY: 2, threshold: threshold)
        emittedY += tail.y
        emittedX += tail.x

        XCTAssertEqual(
            emittedY,
            threshold * 2,
            "50 points of vertical travel are two notches regardless of horizontal wobble"
        )
        XCTAssertEqual(emittedX, 0, "The idle axis's wobble never adds up to a notch")
    }

    /// A deliberate reversal often starts slowly (the finger passing through
    /// zero velocity): −1, −2, −4… The first sub-tolerance sample erodes the
    /// remainder; the first at-tolerance sample drops what is left. The
    /// abandoned credit never arrives as a notch in the new direction.
    func testASlowRealReversalDropsTheRemainderOnceItsMagnitudeIsReal() {
        var accumulator = ScrollTickAccumulator()
        _ = accumulator.accumulate(deltaX: 0, deltaY: 20, threshold: threshold)

        _ = accumulator.accumulate(deltaX: 0, deltaY: -1, threshold: threshold)
        XCTAssertEqual(accumulator.pendingY, 19, accuracy: 0.0001)

        _ = accumulator.accumulate(deltaX: 0, deltaY: -3, threshold: threshold)
        XCTAssertEqual(
            accumulator.pendingY,
            -3,
            accuracy: 0.0001,
            "Once the reversal is real, the eroded remainder is dropped rather than spent backwards"
        )
    }

    // MARK: - Spec 037 behavior unchanged

    func testResetStillForgetsTheRemainder() {
        var accumulator = ScrollTickAccumulator()
        _ = accumulator.accumulate(deltaX: 0, deltaY: 20, threshold: threshold)

        accumulator.reset()

        XCTAssertEqual(accumulator.pendingY, 0)
    }
}
