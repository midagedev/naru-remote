import XCTest
@testable import NaruRemoteCore

/// Spec 034 FR-004 / FR-008. The interesting property of an automatic framing
/// loop is not that it finds the activity — it is that it holds still. A PiP
/// window that re-frames on every terminal line is worse than one that never
/// moves, so the dead zone and the cooldown are asserted as contract.
///
/// Time is passed in, never read, so every case here is exact.
final class PiPAutoFramingPolicyTests: XCTestCase {
    /// The founder's desktop, measured by direct probe in spec 031.
    private let width = 3024
    private let height = 1964

    private func damage(x: Int, y: Int, width w: Int, height h: Int) -> [RFBFrameDamageRect] {
        [RFBFrameDamageRect(x: x, y: y, width: w, height: h)]
    }

    // MARK: - Centring

    func testFramesOnWhereThePixelsAreChanging() throws {
        var state = PiPAutoFramingState()

        let target = state.observe(
            damage: damage(x: 2000, y: 1400, width: 600, height: 320),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 0
        )

        let framing = try XCTUnwrap(target)
        XCTAssertEqual(framing.centerX, 2300.0 / 3024.0, accuracy: 0.001)
        XCTAssertEqual(framing.centerY, 1560.0 / 1964.0, accuracy: 0.001)
        XCTAssertGreaterThan(framing.zoomScale, 1, "A 600-pixel change must not frame the desktop")
        XCTAssertEqual(state.reframeCount, 1)
    }

    func testTheBusiestAreaWinsWhenTwoRegionsChange() throws {
        var state = PiPAutoFramingState()

        // A clock ticking in the corner against a terminal printing: the
        // terminal has two orders of magnitude more changed area.
        _ = state.observe(
            damage: [
                RFBFrameDamageRect(x: 2900, y: 20, width: 100, height: 30),
                RFBFrameDamageRect(x: 300, y: 1200, width: 700, height: 400)
            ],
            framebufferWidth: width,
            framebufferHeight: height,
            now: 0
        )

        let framing = try XCTUnwrap(state.current)
        XCTAssertLessThan(
            framing.centerX,
            0.5,
            "Area weighting must put the terminal, not the clock, in the window"
        )
    }

    // MARK: - The legible band

    func testACaretSizedChangeIsPaddedOutRatherThanFramedExactly() throws {
        let policy = PiPAutoFramingPolicy(minimumCropWidthPixels: 320, maximumCropWidthPixels: 800)
        var state = PiPAutoFramingState(policy: policy)

        let framing = try XCTUnwrap(
            state.observe(
                damage: damage(x: 1500, y: 900, width: 8, height: 18),
                framebufferWidth: width,
                framebufferHeight: height,
                now: 0
            )
        )

        let cropWidth = Double(width) / framing.zoomScale
        XCTAssertGreaterThanOrEqual(cropWidth, 320, "Framing a caret exactly is useless")
        XCTAssertLessThanOrEqual(framing.zoomScale, PiPAutoFramingPolicy.maximumZoomScale)
    }

    func testAWideChangeIsNotZoomedOutBelowLegibility() throws {
        let policy = PiPAutoFramingPolicy(maximumCropWidthPixels: 800)
        var state = PiPAutoFramingState(policy: policy)

        // A full-screen repaint: the whole desktop changed.
        let framing = try XCTUnwrap(
            state.observe(
                damage: damage(x: 0, y: 0, width: width, height: height),
                framebufferWidth: width,
                framebufferHeight: height,
                now: 0
            )
        )

        let cropWidth = Double(width) / framing.zoomScale
        XCTAssertLessThanOrEqual(
            cropWidth,
            800.5,
            "Zooming out to fit an unreadable desktop is the failure this clamp prevents"
        )
        XCTAssertEqual(framing.centerX, 0.5, accuracy: 0.001)
    }

    func testTheCropNeverExceedsTheAppsOwnZoomCeiling() throws {
        var state = PiPAutoFramingState(
            policy: PiPAutoFramingPolicy(minimumCropWidthPixels: 1, maximumCropWidthPixels: 2)
        )

        let framing = try XCTUnwrap(
            state.observe(
                damage: damage(x: 10, y: 10, width: 2, height: 2),
                framebufferWidth: width,
                framebufferHeight: height,
                now: 0
            )
        )

        XCTAssertEqual(
            framing.zoomScale,
            PiPAutoFramingPolicy.maximumZoomScale,
            "Automatic framing must not ask for a crop the manual path cannot produce"
        )
    }

    // MARK: - Holding still

    func testAChangeInsideTheDeadZoneDoesNotMoveTheWindow() {
        var state = PiPAutoFramingState()
        _ = state.observe(
            damage: damage(x: 1400, y: 900, width: 400, height: 200),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 0
        )

        // Well past the cooldown, but the next line printed 30 pixels lower.
        let next = state.observe(
            damage: damage(x: 1400, y: 930, width: 400, height: 200),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 10
        )

        XCTAssertTrue(next == nil, "The window must hold for a change this small")
        XCTAssertEqual(state.suppressedCount, 1)
        XCTAssertEqual(state.reframeCount, 1)
    }

