import XCTest

@MainActor
final class NaruRemoteLaunchUITests: XCTestCase {
    func testAppShellLaunchesOnIPadSimulator() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = launchAppWithEmptyProfileStore()

        XCTAssertTrue(app.staticTexts["Add a computer to begin."].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.staticTexts["Connect to your Mac or Linux machine over your private Tailscale network."]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["naru.home.empty.addProfile"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Remote Input Dock"].exists)
        XCTAssertFalse(app.staticTexts["Diagnostics"].exists)
    }

    func testRemoteInputDockMovesAboveKeyboardWhileComposing() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = launchAppWithProfileStore(
            launchEnvironment: [
                "NARU_TEST_SKIP_PROFILE_STORE_LOAD": "1",
                "NARU_TEST_FIXTURE_SNAPSHOT": "session-active-widescreen"
            ]
        )

        let editor = app.textViews["Remote input text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

        let verticalGap = keyboard.frame.minY - editor.frame.maxY
        XCTAssertGreaterThanOrEqual(verticalGap, 0)
        XCTAssertLessThan(verticalGap, 96)
    }

    func testSelectedProfileWithoutSessionHidesRemoteInputDock() {
        XCUIDevice.shared.orientation = .portrait

        let app = launchAppWithProfileStore(
            seedProfiles: [
                SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
            ],
            launchEnvironment: [
                "NARU_TEST_START_PROFILE_DETAIL": "1",
                "NARU_TEST_SKIP_SETTINGS_STORE_LOAD": "1"
            ]
        )

        XCTAssertTrue(app.staticTexts["Studio Mac"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["naru.session.connect"].waitForExistence(timeout: 4))
        XCTAssertFalse(
            app.staticTexts["Remote Input Dock"].exists,
            "The Compose/Direct dock should not cover diagnostics before a session exists."
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

    func testStartupGlanceScaleOverrideIsScopedToLowTrafficProfiles() {
        XCUIDevice.shared.orientation = .portrait

        let standardApp = launchAppWithProfileStore(
            seedProfiles: [
                SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
            ],
            launchEnvironment: [
                "NARU_TEST_START_PROFILE_DETAIL": "1",
                "NARU_TEST_SKIP_SETTINGS_STORE_LOAD": "1"
            ]
        )
        openFirstConnectionCardIfPresent(app: standardApp)
        XCTAssertFalse(
            startupGlanceButton(in: standardApp).waitForExistence(timeout: 1),
            "Standard stream profile must not expose the startup glance scale control"
        )
        standardApp.terminate()

        let lowTrafficApp = launchAppWithProfileStore(
            seedProfiles: [
                SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
            ],
            launchEnvironment: [
                "NARU_TEST_START_PROFILE_DETAIL": "1",
                "NARU_TEST_SKIP_SETTINGS_STORE_LOAD": "1",
                "NARU_TEST_STREAM_ENCODING_MODE": "local-low-latency-rgb565",
                "NARU_TEST_STARTUP_GLANCE_SCALE_MODE": "glance-025"
            ]
        )
        openFirstConnectionCardIfPresent(app: lowTrafficApp)

        let glance025 = startupGlanceButton(in: lowTrafficApp, containing: "Startup glance 0.25")
        XCTAssertTrue(
            glance025.waitForExistence(timeout: 4),
            "Low-traffic RGB565 physical candidates must expose the injected glance scale"
        )
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

    private func openFirstConnectionCardIfPresent(app: XCUIApplication) {
        let gridHeading = app.staticTexts["Connections"]
        guard gridHeading.waitForExistence(timeout: 3) else {
            return
        }

        let firstCard = app.buttons["naru.connection.grid.card"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 4))
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
