import XCTest
@testable import NaruRemoteCore

/// Spec 032. These assertions exist here — in a pure Core test — because the
/// crash they describe cannot be reproduced on any runner this repository can
/// gate on: `AVPictureInPictureController.isPictureInPictureSupported()` is
/// false on the iPhone 17 Pro simulator (iOS 26.2), so `PiPWatchReentryUITests`
/// skips. What can be gated is the decision the platform adapter makes, and
/// that decision lives in this value type.
final class PiPWatchControllerLifecycleTests: XCTestCase {

    // MARK: - FR-001: one controller per layer

    func testSecondPrepareReusesTheController() {
        var lifecycle = PiPWatchControllerLifecycle()

        XCTAssertEqual(lifecycle.prepare(), .createController)
        XCTAssertEqual(lifecycle.prepare(), .reuseController)
        XCTAssertEqual(lifecycle.prepare(), .reuseController)

        XCTAssertEqual(
            lifecycle.controllerCreationCount,
            1,
            "A second content source over the same layer is the reported crash."
        )
    }

    func testPrepareAfterAnActiveSessionEndsBuildsAFreshController() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)
        lifecycle.noteStarted()

        lifecycle.invalidate()

        XCTAssertFalse(lifecycle.hasController)
        XCTAssertFalse(lifecycle.isEngaged)
        XCTAssertEqual(lifecycle.prepare(), .createController)
        XCTAssertEqual(lifecycle.controllerCreationCount, 2)
        XCTAssertEqual(lifecycle.lastStopReason, .sessionEnded)
    }

    // MARK: - FR-002: the guarded start

    func testEntryIsRefusedWhenAWindowIsAlreadyUp() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()
        XCTAssertEqual(lifecycle.requestEntry(isPictureInPicturePossible: true), .start)
        lifecycle.noteStarted()

        let second = lifecycle.requestEntry(isPictureInPicturePossible: true)

        XCTAssertEqual(second, .refused(.alreadyActive))
        XCTAssertEqual(lifecycle.entryRequestCount, 2)
        XCTAssertEqual(lifecycle.startRefusalCount, 1)
        XCTAssertEqual(lifecycle.phase, .active, "A refusal must not disturb the live window.")
    }

    func testEntryIsRefusedWhileAStartIsStillInFlight() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)

        XCTAssertEqual(
            lifecycle.requestEntry(isPictureInPicturePossible: true),
            .refused(.startInFlight)
        )
    }

    func testEntryIsRefusedWhileAStopIsStillInFlight() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)
        lifecycle.noteStarted()
        XCTAssertTrue(lifecycle.requestStop())

        XCTAssertEqual(
            lifecycle.requestEntry(isPictureInPicturePossible: true),
            .refused(.stopInFlight),
            "Starting into a teardown is the second hazard spec 032 closes."
        )
    }

    func testEntryIsRefusedWhenTheSystemSaysItIsNotPossible() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()

        XCTAssertEqual(
            lifecycle.requestEntry(isPictureInPicturePossible: false),
            .refused(.notPossible)
        )
        XCTAssertEqual(lifecycle.phase, .prepared)
    }

    func testEntryIsRefusedWithNoController() {
        var lifecycle = PiPWatchControllerLifecycle()

        XCTAssertEqual(
            lifecycle.requestEntry(isPictureInPicturePossible: true),
            .refused(.notPrepared)
        )
        XCTAssertEqual(lifecycle.entryRequestCount, 1)
    }

    func testStoppingWhenNothingIsUpIsNotDeliveredToTheSystem() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()

        XCTAssertFalse(lifecycle.requestStop(), "There is no window to stop.")
        XCTAssertEqual(lifecycle.lastStopReason, .notStopped)
    }

    // MARK: - FR-003: the system's view wins

    func testAStopWithNoAppRequestIsRecordedAsASystemDismissal() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)
        lifecycle.noteStarted()

        // The user closed the floating window from the system chrome.
        lifecycle.noteStopped()

        XCTAssertEqual(lifecycle.lastStopReason, .systemDismissed)
        XCTAssertEqual(lifecycle.systemDismissalCount, 1)
        XCTAssertFalse(lifecycle.isEngaged)
        XCTAssertTrue(
            lifecycle.hasController,
            "The controller outlives the window; only the window went away."
        )
    }

    func testAnAppRequestedStopKeepsItsReason() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)
        lifecycle.noteStarted()

        XCTAssertTrue(lifecycle.requestStop(reason: .userRequested))
        lifecycle.noteStopped()

        XCTAssertEqual(lifecycle.lastStopReason, .userRequested)
        XCTAssertEqual(lifecycle.systemDismissalCount, 0)
    }

    func testReEntryAfterAStopIsAllowedAndDoesNotRebuildTheController() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)
        lifecycle.noteStarted()
        _ = lifecycle.requestStop()
        lifecycle.noteStopped()

        XCTAssertEqual(lifecycle.prepare(), .reuseController)
        XCTAssertEqual(lifecycle.requestEntry(isPictureInPicturePossible: true), .start)
        lifecycle.noteStarted()

        XCTAssertEqual(lifecycle.phase, .active)
        XCTAssertEqual(
            lifecycle.controllerCreationCount,
            1,
            "The founder's second entry must reuse the first entry's controller."
        )
        XCTAssertEqual(lifecycle.startRefusalCount, 0)
    }

    func testAFailedStartLeavesTheControllerUsable() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)

        lifecycle.noteStartFailed()

        XCTAssertEqual(lifecycle.phase, .prepared)
        XCTAssertEqual(lifecycle.startFailureCount, 1)
        XCTAssertEqual(lifecycle.lastStopReason, .startFailed)
        XCTAssertEqual(
            lifecycle.requestEntry(isPictureInPicturePossible: true),
            .start,
            "A refused start must not be a dead end."
        )
    }

    // MARK: - FR-006: what reaches the export

    func testTheDiagnosticReportCarriesCountsAndCatalogLabelsOnly() {
        var lifecycle = PiPWatchControllerLifecycle()
        _ = lifecycle.prepare()
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)
        lifecycle.noteStarted()
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)
        lifecycle.noteStopped()

        let report = DiagnosticPiPWatchReport(lifecycle: lifecycle)

        XCTAssertEqual(report.pipEntryRequestCount, 2)
        XCTAssertEqual(report.pipControllerCreationCount, 1)
        XCTAssertEqual(report.pipStartRefusalCount, 1)
        XCTAssertEqual(report.pipSystemDismissalCount, 1)
        XCTAssertEqual(report.pipLastStopReason, PiPWatchStopReason.systemDismissed.rawValue)
        XCTAssertEqual(report.pipPhase, PiPWatchControllerLifecycle.Phase.prepared.rawValue)
    }

    func testTheReportRejectsLabelsOutsideItsCatalogue() {
        let report = DiagnosticPiPWatchReport(
            pipEntryRequestCount: -4,
            pipControllerCreationCount: 1,
            pipStartRefusalCount: 0,
            pipStartFailureCount: 0,
            pipSystemDismissalCount: 0,
            pipLastStopReason: "1920x1080 window closed",
            pipPhase: "whatever the system said"
        )

        XCTAssertEqual(report.pipEntryRequestCount, 0)
        XCTAssertEqual(report.pipLastStopReason, PiPWatchDiagnosticCatalog.unknown)
        XCTAssertEqual(report.pipPhase, PiPWatchDiagnosticCatalog.unknown)
    }
}
