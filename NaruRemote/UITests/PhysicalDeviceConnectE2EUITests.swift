import XCTest

@MainActor
final class PhysicalDeviceConnectE2EUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testPhysicalDeviceConnectsToConfiguredMac() throws {
        addSystemPermissionHandler()

        let app = XCUIApplication()
        app.launchEnvironment["NARU_TEST_LOG_DIAGNOSTIC_EXPORT"] = "1"
        let expectsSeededProfile = hasSeededPhysicalProfileConfiguration
        guard expectsSeededProfile || !isRunningInSimulator else {
            throw XCTSkip("Physical E2E requires an injected profile when running on a simulator")
        }
        forwardSeededPhysicalProfileIfPresent(to: app)
        app.launch()

        if app.staticTexts["Connections"].waitForExistence(timeout: 8) {
            openNewestPhysicalCard(in: app)
        } else {
            attachFailureArtifacts(app: app, name: "physical-connect-no-grid")
            guard expectsSeededProfile else {
                throw XCTSkip("No physical E2E profile was injected and no saved profile grid is available")
            }
            XCTAssertTrue(
                false,
                "Expected the seeded or saved physical-device profile grid to be visible"
            )
        }

        let activeBadge = app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] %@", "Active")).firstMatch
        let failureBadge = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Failed")).firstMatch
        let inFlightBadge = app.staticTexts
            .matching(NSPredicate(format: "label MATCHES[c] %@", "(Connecting|Authenticating|Reconnecting.*)"))
            .firstMatch
        if !activeBadge.exists,
           !failureBadge.exists,
           !inFlightBadge.waitForExistence(timeout: 2) {
            guard let connect = waitForConnectButton(in: app, timeout: 8) else {
                attachFailureArtifacts(app: app, name: "physical-connect-no-connect-button")
                XCTAssertTrue(false, "Connect button must be visible for saved physical profile")
                return
            }

            connect.tap()
            app.tap()
        }

        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if activeBadge.exists || failureBadge.exists {
                break
            }
            usleep(250_000)
        }

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = activeBadge.exists ? "physical-connect-active" : "physical-connect-final"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(activeBadge.exists, "Expected physical device connection to reach Active state")
    }

    private func waitForConnectButton(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let identifiedConnect = app.buttons["naru.session.connect"]
        if identifiedConnect.waitForExistence(timeout: timeout) {
            return identifiedConnect
        }

        let labeledConnect = app.buttons["Connect"]
        if labeledConnect.waitForExistence(timeout: 1) {
            return labeledConnect
        }

        return nil
    }

    private var hasSeededPhysicalProfileConfiguration: Bool {
        let env = ProcessInfo.processInfo.environment
        return !(env["NARU_PHYSICAL_E2E_HOST"] ?? "").isEmpty
            && !(env["NARU_PHYSICAL_E2E_PASSWORD"] ?? "").isEmpty
    }

    private var isRunningInSimulator: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["SIMULATOR_UDID"] != nil || env["SIMULATOR_DEVICE_NAME"] != nil
    }

    private func forwardSeededPhysicalProfileIfPresent(to app: XCUIApplication) {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["NARU_PHYSICAL_E2E_HOST"], !host.isEmpty,
              let password = env["NARU_PHYSICAL_E2E_PASSWORD"], !password.isEmpty
        else {
            return
        }

        let profileID = UUID()
        let credentialRef = "vnc-password:\(profileID.uuidString)"
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_ID"] = profileID.uuidString
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_NAME"] = env["NARU_PHYSICAL_E2E_NAME"] ?? "Physical E2E Mac"
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = host
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_PORT"] = env["NARU_PHYSICAL_E2E_PORT"] ?? "5900"
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST_KIND"] = env["NARU_PHYSICAL_E2E_HOST_KIND"] ?? "privateAddress"
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_CREDENTIAL_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_PASSWORD"] = password
    }

    private func addSystemPermissionHandler() {
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for buttonTitle in ["Allow", "OK", "허용", "확인"] {
                let button = alert.buttons[buttonTitle]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    private func openNewestPhysicalCard(in app: XCUIApplication) {
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Physical E2E")).firstMatch
        if card.waitForExistence(timeout: 4) {
            card.tap()
            return
        }

        openFirstSavedCard(in: app)
    }

    private func openFirstSavedCard(in app: XCUIApplication) {
        let firstCard = app.buttons["naru.connection.grid.card"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 4), "At least one connection grid card must be visible")
        firstCard.tap()
    }

    private func attachFailureArtifacts(app: XCUIApplication, name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let screenshotAttachment = XCTAttachment(screenshot: screenshot)
        screenshotAttachment.name = "\(name)-screenshot"
        screenshotAttachment.lifetime = .keepAlways
        add(screenshotAttachment)

        let hierarchyAttachment = XCTAttachment(string: app.debugDescription)
        hierarchyAttachment.name = "\(name)-hierarchy"
        hierarchyAttachment.lifetime = .keepAlways
        add(hierarchyAttachment)
    }
}
