import XCTest
@testable import NaruRemoteCore

final class FramePresentationLedgerTests: XCTestCase {
    func testEveryOutcomeIsClassifiedAsTerminalOrHeld() {
        // The conservation law is written over terminal outcomes, so a new case
        // that nobody classified would silently unbalance the books. This is
        // the test that fails when someone adds one.
        let terminal = FramePresentationOutcome.allCases.filter(\.isTerminal)
        let held = FramePresentationOutcome.allCases.filter { !$0.isTerminal }
        XCTAssertEqual(
            terminal.count + held.count,
            FramePresentationOutcome.allCases.count
        )
        XCTAssertTrue(terminal.contains(.presented))
        XCTAssertFalse(held.contains(.presented))
    }

    func testABalancedSessionAccountsForEveryPublishedFrame() {
        var ledger = FramePresentationLedger()
        for _ in 0..<5 {
            ledger.recordPublished()
        }
        ledger.record(.presented)
        ledger.record(.presented)
        ledger.record(.duplicateSuppressed)
        ledger.record(.superseded)
        ledger.record(.abandonedOnSizeMismatch)

        XCTAssertEqual(ledger.publishedCount, 5)
        XCTAssertEqual(ledger.terminalCount, 5)
        XCTAssertEqual(ledger.framesInFlightCount, 0)
        XCTAssertTrue(ledger.isBalanced)
    }

    func testHeldFramesAreGaugesAndDoNotCloseTheBooks() {
        // A held frame is still alive — it is waiting for a gesture to settle or
        // a latch to lift. Counting a hold as a loss would make the books
        // disagree with reality on every pinch; not counting it at all is what
        // let a stuck latch look like silence.
        var ledger = FramePresentationLedger()
        ledger.recordPublished()
        ledger.record(.heldBySuspension)
        ledger.record(.heldBySuspension)
        ledger.record(.heldByThrottle)

        XCTAssertEqual(ledger.terminalCount, 0)
        XCTAssertEqual(ledger.framesInFlightCount, 1)
        XCTAssertTrue(ledger.isBalanced)

        ledger.record(.presented)
        XCTAssertEqual(ledger.framesInFlightCount, 0)
    }

    func testAStalledPresentationIsDetectedWhileFramesKeepArriving() {
        // This is the exact shape of the founder's build 7 report, and the exact
        // shape the existing liveness gate cannot see: frames keep being
        // published while nothing reaches the screen.
        var ledger = FramePresentationLedger()
        for _ in 0..<40 {
            ledger.recordPublished()
            ledger.record(.heldBySuspension)
        }

        XCTAssertTrue(ledger.isPresentationStalled(minimumPublished: 10))
        XCTAssertEqual(ledger.dominantWithholdingReason, .heldBySuspension)
    }

    func testAHealthyStreamIsNotReportedAsStalled() {
        var ledger = FramePresentationLedger()
        for _ in 0..<40 {
            ledger.recordPublished()
            ledger.record(.presented)
        }

        XCTAssertFalse(ledger.isPresentationStalled(minimumPublished: 10))
        XCTAssertNil(ledger.dominantWithholdingReason)
    }

    func testTheDominantReasonNamesTheBiggestWithholder() {
        var ledger = FramePresentationLedger()
        for _ in 0..<10 {
            ledger.recordPublished()
        }
        ledger.record(.heldByThrottle)
        for _ in 0..<7 {
            ledger.record(.heldByGesture)
        }

        XCTAssertEqual(ledger.dominantWithholdingReason, .heldByGesture)
    }

    func testWatchdogReleasesAreCountedSeparatelyFromDrops() {
        var ledger = FramePresentationLedger()
        ledger.recordPublished()
        ledger.record(.presented)
        ledger.recordWatchdogRelease()

        XCTAssertEqual(ledger.watchdogReleaseCount, 1)
        XCTAssertEqual(ledger.terminalCount, 1)
        XCTAssertTrue(
            ledger.isBalanced,
            "A self-released latch is an alarm, not a frame outcome — it must not move the books."
        )
    }

    func testTheLedgerSurvivesTheReportRoundTrip() throws {
        // Spec 027 shipped fields that were read back with a default and never
        // written. The same mistake here would make an archived diagnostic
        // export show a clean ledger for a frozen session.
        var ledger = FramePresentationLedger()
        ledger.recordPublished()
        ledger.record(.heldBySuspension)
        ledger.recordWatchdogRelease()

        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(FramePresentationLedger.self, from: data)

        XCTAssertEqual(decoded, ledger)
        XCTAssertEqual(decoded.count(.heldBySuspension), 1)
        XCTAssertEqual(decoded.watchdogReleaseCount, 1)
    }
}
