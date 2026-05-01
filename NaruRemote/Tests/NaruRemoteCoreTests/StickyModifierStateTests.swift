import XCTest
@testable import NaruRemoteCore

/// Phase 4 (US-2) — `StickyModifierState` is the small state machine
/// that drives the on-screen modifier UX (idle → armed → locked) and
/// is the single source of truth for both the visual state of each
/// modifier key and the `Set<Modifier>` the `KeystrokeEmitter` wraps
/// around a key.
///
/// All time-sensitive transitions are exercised through an injected
/// `ContinuousClock.Instant` — never `Task.sleep` — so the tests are
/// deterministic and run in milliseconds.
final class StickyModifierStateTests: XCTestCase {

    // MARK: - Initial state

    func testFreshStateAllSlotsIdle() {
        let state = StickyModifierState()
        for m in StickyModifierState.Modifier.allCases {
            XCTAssertEqual(state.slot(for: m), .idle, "\(m) should start idle")
        }
        XCTAssertTrue(state.activeModifiers.isEmpty)
    }

    // MARK: - Single-tap arming

    func testSingleTapArmsModifier() {
        var state = StickyModifierState()
        let now = ContinuousClock.now

        state.tap(.control, at: now)

        XCTAssertEqual(state.slot(for: .control), .armed)
        XCTAssertEqual(state.slot(for: .shift), .idle)
        XCTAssertEqual(state.slot(for: .alt), .idle)
        XCTAssertEqual(state.slot(for: .meta), .idle)
        XCTAssertEqual(state.activeModifiers, [.control])
    }

    func testEachSlotTransitionsIndependently() {
        var state = StickyModifierState()
        let now = ContinuousClock.now

        state.tap(.shift, at: now)
        state.tap(.alt, at: now)

        XCTAssertEqual(state.slot(for: .control), .idle)
        XCTAssertEqual(state.slot(for: .shift), .armed)
        XCTAssertEqual(state.slot(for: .alt), .armed)
        XCTAssertEqual(state.slot(for: .meta), .idle)
        XCTAssertEqual(state.activeModifiers, [.shift, .alt])
    }

    // MARK: - Double-tap locking (within 400 ms)

    func testDoubleTapWithin400MillisLocks() {
        var state = StickyModifierState()
        let t0 = ContinuousClock.now

        state.tap(.shift, at: t0)
        XCTAssertEqual(state.slot(for: .shift), .armed)

        // 200 ms later — still inside the 400 ms double-tap window.
        let t1 = t0.advanced(by: .milliseconds(200))
        state.tap(.shift, at: t1)

        XCTAssertEqual(state.slot(for: .shift), .locked)
        XCTAssertEqual(state.activeModifiers, [.shift])
    }

    func testDoubleTapAtExactly400MillisLocks() {
        // Boundary: ≤ 400 ms is "lock". 400 ms exactly is locking.
        var state = StickyModifierState()
        let t0 = ContinuousClock.now

        state.tap(.control, at: t0)
        let t1 = t0.advanced(by: .milliseconds(400))
        state.tap(.control, at: t1)

        XCTAssertEqual(state.slot(for: .control), .locked)
    }

    // MARK: - Re-tap outside the window stays armed (fresh single-tap)

    func testReTapAfter401MillisStaysArmedAndUpdatesTimestamp() {
        var state = StickyModifierState()
        let t0 = ContinuousClock.now

        state.tap(.alt, at: t0)
        XCTAssertEqual(state.slot(for: .alt), .armed)

        // 401 ms later — outside the window.  Fresh single-tap
        // semantics: still armed (re-arm), but the timestamp
        // updates so the NEXT tap can lock if it comes within
        // 400 ms of *this* tap.
        let t1 = t0.advanced(by: .milliseconds(401))
        state.tap(.alt, at: t1)
        XCTAssertEqual(state.slot(for: .alt), .armed,
                       "re-tap > 400 ms after the prior tap should re-arm, not lock")

        // A third tap within 400 ms of t1 should now lock.
        let t2 = t1.advanced(by: .milliseconds(200))
        state.tap(.alt, at: t2)
        XCTAssertEqual(state.slot(for: .alt), .locked,
                       "third tap within 400 ms of the second tap must lock")
    }

    // MARK: - Locked → idle on tap

