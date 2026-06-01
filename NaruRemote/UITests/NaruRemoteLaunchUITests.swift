import XCTest

@MainActor
final class NaruRemoteLaunchUITests: XCTestCase {
    func testAppShellLaunchesOnIPadSimulator() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = launchAppWithEmptyProfileStore()

        XCTAssertTrue(app.staticTexts["Naru Remote"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Add a private VNC profile"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Add a computer to begin."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["naru.home.empty.addProfile"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Remote Input Dock"].exists)
        XCTAssertFalse(app.staticTexts["Diagnostics"].exists)
    }

    func testRemoteInputDockMovesAboveKeyboardWhileComposing() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = launchAppWithProfileStore(seedProfiles: [
            SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
        ])

        openFirstConnectionCardIfPresent(app: app)

        let editor = app.textViews["Remote input text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

        let verticalGap = keyboard.frame.minY - editor.frame.maxY
        XCTAssertGreaterThanOrEqual(verticalGap, 0)
        XCTAssertLessThan(verticalGap, 96)
    }

    func testAddProfileOpensProfileEditor() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = launchAppWithEmptyProfileStore()

        let addProfile = app.buttons["Add Profile"]
        XCTAssertTrue(addProfile.waitForExistence(timeout: 8))
        addProfile.tap()

        XCTAssertTrue(app.navigationBars["Add Profile"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["Profile name"].waitForExistence(timeout: 2))
        let hostField = app.textFields["MagicDNS or private host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 2))

        app.typeText("studio.tailnet.ts.net")
        XCTAssertEqual(hostField.value as? String, "studio.tailnet.ts.net")
    }

    private func launchAppWithEmptyProfileStore() -> XCUIApplication {
        launchAppWithProfileStore()
    }

    private func launchAppWithProfileStore(seedProfiles: [SeedProfile] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
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
