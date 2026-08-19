import XCTest

@MainActor
final class NaruRemoteLaunchUITests: XCTestCase {
    func testAppShellLaunchesOnIPadSimulator() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = launchAppWithEmptyProfileStore()

        XCTAssertTrue(app.staticTexts["Add a computer to begin."].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.staticTexts[
                "Connect to a Mac or Linux machine on your private network. "
                + "Compose text on your phone — Naru sends the finished input across."
            ].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["naru.home.empty.addProfile"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Remote Input Dock"].exists)
        XCTAssertFalse(app.staticTexts["Diagnostics"].exists)
    }

    func testRemoteInputDockMovesAboveKeyboardWhileComposing() throws {
        let app = launchAppWithProfileStore(
            seedProfiles: [
                SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
            ],
            // The Remote Input Dock is now a session-only surface; this
            // focused dock test composes without a live socket, so opt the
            // dock in explicitly (see NaruRemoteAppShell.showsInputDock).
            launchEnvironment: ["NARU_TEST_FORCE_INPUT_DOCK": "1"]
        )

        openFirstConnectionCardIfPresent(app: app)
        rotate(app, to: .landscapeLeft)

        let editor = app.textViews["Remote input text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()

        let keyboard = app.keyboards.firstMatch
        guard waitForKeyboardOnScreen(keyboard, in: app, timeout: 6) else {
            // A simulator with "Connect Hardware Keyboard" on never raises the
            // software keyboard, and this assertion is about where the dock
            // sits relative to it. That is an environment fact, not a product
            // failure — say so instead of reporting a layout defect.
            throw XCTSkip("No software keyboard on this simulator (hardware keyboard connected)")
        }

        // The dock is taller than its editor: the send / backspace / return row
        // lives below the text view, so measuring editor-to-keyboard measures
        // that row and calls it a gap. What the dock promises is that its
        // *last* row rides just above the keyboard.
        let send = app.buttons["naru.input.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 4))

        XCTAssertLessThanOrEqual(
            send.frame.maxY,
            keyboard.frame.minY + 1,
            "The keyboard is covering the dock's action row"
        )
        // Measured 56 pt on iPhone 17 Pro Max in landscape: the dock's own
        // bottom padding plus the home-indicator safe area. The bar is set just
        // above that so a real regression — the dock drifting up the screen —
        // still trips it.
        XCTAssertLessThan(
            keyboard.frame.minY - send.frame.maxY,
            72,
            "The dock should ride on the keyboard, not float above it"
        )
        XCTAssertLessThanOrEqual(
            editor.frame.maxY,
            send.frame.minY + 1,
            "The editor must stay above the action row it is composed with"
        )
    }

    func testAddProfileOpensProfileEditor() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = launchAppWithEmptyProfileStore()

        let addProfile = app.buttons["naru.home.empty.addProfile"]
        XCTAssertTrue(addProfile.waitForExistence(timeout: 8))
        addProfile.tap()

        XCTAssertTrue(app.navigationBars["Add Profile"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["Profile name"].waitForExistence(timeout: 2))
        let hostField = app.textFields["MagicDNS or private host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 2))

        hostField.tap()
        app.typeText("studio.tailnet.ts.net")
        XCTAssertEqual(hostField.value as? String, "studio.tailnet.ts.net")
    }

    func testStartupGlanceScaleOverrideIsScopedToLowTrafficProfiles() throws {
        // The control lives inside the session tools menu's "Advanced"
        // submenu, so it can only be seen by opening both — this test used to
        // look for a bare button with a stale identifier
        // (`naru.session.startupGlanceScaleMode`, no `.tools`) and could never
        // have found it on either profile.
        let standardApp = launchAppWithProfileStore(
            seedProfiles: [
                SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
            ],
            launchEnvironment: [
                "NARU_TEST_FIXTURE_SNAPSHOT": "session-active-widescreen",
                "NARU_TEST_SKIP_SETTINGS_STORE_LOAD": "1"
            ]
        )
        XCTAssertFalse(
            try openAdvancedSessionTools(in: standardApp)
                .buttons["naru.session.tools.startupGlanceScaleMode"].exists,
            "A standard stream profile must not expose the startup glance scale control"
        )
        standardApp.terminate()

        let lowTrafficApp = launchAppWithProfileStore(
            seedProfiles: [
                SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
            ],
            launchEnvironment: [
                "NARU_TEST_FIXTURE_SNAPSHOT": "session-active-widescreen",
                "NARU_TEST_SKIP_SETTINGS_STORE_LOAD": "1",
                "NARU_TEST_STREAM_ENCODING_MODE": "local-low-latency-rgb565",
                "NARU_TEST_STARTUP_GLANCE_SCALE_MODE": "glance-025"
            ]
        )
        let glance = try openAdvancedSessionTools(in: lowTrafficApp)
            .buttons["naru.session.tools.startupGlanceScaleMode"]
        XCTAssertTrue(
            glance.waitForExistence(timeout: 4),
            "Low-traffic RGB565 physical candidates must expose the injected glance scale"
        )
        XCTAssertTrue(
            glance.label.localizedCaseInsensitiveContains("0.25"),
            "The control must report the injected scale, not the default"
        )
    }

    /// Opens the session tools menu and its Advanced submenu, returning the app
    /// so the caller can query the items inside.
    ///
    /// The immersive control bar auto-hides after 2.4 s, so the menu has to be
    /// revealed first — a test that just looks for it races the animation and
    /// reports a missing feature.
    @discardableResult
    private func openAdvancedSessionTools(in app: XCUIApplication) throws -> XCUIApplication {
        let reveal = app.buttons["naru.session.controls.reveal"].firstMatch
        if reveal.waitForExistence(timeout: 6), reveal.isHittable {
            reveal.tap()
        }

        let toolsMenu = app.buttons["naru.session.tools.menu"].firstMatch
        guard toolsMenu.waitForExistence(timeout: 6) else {
            throw XCTSkip("No session tools menu — the fixture did not reach a live session")
        }
        toolsMenu.tap()

        let advanced = app.buttons["naru.session.tools.advanced"].firstMatch
        XCTAssertTrue(
            advanced.waitForExistence(timeout: 4),
            "The Advanced submenu is where the stream tuning controls live"
        )
        advanced.tap()
        return app
    }

    func testLaunchEnvironmentSeedProfileCanEnableHelperVideo() {
        XCUIDevice.shared.orientation = .portrait

        let helperVideoSecretRef = "helper-video-token:\(UUID().uuidString)"
        let app = launchAppWithProfileStore(
            launchEnvironment: [
                "NARU_TEST_SKIP_PROFILE_STORE_LOAD": "1",
                "NARU_TEST_SEED_PROFILE_NAME": "Physical E2E Mac",
                "NARU_TEST_SEED_PROFILE_HOST": "studio.tailnet.ts.net",
                "NARU_TEST_SEED_PROFILE_HOST_KIND": "magicDNS",
                "NARU_TEST_SEED_HELPER_VIDEO_ENABLED": "1",
                "NARU_TEST_SEED_HELPER_VIDEO_SECRET_REF": helperVideoSecretRef,
                "NARU_TEST_SEED_HELPER_VIDEO_PAIRING_FINGERPRINT": "sha256:physical-e2e-helper-video",
                "NARU_TEST_INJECT_HELPER_VIDEO_KEYCHAIN_REF": helperVideoSecretRef,
                "NARU_TEST_INJECT_HELPER_VIDEO_KEYCHAIN_PASSWORD": "redacted-helper-video-token"
            ]
        )

        XCTAssertTrue(app.staticTexts["Connections"].waitForExistence(timeout: 8))
        let card = app.buttons["naru.connection.grid.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 4))
        XCTAssertTrue(
            card.label.localizedCaseInsensitiveContains("helper video"),
            "Seeded physical E2E profiles with helper-video pairing must not launch as VNC-only cards"
        )
    }

    /// Rotate *after* launch and wait for the window to actually turn.
    /// Setting `XCUIDevice.orientation` before `app.launch()` is a no-op — the
    /// app comes up portrait, and a test that assumes otherwise silently
    /// measures the wrong layout (which this suite did until 2026-08-19).
    private func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let wantsLandscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let frame = app.windows.firstMatch.frame
            if (frame.width > frame.height) == wantsLandscape {
                return
            }
            usleep(100_000)
        }
    }

    /// `exists` outlives visibility: once the keyboard goes down iOS keeps a
    /// zero-height element parked below the window, so `waitForExistence`
    /// answers yes for a keyboard nobody can see. Ask geometry.
    private func waitForKeyboardOnScreen(
        _ keyboard: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let window = app.windows.firstMatch.frame
            let frame = keyboard.frame
            if frame.height > 1, frame.intersects(window) {
                return true
            }
            usleep(100_000)
        }
        return false
    }

    private func launchAppWithEmptyProfileStore() -> XCUIApplication {
        launchAppWithProfileStore()
    }

    private func launchAppWithProfileStore(
        seedProfiles: [SeedProfile] = [],
        launchEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        for (key, value) in launchEnvironment {
            app.launchEnvironment[key] = value
        }
        if !seedProfiles.isEmpty {
            try? writeSeedProfiles(seedProfiles, to: storeURL)
        }
        app.launch()
        return app
    }

    /// Taps the first host card when there is one, and does nothing when there
    /// is not — which is what the name has always promised.
    ///
    /// It used to decide by looking for the text "Connections", and that is
    /// also the label of the immersive control bar's Connections *button*. So
    /// on a surface that starts in a session (`NARU_TEST_START_PROFILE_DETAIL`)
    /// the guard passed, no grid card existed, and the helper failed the test
    /// with "Failed to tap naru.connection.grid.card". Ask for the card.
    private func openFirstConnectionCardIfPresent(app: XCUIApplication) {
        let firstCard = app.buttons["naru.connection.grid.card"].firstMatch
        guard firstCard.waitForExistence(timeout: 4) else {
            return
        }
        firstCard.tap()
    }

    private func startupGlanceButton(
        in app: XCUIApplication,
        containing labelFragment: String? = nil
    ) -> XCUIElement {
        if let labelFragment {
            return app.buttons
                .matching(NSPredicate(format: "label CONTAINS[c] %@", labelFragment))
                .firstMatch
        }

        let identified = app.buttons["naru.session.startupGlanceScaleMode"]
        if identified.exists {
            return identified
        }
        return app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Startup glance"))
            .firstMatch
    }

    private struct SeedProfile {
        let id = UUID()
        let displayName: String
        let host: String
        let port = 5900
        let hostKind = "magicDNS"
    }

    private func writeSeedProfiles(_ profiles: [SeedProfile], to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = profiles.map { profile in
            [
                "id": profile.id.uuidString,
                "displayName": profile.displayName,
                "host": profile.host,
                "port": profile.port,
                "hostKind": profile.hostKind,
                "allowsPiPWatch": true
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: fileURL, options: .atomic)
    }
}