    func testTapLockedModifierReturnsToIdle() {
        var state = StickyModifierState()
        let t0 = ContinuousClock.now

        state.tap(.meta, at: t0)
        state.tap(.meta, at: t0.advanced(by: .milliseconds(100)))
        XCTAssertEqual(state.slot(for: .meta), .locked)

        // Tap the locked modifier any time afterwards → idle.
        state.tap(.meta, at: t0.advanced(by: .seconds(5)))
        XCTAssertEqual(state.slot(for: .meta), .idle)
        XCTAssertTrue(state.activeModifiers.isEmpty)
    }

    // MARK: - consumeAfterNonModifierEmission

    func testConsumeReleasesArmedSlotsOnly() {
        var state = StickyModifierState()
        let t0 = ContinuousClock.now

        // Control: armed (single tap)
        state.tap(.control, at: t0)
        // Shift: locked (double tap)
        state.tap(.shift, at: t0)
        state.tap(.shift, at: t0.advanced(by: .milliseconds(50)))
        // Alt: idle (untouched)

        XCTAssertEqual(state.slot(for: .control), .armed)
        XCTAssertEqual(state.slot(for: .shift), .locked)
        XCTAssertEqual(state.slot(for: .alt), .idle)
        XCTAssertEqual(state.activeModifiers, [.control, .shift])

        state.consumeAfterNonModifierEmission()

        XCTAssertEqual(state.slot(for: .control), .idle,
                       "armed control should release after a non-modifier emission")
        XCTAssertEqual(state.slot(for: .shift), .locked,
                       "locked shift must NOT release on emission")
        XCTAssertEqual(state.slot(for: .alt), .idle)
        XCTAssertEqual(state.activeModifiers, [.shift])
    }

    func testConsumeIsNoOpWhenAllSlotsIdle() {
        var state = StickyModifierState()
        state.consumeAfterNonModifierEmission()
        XCTAssertTrue(state.activeModifiers.isEmpty)
    }

    func testLockedModifierAppliesToManySequentialEmissions() {
        // The "double-tap Shift, type three letters all held"
        // scenario from spec.md US-2 acceptance #4.
        var state = StickyModifierState()
        let t0 = ContinuousClock.now

        state.tap(.shift, at: t0)
        state.tap(.shift, at: t0.advanced(by: .milliseconds(50)))
        XCTAssertEqual(state.slot(for: .shift), .locked)

        for _ in 0..<3 {
            XCTAssertEqual(state.activeModifiers, [.shift])
            state.consumeAfterNonModifierEmission()
            XCTAssertEqual(state.slot(for: .shift), .locked)
        }

        // Tapping shift again releases the lock.
        state.tap(.shift, at: t0.advanced(by: .seconds(10)))
        XCTAssertEqual(state.slot(for: .shift), .idle)

        state.consumeAfterNonModifierEmission()
        XCTAssertTrue(state.activeModifiers.isEmpty)
    }

    // MARK: - clear()

    func testClearResetsAllSlotsToIdle() {
        var state = StickyModifierState()
        let t0 = ContinuousClock.now

        state.tap(.control, at: t0)
        state.tap(.shift, at: t0)
        state.tap(.shift, at: t0.advanced(by: .milliseconds(50)))
        state.tap(.alt, at: t0)

        XCTAssertEqual(state.slot(for: .control), .armed)
        XCTAssertEqual(state.slot(for: .shift), .locked)
        XCTAssertEqual(state.slot(for: .alt), .armed)

        state.clear()

        for m in StickyModifierState.Modifier.allCases {
            XCTAssertEqual(state.slot(for: m), .idle, "\(m) should be idle after clear()")
        }
        XCTAssertTrue(state.activeModifiers.isEmpty)
    }

    // MARK: - Stacking modifiers (Ctrl + Shift)

    func testStackedArmedModifiersBothApplyAndBothReleaseOnEmission() {
        // spec.md US-2 acceptance #3 — Ctrl-Shift-Tab is reachable
        // by tapping Ctrl then Shift then a non-modifier key.
        var state = StickyModifierState()
        let t0 = ContinuousClock.now

        state.tap(.control, at: t0)
        state.tap(.shift, at: t0.advanced(by: .milliseconds(10)))
        XCTAssertEqual(state.activeModifiers, [.control, .shift])

        state.consumeAfterNonModifierEmission()
        XCTAssertEqual(state.activeModifiers, [])
    }
}
