import XCTest
@testable import NaruRemoteCore

final class ViewportGestureRedrawThrottleTests: XCTestCase {
    func testInactiveGestureRequestsEveryFrameAndResetsDeferredState() {
        var throttle = ViewportGestureRedrawThrottle(minimumInterval: 1.0 / 15.0)

        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 10.0), .requestNow)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 10.01), .deferRedraw)

        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: false, now: 10.02), .requestNow)
        XCTAssertFalse(throttle.flushAfterGesture())
    }

    func testActiveGestureAllowsFirstFrameThenCoalescesUntilInterval() {
        var throttle = ViewportGestureRedrawThrottle(minimumInterval: 0.1)

        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 1.0), .requestNow)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 1.03), .deferRedraw)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 1.09), .deferRedraw)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 1.10), .requestNow)
    }

    func testThirtyHertzCadenceRejectsSixtyHertzFloodButAllowsNextFrameSlot() {
        var throttle = ViewportGestureRedrawThrottle(minimumInterval: 1.0 / 30.0)

        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 0.000), .requestNow)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 0.016), .deferRedraw)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 0.034), .requestNow)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 0.050), .deferRedraw)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 0.068), .requestNow)
    }

    func testViewportInteractionCadenceKeepsBoundedLiveGestureFrames() {
        let interval = StreamPressurePacingDefaults.viewportInteractionContentFrameIntervalSeconds
        var throttle = ViewportGestureRedrawThrottle(
            minimumInterval: interval,
            allowsFirstRedrawDuringGesture: true
        )

        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 0.000), .requestNow)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: interval / 2), .deferRedraw)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: interval), .requestNow)
    }

    func testViewportInteractionCadenceStaysFourHertzClass() {
        XCTAssertEqual(
            StreamPressurePacingDefaults.viewportInteractionContentFrameIntervalSeconds,
            1.0 / 4.0,
            accuracy: 0.0001
        )
    }

    func testStrictGestureModeDefersEveryFrameUntilGestureEnd() {
        var throttle = ViewportGestureRedrawThrottle(
            minimumInterval: .infinity,
            allowsFirstRedrawDuringGesture: false
        )

        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 1.0), .deferRedraw)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 1.5), .deferRedraw)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 2.0), .deferRedraw)
        XCTAssertTrue(throttle.flushAfterGesture())
        XCTAssertFalse(throttle.flushAfterGesture())
    }

    func testGestureEndFlushesOnlyWhenAFrameWasDeferred() {
        var throttle = ViewportGestureRedrawThrottle(minimumInterval: 0.1)

        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 2.0), .requestNow)
        XCTAssertFalse(throttle.flushAfterGesture())

        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 3.0), .requestNow)
        XCTAssertEqual(throttle.recordIncomingFrame(isGestureActive: true, now: 3.01), .deferRedraw)
        XCTAssertTrue(throttle.flushAfterGesture())
        XCTAssertFalse(throttle.flushAfterGesture())
    }
}
