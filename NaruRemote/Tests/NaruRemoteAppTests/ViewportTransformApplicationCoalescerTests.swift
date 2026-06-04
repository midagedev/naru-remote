import XCTest
@testable import NaruRemoteApp

final class ViewportTransformApplicationCoalescerTests: XCTestCase {
    func testFirstRequestSchedulesDisplayLink() {
        var coalescer = ViewportTransformApplicationCoalescer()

        XCTAssertTrue(coalescer.requestDisplayLinkedApplication())
        XCTAssertTrue(coalescer.hasPendingApplication)
        XCTAssertTrue(coalescer.hasScheduledDisplayLink)
    }

    func testRepeatedRequestsCoalesceOntoExistingDisplayLink() {
        var coalescer = ViewportTransformApplicationCoalescer()

        XCTAssertTrue(coalescer.requestDisplayLinkedApplication())
        XCTAssertFalse(coalescer.requestDisplayLinkedApplication())
        XCTAssertTrue(coalescer.hasPendingApplication)
        XCTAssertTrue(coalescer.hasScheduledDisplayLink)
    }

    func testFlushAppliesOnceAndClearsState() {
        var coalescer = ViewportTransformApplicationCoalescer()
        _ = coalescer.requestDisplayLinkedApplication()
        _ = coalescer.requestDisplayLinkedApplication()

        XCTAssertTrue(coalescer.flush())
        XCTAssertFalse(coalescer.flush())
        XCTAssertFalse(coalescer.hasPendingApplication)
        XCTAssertFalse(coalescer.hasScheduledDisplayLink)
    }

    func testCancelDropsPendingApplication() {
        var coalescer = ViewportTransformApplicationCoalescer()
        _ = coalescer.requestDisplayLinkedApplication()

        coalescer.cancel()

        XCTAssertFalse(coalescer.flush())
        XCTAssertFalse(coalescer.hasPendingApplication)
        XCTAssertFalse(coalescer.hasScheduledDisplayLink)
    }
}
