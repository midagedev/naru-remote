import XCTest

/// The gate the founder asked for on 2026-08-21: *the lead verifies the
/// symptom, not the human*. It drives the real app in the simulator against
/// the dev Mac's Screen Sharing endpoint, performs the interaction that
/// killed build 4 (zoom in — which is what turns spec 017 region scoping on —
/// then pan, then open the input dock so the visible area shrinks again), and
/// asserts that the stream's content-frame counter keeps advancing.
///
/// Before the spec 022 fix this is exactly the sequence that deadlocked the
/// pipelined request pump: every parked incremental request still described
/// the region the user had left, so the server held all of them forever.
///
/// Env (same contract as `PerfHUDLiveProbeUITests`):
///   NARU_E2E_HOST     (default 127.0.0.1)
///   NARU_E2E_PORT     (default 5900)
///   NARU_E2E_PASSWORD (required; test skips when unset)
@MainActor
final class StreamLivenessUnderInteractionUITests: XCTestCase {
    private var host: String {
        ProcessInfo.processInfo.environment["NARU_E2E_HOST"] ?? "127.0.0.1"
    }
    private var port: Int {
        Int(ProcessInfo.processInfo.environment["NARU_E2E_PORT"] ?? "5900") ?? 5900
    }
    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_E2E_PASSWORD"]
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testStreamKeepsDeliveringFramesWhileZoomingPanningAndOpeningTheDock() throws {
        guard let password else {
            throw XCTSkip("NARU_E2E_PASSWORD not set — skipping live stream-liveness gate")
        }

        let profileID = UUID()
        let credentialRef = "vnc-password:\(profileID.uuidString)"
        let app = launch(seedProfileID: profileID, credentialRef: credentialRef, password: password)

        let firstCard = app.buttons["naru.connection.grid.card"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "Saved connection card must be present")
        firstCard.tap()

        let diagnosticCorner = app.buttons["naru.session.diagnostics.corner"]
        XCTAssertTrue(
            diagnosticCorner.waitForExistence(timeout: 10),
            "A card tap must enter Operation"
        )

        let connectDeadline = Date().addingTimeInterval(30)
        while Date() < connectDeadline, !isConnected(diagnosticCorner) {
            allowSystemPermissionAlertIfPresent()
            usleep(250_000)
        }
        XCTAssertTrue(
            isConnected(diagnosticCorner),
            "Operation diagnostics must report Connected"
        )

        // Spec 028. The liveness property is asserted on the *presented* counter
        // — frames whose pixels reached the texture — not on the pump's content
        // frame count.
        //
        // Until 2026-08-25 this gate asserted `contentFrameCount`, which the
        // frame pump increments when it decodes a frame and which says nothing
        // about whether anything reached the screen. That is a proxy wait: PASS
        // meant "the pump ran". The founder's TestFlight build 7 report — the
        // picture frozen while frames kept arriving — is exactly the state that
        // assertion cannot distinguish from a healthy session, which is how the
        // same freeze class survived spec 022 and shipped again.
        let pumpCounter = app.descendants(matching: .any)["naru.session.perf.contentFrameCount"]
        XCTAssertTrue(
            pumpCounter.waitForExistence(timeout: 10),
            "The perf HUD frame counter must be present (NARU_PERF_HUD=1)"
        )
        // Precondition only. The pump being alive is what makes a frozen screen
        // a defect rather than a quiet remote.
        XCTAssertTrue(
            waitForFrameProgress(pumpCounter, from: currentFrameCount(pumpCounter), timeout: 20),
            "The pump delivered no frames at all — this run cannot judge presentation"
        )

        let counter = app.descendants(matching: .any)["naru.session.perf.presentedFrameCount"]
        XCTAssertTrue(
            counter.waitForExistence(timeout: 10),
            "The perf HUD presentation counter must be present (spec 028)"
        )
        XCTAssertTrue(
            waitForFrameProgress(counter, from: currentFrameCount(counter), timeout: 20),
            "Frames are arriving but none of them are reaching the screen"
                + heldReasonSuffix(app)
        )

        var stalls: [String] = []
        var inconclusive: [String] = []
        let surface = app.windows.firstMatch

        // 1. Zoom in. This is the state that makes the pump request a
        //    viewport-scoped region instead of the full framebuffer.
        surface.pinch(withScale: 2.4, velocity: 1.6)
        let zoomProgress = waitForPresentationToFollowThePump(
            presented: counter,
            pump: pumpCounter,
            timeout: 25
        )
        if zoomProgress == .stalled { stalls.append("zoom") }
        if zoomProgress == .inconclusive { inconclusive.append("zoom") }
        XCTAssertNotEqual(
            zoomProgress,
            .stalled,
            "Frames arrived after zooming in but none of them reached the screen"
                + heldReasonSuffix(app)
        )

        // 2. Pan. The viewport region moves, so every request parked for the
        //    previous region can no longer be satisfied.
        for _ in 0..<3 {
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.62))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.34))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let panProgress = waitForPresentationToFollowThePump(
            presented: counter,
            pump: pumpCounter,
            timeout: 25
        )
        if panProgress == .stalled { stalls.append("pan") }
        if panProgress == .inconclusive { inconclusive.append("pan") }
        XCTAssertNotEqual(
            panProgress,
            .stalled,
            "Frames arrived after panning but none of them reached the screen"
                + heldReasonSuffix(app)
        )

        // 3. Open the input dock: the visible area shrinks, which changes the
        //    requested region again while zoomed.
        let dockToggle = app.buttons["naru.input.type-reveal"].firstMatch
        if dockToggle.waitForExistence(timeout: 3) {
            dockToggle.tap()
        let dockProgress = waitForPresentationToFollowThePump(
                presented: counter,
                pump: pumpCounter,
                timeout: 25
            )
            if dockProgress == .stalled { stalls.append("dock") }
            if dockProgress == .inconclusive { inconclusive.append("dock") }
            XCTAssertNotEqual(
                dockProgress,
                .stalled,
                "Frames arrived after the dock opened but none of them reached the screen"
                    + heldReasonSuffix(app)
            )
        }

        // Spec 028 FR-007: a run that presented frames throughout but released a
        // stuck latch to do it is not a pass. The watchdog is a recovery, not a
        // reason to stop reporting the defect it recovered from.
        let watchdog = app.descendants(matching: .any)["naru.session.perf.presentationWatchdogCount"]
        XCTAssertFalse(
            watchdog.exists,
            "A presentation latch had to release itself during this run"
        )

        print(
            "Stream liveness gate: presentedAtEnd=\(currentFrameCount(counter)) "
                + "pumpAtEnd=\(currentFrameCount(pumpCounter)) "
                + "stalledAt=\(stalls.isEmpty ? "none" : stalls.joined(separator: "+")) "
                + "quietAt=\(inconclusive.isEmpty ? "none" : inconclusive.joined(separator: "+")) "
                + "verdict=\(stalls.isEmpty ? "kept-presenting" : "presentation-died")"
        )
    }

    // MARK: - Helpers

    /// Spec 028. Names what is withholding frames, so a red gate arrives already
    /// attributed instead of starting an investigation. Fixed labels only.
    private func heldReasonSuffix(_ app: XCUIApplication) -> String {
        let reason = app.descendants(matching: .any)["naru.session.perf.presentationHeldReason"]
        guard reason.exists, let value = reason.value as? String, !value.isEmpty else {
            return ""
        }
        return " — held by: \(value)"
    }

    private func currentFrameCount(_ element: XCUIElement) -> Int {
        Int((element.value as? String) ?? "") ?? 0
    }

    /// Frames are only produced when the remote screen changes, so a quiet
    /// Mac can legitimately hold. Poll until the counter moves, which is the
    /// liveness property; a dead stream never moves it again.
    private func waitForFrameProgress(
        _ element: XCUIElement,
        from baseline: Int,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if currentFrameCount(element) > baseline {
                return true
            }
            usleep(300_000)
        }
        return false
    }

    /// Spec 028. The presentation property has to be **relative** to the pump.
    ///
    /// Asserting that the presented counter advances within a fixed window is
    /// wrong on its own: the remote screen may simply not have changed, and then
    /// there is nothing to present and the gate reddens on a healthy session.
    /// The defect is presentation falling behind frames that actually arrived,
    /// so this waits for the pump to move and only fails when it moved and
    /// presentation did not follow.
    ///
    /// Returns `.inconclusive` when the remote stayed quiet for the whole
    /// window — which is reported, never silently passed.
    private enum PresentationProgress {
        case kept
        case stalled
        case inconclusive
    }

    private func waitForPresentationToFollowThePump(
        presented: XCUIElement,
        pump: XCUIElement,
        timeout: TimeInterval
    ) -> PresentationProgress {
        let presentedBaseline = currentFrameCount(presented)
        let pumpBaseline = currentFrameCount(pump)
        let deadline = Date().addingTimeInterval(timeout)
        var pumpAdvanced = false

        while Date() < deadline {
            if currentFrameCount(presented) > presentedBaseline {
                return .kept
            }
            if currentFrameCount(pump) > pumpBaseline + 2 {
                pumpAdvanced = true
            }
            usleep(300_000)
        }
        return pumpAdvanced ? .stalled : .inconclusive
    }

    private func isConnected(_ diagnosticCorner: XCUIElement) -> Bool {
        guard let value = diagnosticCorner.value as? String else { return false }
        return value.lowercased().hasPrefix("connected")
    }

    private func allowSystemPermissionAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.exists else { return }
        for label in ["Allow", "허용", "OK", "확인"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
    }

    private func launch(
        seedProfileID: UUID,
        credentialRef: String,
        password: String
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = host
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_PORT"] = String(port)
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_ID"] = seedProfileID.uuidString
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_NAME"] = "Liveness Mac"
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_CREDENTIAL_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_PASSWORD"] = password
        app.launchEnvironment["NARU_PERF_HUD"] = "1"
        app.launch()
        return app
    }
}
