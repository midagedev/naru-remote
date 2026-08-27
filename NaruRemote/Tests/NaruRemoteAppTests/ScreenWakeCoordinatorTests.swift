import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Spec 039 FR-003, the applying half.
///
/// `ScreenWakePolicy` says what should happen; this is the object that writes
/// `isIdleTimerDisabled`, and the failure mode it exists to prevent is a hold
/// that outlives its session. So the assertions are about *writes*: how many,
/// in what order, and whether the last one is always a release.
@MainActor
final class ScreenWakeCoordinatorTests: XCTestCase {

    private final class Recorder {
        private(set) var writes: [Bool] = []
        func record(_ value: Bool) { writes.append(value) }
    }

    private func makeCoordinator() -> (ScreenWakeCoordinator, Recorder) {
        let recorder = Recorder()
        let coordinator = ScreenWakeCoordinator { recorder.record($0) }
        return (coordinator, recorder)
    }

    private func hold() -> ScreenWakeResolution {
        ScreenWakeResolution(decision: .holdAwake, reason: .sessionLive)
    }

    private func sleep(_ reason: ScreenWakeResolution.Reason) -> ScreenWakeResolution {
        ScreenWakeResolution(decision: .allowSleep, reason: reason)
    }

    func testRaisingTheHoldWritesItOnce() {
        let (coordinator, recorder) = makeCoordinator()

        coordinator.update(with: hold())

        XCTAssertEqual(recorder.writes, [true])
    }

    /// The shell re-resolves on every session and scene change, which is far
    /// more often than the answer changes. A setter that re-fires on every
    /// render is a setter whose cost nobody budgeted.
    func testRepeatingTheSameAnswerWritesNothingFurther() {
        let (coordinator, recorder) = makeCoordinator()

        coordinator.update(with: hold())
        coordinator.update(with: hold())
        coordinator.update(with: hold())

        XCTAssertEqual(recorder.writes, [true])
    }

    func testEndingTheSessionLowersTheHold() {
        let (coordinator, recorder) = makeCoordinator()

        coordinator.update(with: hold())
        coordinator.update(with: sleep(.noSession))

        XCTAssertEqual(recorder.writes, [true, false])
    }

    /// The path that has no resolution to consult: the view is going away.
    func testReleaseLowersTheHoldWithoutBeingAskedToResolve() {
        let (coordinator, recorder) = makeCoordinator()

        coordinator.update(with: hold())
        coordinator.release()

        XCTAssertEqual(recorder.writes, [true, false])
        XCTAssertEqual(coordinator.lastResolution?.reason, .appNotForeground)
    }

    func testReleasingWhenNothingIsHeldWritesNothing() {
        let (coordinator, recorder) = makeCoordinator()

        coordinator.release()

        XCTAssertEqual(
            recorder.writes,
            [],
            "A coordinator that never held the screen has nothing to give back"
        )
    }

    /// Whatever the sequence, the flag ends down. This is the property the
    /// whole type exists for.
    func testEveryOrderingEndsWithTheHoldReleased() {
        let sequences: [[ScreenWakeResolution]] = [
            [hold(), sleep(.noSession)],
            [hold(), sleep(.appNotForeground), hold(), sleep(.userDeclined)],
            [sleep(.noSession), hold(), hold(), sleep(.noSession)],
            [hold(), hold(), sleep(.userDeclined)]
        ]

        for sequence in sequences {
            let (coordinator, recorder) = makeCoordinator()
            for resolution in sequence {
                coordinator.update(with: resolution)
            }

            XCTAssertEqual(
                recorder.writes.last,
                false,
                "Sequence ending in \(sequence.map(\.reason.rawValue)) left the screen held"
            )
        }
    }
}