    func testACooldownHoldsEvenWhenTheActivityJumpsAcrossTheScreen() throws {
        var state = PiPAutoFramingState(
            policy: PiPAutoFramingPolicy(recenterCooldownSeconds: 1.5)
        )
        _ = state.observe(
            damage: damage(x: 200, y: 200, width: 400, height: 200),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 0
        )

        let tooSoon = state.observe(
            damage: damage(x: 2600, y: 1700, width: 400, height: 200),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 0.9
        )
        XCTAssertTrue(tooSoon == nil, "Two re-frames inside the cooldown is the jitter case")
        XCTAssertEqual(state.suppressedCount, 1)

        let later = state.observe(
            damage: damage(x: 2600, y: 1700, width: 400, height: 200),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 2.6
        )
        XCTAssertNotNil(later, "Past the cooldown, a real move must be followed")
        XCTAssertEqual(state.reframeCount, 2)
    }

    func testActivityMovingFarEnoughDoesMoveTheWindow() throws {
        var state = PiPAutoFramingState()
        _ = state.observe(
            damage: damage(x: 200, y: 200, width: 300, height: 200),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 0
        )

        // A different window on the Mac, four seconds later.
        let moved = state.observe(
            damage: damage(x: 2400, y: 1500, width: 300, height: 200),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 4
        )

        let framing = try XCTUnwrap(moved)
        XCTAssertGreaterThan(framing.centerX, 0.5)
        XCTAssertGreaterThan(framing.centerY, 0.5)
    }

    func testAnIdleScreenHoldsTheLastFramingInsteadOfDrifting() throws {
        var state = PiPAutoFramingState(policy: PiPAutoFramingPolicy(damageWindowSeconds: 2.5))
        _ = state.observe(
            damage: damage(x: 2000, y: 1400, width: 600, height: 320),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 0
        )
        let framedAt = try XCTUnwrap(state.current)

        // Empty updates for ten seconds — nothing on the remote screen moved.
        for tick in stride(from: 1.0, through: 10.0, by: 1.0) {
            XCTAssertTrue(
                state.observe(
                    damage: [],
                    framebufferWidth: width,
                    framebufferHeight: height,
                    now: tick
                ) == nil,
                "Idle must not produce a re-frame"
            )
        }

        XCTAssertEqual(state.current, framedAt, "Idle holds; it does not zoom back out")
        XCTAssertEqual(state.reframeCount, 1)
    }

    // MARK: - Entry and reset

    func testAdoptingTheEntryFramingMakesTheFirstDecisionRelativeToIt() throws {
        var state = PiPAutoFramingState()
        let entry = PiPFramingTarget(centerX: 0.66, centerY: 0.79, zoomScale: 3.8)
        state.adopt(entry, at: 0)

        // The same place the user was already looking at, just after entry.
        let held = state.observe(
            damage: damage(x: 1900, y: 1450, width: 400, height: 220),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 5
        )

        XCTAssertTrue(held == nil, "Entry framing counts as the framing in force")
        XCTAssertEqual(state.current, entry)
        XCTAssertEqual(state.reframeCount, 0)
    }

    func testResetForgetsEverything() {
        var state = PiPAutoFramingState()
        _ = state.observe(
            damage: damage(x: 100, y: 100, width: 200, height: 200),
            framebufferWidth: width,
            framebufferHeight: height,
            now: 0
        )

        state.reset()

        XCTAssertTrue(state.current == nil)
        XCTAssertEqual(state.reframeCount, 0)
        XCTAssertEqual(state.suppressedCount, 0)
    }

    func testADegenerateFramebufferIsIgnoredRatherThanDividedBy() {
        var state = PiPAutoFramingState()

        XCTAssertTrue(
            state.observe(
                damage: damage(x: 0, y: 0, width: 10, height: 10),
                framebufferWidth: 0,
                framebufferHeight: 0,
                now: 0
            ) == nil
        )
        XCTAssertTrue(state.current == nil)
    }

    // MARK: - The mode itself

    func testTheDefaultModeIsWhatASingleTapDoes() {
        XCTAssertEqual(AppSettings().pipFramingMode, .currentView)
    }

    func testTheModeSurvivesARoundTripAndDefaultsWhenAbsent() throws {
        var settings = AppSettings()
        settings.pipFramingMode = .followActivity

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(decoded.pipFramingMode, .followActivity)

        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.pipFramingMode, .currentView)
    }

    // MARK: - Automatic entry (spec 036 FR-005)

    /// Default on, because an app cannot send itself to the background: the
    /// gesture that backgrounds it is the only place PiP entry can live
    /// without a button that half-works.
    func testLeavingTheAppEntersPiPByDefault() throws {
        XCTAssertTrue(AppSettings().pipEntersOnLeavingApp)
        XCTAssertTrue(
            try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
                .pipEntersOnLeavingApp,
            "An empty settings file is the product default, not off"
        )
    }

    func testAutomaticEntryCanBeTurnedOffAndSurvivesARoundTrip() throws {
        var settings = AppSettings()
        settings.pipEntersOnLeavingApp = false

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertFalse(
            decoded.pipEntersOnLeavingApp,
            "Off has to persist — a PiP window keeps streaming in the background, and that costs cellular data"
        )
    }
}
