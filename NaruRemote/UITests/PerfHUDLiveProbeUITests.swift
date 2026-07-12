import XCTest

/// Live performance probe driven through the real app UI — on the
/// simulator or a physical device — against the dev Mac's Screen
/// Sharing endpoint. It connects, measures an idle window, then drives
/// sustained pointer interaction (the same path that produces "input
/// feels laggy"), and captures the on-screen performance HUD so the
/// per-stage numbers come from the real Metal + main-actor + pacing
/// pipeline rather than a headless Core probe.
///
/// Env (set via TEST_RUNNER_* on xcodebuild, SIMCTL_CHILD_*, or the scheme):
///   NARU_E2E_HOST     (default 127.0.0.1 — use the Mac's LAN IP for devices)
///   NARU_E2E_PORT     (default 5900)
///   NARU_E2E_PASSWORD (required; test skips when unset)
///
/// Profile seeding uses the env-based `NARU_TEST_SEED_PROFILE_*` hook
/// (`UXAuditFixtures.loadSeedProfileSnapshot`) instead of a shared
/// profiles.json — a physical device cannot read a file written into
/// the test runner's sandbox.
///
/// Screenshots are attached to the xcresult bundle (`keepAlways`) and,
/// where the filesystem is shared (simulator), also written to
/// NARU_E2E_OUTPUT_DIR.
@MainActor
final class PerfHUDLiveProbeUITests: XCTestCase {
    private var host: String {
        ProcessInfo.processInfo.environment["NARU_E2E_HOST"] ?? "127.0.0.1"
    }
    private var port: Int {
        Int(ProcessInfo.processInfo.environment["NARU_E2E_PORT"] ?? "5900") ?? 5900
    }
    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_E2E_PASSWORD"]
    }
    private var outputDirectory: String {
        if let override = ProcessInfo.processInfo.environment["NARU_E2E_OUTPUT_DIR"], !override.isEmpty {
            return override
        }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("naru-perf-hud")
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testLivePerfHUDUnderSustainedInteraction() throws {
        guard let password else {
            throw XCTSkip("NARU_E2E_PASSWORD not set — skipping live perf HUD probe")
        }

        let profileID = UUID()
        let credentialRef = "vnc-password:\(profileID.uuidString)"
        let app = launch(seedProfileID: profileID, credentialRef: credentialRef, password: password)

        // Saved-profile launch starts on Connections. A single card tap
        // enters Operation and starts the connection immediately.
        let firstCard = app.buttons["naru.connection.grid.card"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "Saved connection card must be present")
        firstCard.tap()

        let diagnosticCorner = app.buttons["naru.session.diagnostics.corner"]
        XCTAssertTrue(
            diagnosticCorner.waitForExistence(timeout: 8),
            "A card tap must enter Operation and mount its persistent diagnostic control"
        )

        // First launch on a physical device raises the iOS Local
        // Network permission alert the moment the socket touches a
        // private address; the connection cannot proceed until it is
        // allowed, so poll for it while waiting for Connected.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, !isConnected(diagnosticCorner) {
            allowSystemPermissionAlertIfPresent()
            usleep(250_000)
        }
        XCTAssertTrue(
            isConnected(diagnosticCorner),
            "Operation diagnostics must report Connected — check network path/password/local-network permission"
        )
        try saveScreen(app: app, named: "perf-01-active.png")

        // Idle window first: no interaction, so the HUD aggregates show
        // the stream's natural produce rate and idle pacing without the
        // viewport-interaction throttle mixed in.
        sleep(8)
        try saveScreen(app: app, named: "perf-02-idle.png")

        // Drive sustained interaction: swipe/drag across the viewport to
        // generate pointer events (input path) and remote cursor motion
        // (frame path). Capture the HUD periodically so its rolling
        // aggregates reflect interaction, not an idle screen.
        let surface = app.windows.firstMatch
        for round in 0..<6 {
            dragRound(on: surface)
            try saveScreen(app: app, named: String(format: "perf-03-drag%02d.png", round))
        }

        // Tap rounds: discrete taps exercise the outbound pointer-event
        // path (in queue / in op rows) even when drags are treated as
        // local viewport panning.
        for round in 0..<3 {
            tapRound(on: surface)
            try saveScreen(app: app, named: String(format: "perf-04-tap%02d.png", round))
        }

        // Let it settle, then one final HUD capture.
        sleep(2)
        try saveScreen(app: app, named: "perf-05-final.png")
    }

    private func dragRound(on element: XCUIElement) {
        let points: [(CGVector, CGVector)] = [
            (CGVector(dx: 0.25, dy: 0.35), CGVector(dx: 0.75, dy: 0.35)),
            (CGVector(dx: 0.75, dy: 0.45), CGVector(dx: 0.25, dy: 0.65)),
            (CGVector(dx: 0.35, dy: 0.65), CGVector(dx: 0.65, dy: 0.30)),
        ]
        for (from, to) in points {
            let start = element.coordinate(withNormalizedOffset: from)
            let end = element.coordinate(withNormalizedOffset: to)
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func tapRound(on element: XCUIElement) {
        let points: [CGVector] = [
            CGVector(dx: 0.40, dy: 0.40),
            CGVector(dx: 0.60, dy: 0.45),
            CGVector(dx: 0.50, dy: 0.55),
        ]
        for point in points {
            element.coordinate(withNormalizedOffset: point).tap()
            usleep(200_000)
        }
    }

    private func isConnected(_ diagnosticCorner: XCUIElement) -> Bool {
        guard let value = diagnosticCorner.value as? String else { return false }
        return value.lowercased().hasPrefix("connected")
    }

    /// Taps the affirmative button on a system alert (Local Network
    /// permission, notifications, …) if one is covering the app. Exact
    /// label matches only — "허용 안 함"/"Don't Allow" must never match.
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

    // MARK: - Launch / seed helpers

    private func launch(
        seedProfileID: UUID,
        credentialRef: String,
        password: String
    ) -> XCUIApplication {
        let app = XCUIApplication()

        // Env-based seeding works identically on simulator and physical
        // device (no cross-sandbox file access). Skip the disk profile
        // store so a previous install cannot shadow the seeded profile.
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = host
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_PORT"] = String(port)
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_ID"] = seedProfileID.uuidString
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_NAME"] = "Perf Mac"
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_CREDENTIAL_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        app.launchEnvironment["NARU_TEST_OVERRIDE_INTERFACE_STYLE"] = "Dark"
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_PASSWORD"] = password
        app.launchEnvironment["NARU_PERF_HUD"] = "1"
        app.launch()
        return app
    }

    private func saveScreen(app: XCUIApplication, named filename: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = filename
        add(attachment)
        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename)
        try? screenshot.pngRepresentation.write(to: url)
    }
}
