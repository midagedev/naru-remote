import CoreGraphics
import XCTest
@testable import NaruRemoteCore

/// Spec 037: the arithmetic that decides when accumulated motion is worth a
/// remote wheel notch.
///
/// This existed only as a comment before — `sendScrollAt` said "the caller is
/// expected to accumulate across `.changed` callbacks" and no caller did, so a
/// comfortable two-finger drag scrolled nothing.
final class ScrollTickAccumulatorTests: XCTestCase {

    private let threshold: CGFloat = 24

    // MARK: - FR-001 the remainder is carried

    /// The founder's actual gesture: a steady drag delivering a few points per
    /// callback. Under the old arithmetic every one of these was
    /// `floor(4 / 24) = 0` and the motion was thrown away.
    func testAStreamOfSubThresholdDeltasEventuallyEmitsANotch() {
        var accumulator = ScrollTickAccumulator()
        var emitted: [CGFloat] = []

        for _ in 0..<6 {
            let step = accumulator.accumulate(deltaX: 0, deltaY: 4, threshold: threshold)
            if step.y != 0 {
                emitted.append(step.y)
            }
        }

        XCTAssertEqual(
            emitted,
            [threshold],
            "Six 4-point callbacks are 24 points of travel — exactly one notch, once"
        )
    }

    func testTheRemainderSurvivesIntoTheNextNotch() {
        var accumulator = ScrollTickAccumulator()

        // 30 points: one notch out, 6 left over.
        let first = accumulator.accumulate(deltaX: 0, deltaY: 30, threshold: threshold)
        XCTAssertEqual(first.y, threshold)
        XCTAssertEqual(accumulator.pendingY, 6, accuracy: 0.0001)

        // 18 more reaches 24 again only because the 6 was kept.
        let second = accumulator.accumulate(deltaX: 0, deltaY: 18, threshold: threshold)
        XCTAssertEqual(
            second.y,
            threshold,
            "Without the carry this second callback is 18 points and emits nothing"
        )
    }

    func testALargeDeltaStillEmitsEveryNotchAtOnce() {
        var accumulator = ScrollTickAccumulator()

        let emitted = accumulator.accumulate(deltaX: 0, deltaY: -50, threshold: threshold)

        XCTAssertEqual(emitted.y, -48, "Two notches, sign preserved")
        XCTAssertEqual(accumulator.pendingY, -2, accuracy: 0.0001)
    }

    func testAxesAccumulateIndependently() {
        var accumulator = ScrollTickAccumulator()

        _ = accumulator.accumulate(deltaX: 20, deltaY: 4, threshold: threshold)
        let emitted = accumulator.accumulate(deltaX: 8, deltaY: 4, threshold: threshold)

        XCTAssertEqual(emitted.x, threshold, "28 points across two callbacks is a horizontal notch")
        XCTAssertEqual(emitted.y, 0, "8 points of vertical is not, and must not ride along")
    }

    // MARK: - FR-003 a reversal does not spend backwards

    func testReversingDirectionDropsTheAbandonedRemainder() {
        var accumulator = ScrollTickAccumulator()

        // Most of a notch upward, then the user changes their mind.
        _ = accumulator.accumulate(deltaX: 0, deltaY: 20, threshold: threshold)
        let emitted = accumulator.accumulate(deltaX: 0, deltaY: -6, threshold: threshold)

        XCTAssertEqual(emitted.y, 0)
        XCTAssertEqual(
            accumulator.pendingY,
            -6,
            accuracy: 0.0001,
            "The 20 points of abandoned upward motion are gone, not spent downward"
        )
    }

    // MARK: - FR-004 a gesture end clears it

    func testResetForgetsTheRemainder() {
        var accumulator = ScrollTickAccumulator()
        _ = accumulator.accumulate(deltaX: 12, deltaY: 20, threshold: threshold)

        accumulator.reset()

        XCTAssertEqual(accumulator.pendingX, 0)
        XCTAssertEqual(accumulator.pendingY, 0)
        let emitted = accumulator.accumulate(deltaX: 0, deltaY: 20, threshold: threshold)
        XCTAssertEqual(
            emitted.y,
            0,
            "A new gesture starts from zero rather than inheriting the last one's credit"
        )
    }

    // MARK: - Degenerate inputs

    func testNonFiniteAndZeroDeltasAreIgnored() {
        var accumulator = ScrollTickAccumulator()

        _ = accumulator.accumulate(deltaX: .nan, deltaY: .infinity, threshold: threshold)
        _ = accumulator.accumulate(deltaX: 0, deltaY: 0, threshold: threshold)

        XCTAssertEqual(accumulator.pendingX, 0)
        XCTAssertEqual(accumulator.pendingY, 0)
    }

    func testANonPositiveThresholdEmitsNothing() {
        var accumulator = ScrollTickAccumulator()

        let emitted = accumulator.accumulate(deltaX: 100, deltaY: 100, threshold: 0)

        XCTAssertEqual(emitted.x, 0)
        XCTAssertEqual(emitted.y, 0)
    }
}
