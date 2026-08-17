import XCTest
@testable import NaruRemoteCore

/// Spec 012 US2-1 — clock-injected hold-repeat cadence.
/// Boundary tests do not sleep: `now` is advanced in process.
final class AccessoryKeyRepeatCadenceTests: XCTestCase {
    func testPressEmitsImmediatelyAndSchedulesFirstRepeatAt400ms() {
        var cadence = AccessoryKeyRepeatCadence()
        let t0 = ContinuousClock.now

        let tick = cadence.press(.arrowUp, at: t0)

        XCTAssertEqual(tick.emit, .arrowUp)
        XCTAssertEqual(tick.nextTickAt, t0.advanced(by: .milliseconds(400)))
        XCTAssertTrue(cadence.isActive)
        XCTAssertEqual(cadence.heldKey, .arrowUp)
    }

    func testNoRepeatBefore400msBoundary() {
        var cadence = AccessoryKeyRepeatCadence()
        let t0 = ContinuousClock.now
        _ = cadence.press(.arrowDown, at: t0)

        let early = cadence.tick(at: t0.advanced(by: .milliseconds(399)))
        XCTAssertNil(early.emit, "399 ms must not repeat")
        XCTAssertEqual(early.nextTickAt, t0.advanced(by: .milliseconds(400)))

        let stillEarly = cadence.tick(at: t0)
        XCTAssertNil(stillEarly.emit, "A tick at press-time must not repeat")
        XCTAssertTrue(cadence.isActive)
    }

    func testFirstRepeatFiresAtExactly400msThenEvery45ms() {
        var cadence = AccessoryKeyRepeatCadence()
        let t0 = ContinuousClock.now
        _ = cadence.press(.arrowLeft, at: t0)

        let first = cadence.tick(at: t0.advanced(by: .milliseconds(400)))
        XCTAssertEqual(first.emit, .arrowLeft)
        XCTAssertEqual(first.nextTickAt, t0.advanced(by: .milliseconds(445)))

        let second = cadence.tick(at: t0.advanced(by: .milliseconds(445)))
        XCTAssertEqual(second.emit, .arrowLeft)
        XCTAssertEqual(second.nextTickAt, t0.advanced(by: .milliseconds(490)))
    }

    func testReleaseStopsFurtherEmissions() {
        var cadence = AccessoryKeyRepeatCadence()
        let t0 = ContinuousClock.now
        _ = cadence.press(.delete, at: t0)
        cadence.release()

        let afterRelease = cadence.tick(at: t0.advanced(by: .milliseconds(400)))
        XCTAssertNil(afterRelease.emit, "Release must drop the 400 ms fire")
        XCTAssertNil(afterRelease.nextTickAt)
        XCTAssertFalse(cadence.isActive)

        let later = cadence.tick(at: t0.advanced(by: .milliseconds(800)))
        XCTAssertNil(later.emit, "A later tick after release must stay idle")
        XCTAssertEqual(later, .idle)
    }

    func testStopMatchesReleaseAndNonRepeatableKeysDoNotSchedule() {
        var cadence = AccessoryKeyRepeatCadence()
        let t0 = ContinuousClock.now
        _ = cadence.press(.arrowRight, at: t0)
        cadence.stop()
        XCTAssertFalse(cadence.isActive)
        XCTAssertNil(cadence.tick(at: t0.advanced(by: .milliseconds(400))).emit)

        let oneShot = cadence.press(.escape, at: t0)
        XCTAssertEqual(oneShot.emit, .escape)
        XCTAssertNil(oneShot.nextTickAt, "Esc must not auto-repeat")
        XCTAssertFalse(cadence.isActive)
    }
}
