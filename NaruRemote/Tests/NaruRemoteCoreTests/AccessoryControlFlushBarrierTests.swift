import XCTest
@testable import NaruRemoteCore

/// Spec 012 US2-3 — marked commit before keysym; flush failure drops
/// the control (orca `sendTerminalLiveControlAfterPendingFlush`).
final class FlushBarrierTests: XCTestCase {
    func testMarkedCompositionIsCommittedBeforeControlEmission() {
        let steps = FlushBarrier.steps(
            hasMarkedText: true,
            pendingFlush: .succeeded
        )
        XCTAssertEqual(steps.first, .commitMarkedText)
        XCTAssertEqual(steps.last, .emitControl)
        XCTAssertLessThan(
            steps.firstIndex(of: .commitMarkedText) ?? .max,
            steps.firstIndex(of: .emitControl) ?? .min,
            "Committed text must precede the keysym"
        )
        XCTAssertFalse(steps.contains(.dropControl))
    }

    func testFlushFailureDropsControlAndDoesNotEmit() {
        let steps = FlushBarrier.steps(
            hasMarkedText: false,
            pendingFlush: .failed
        )
        XCTAssertEqual(steps, [.dropControl])
        XCTAssertFalse(steps.contains(.emitControl), "Failed flush must not emit")
        XCTAssertFalse(FlushBarrier.shouldEmitAfterFlush(succeeded: false))
        XCTAssertTrue(FlushBarrier.shouldEmitAfterFlush(succeeded: true))
    }

    func testMarkedThenFailedFlushStillDropsControl() {
        let steps = FlushBarrier.steps(
            hasMarkedText: true,
            pendingFlush: .failed
        )
        XCTAssertEqual(steps, [.commitMarkedText, .dropControl])
        XCTAssertFalse(steps.contains(.emitControl))
    }

    func testNoMarkedTextAndNoPendingFlushEmitsImmediately() {
        let steps = FlushBarrier.steps(
            hasMarkedText: false,
            pendingFlush: .notNeeded
        )
        XCTAssertEqual(steps, [.emitControl])
    }
}
