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

        let counter = app.descendants(matching: .any)["naru.session.perf.contentFrameCount"]
        XCTAssertTrue(
            counter.waitForExistence(timeout: 10),
            "The perf HUD frame counter must be present (NARU_PERF_HUD=1)"
        )
        XCTAssertTrue(
            waitForFrameProgress(counter, from: currentFrameCount(counter), timeout: 20),
            "The stream delivered no frames even before any interaction"
        )

        var stalls: [String] = []
        let surface = app.windows.firstMatch

        // 1. Zoom in. This is the state that makes the pump request a
        //    viewport-scoped region instead of the full framebuffer.
        surface.pinch(withScale: 2.4, velocity: 1.6)
        let afterZoom = currentFrameCount(counter)
        let zoomProgressed = waitForFrameProgress(counter, from: afterZoom, timeout: 20)
        if !zoomProgressed { stalls.append("zoom") }
        XCTAssertTrue(
            zoomProgressed,
            "Frames stopped after zooming in — region-scoped requests are starving the stream"
        )

        // 2. Pan. The viewport region moves, so every request parked for the
        //    previous region can no longer be satisfied.
        for _ in 0..<3 {
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.62))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.34))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let afterPan = currentFrameCount(counter)
        let panProgressed = waitForFrameProgress(counter, from: afterPan, timeout: 20)
        if !panProgressed { stalls.append("pan") }
        XCTAssertTrue(
            panProgressed,
            "Frames stopped after panning — the pump stayed parked on the region the user left"
        )

        // 3. Open the input dock: the visible area shrinks, which changes the
        //    requested region again while zoomed.
        let dockToggle = app.buttons["naru.input.type-reveal"].firstMatch
        if dockToggle.waitForExistence(timeout: 3) {
            dockToggle.tap()
            let afterDock = currentFrameCount(counter)
            let dockProgressed = waitForFrameProgress(counter, from: afterDock, timeout: 20)
            if !dockProgressed { stalls.append("dock") }
            XCTAssertTrue(
                dockProgressed,
                "Frames stopped after the dock opened and shrank the visible region"
            )
        }

        print(
            "Stream liveness gate: framesAtEnd=\(currentFrameCount(counter)) "
                + "stalledAt=\(stalls.isEmpty ? "none" : stalls.joined(separator: "+")) "
                + "verdict=\(stalls.isEmpty ? "kept-streaming" : "stream-died")"
        )
    }

    // MARK: - Helpers

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
