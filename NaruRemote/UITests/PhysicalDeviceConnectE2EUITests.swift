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
        try forwardSeededPhysicalProfileIfPresent(to: app)
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

    func testPhysicalDeviceSustainedCandidateGate() throws {
        addSystemPermissionHandler()

        let sustainedDuration = try sustainedCandidateDuration()
        guard hasSeededPhysicalProfileConfiguration else {
            throw XCTSkip("Physical sustained gate requires an injected profile")
        }

        let app = XCUIApplication()
        app.launchEnvironment["NARU_TEST_LOG_DIAGNOSTIC_EXPORT"] = "1"
        app.launchEnvironment["NARU_TEST_EXPOSE_DIAGNOSTIC_EXPORT_RELAY"] = "1"
        app.launchEnvironment["NARU_TEST_EMIT_DIAGNOSTIC_EXPORT_AFTER_ACTIVE_SECONDS"] =
            Self.secondsString(sustainedDuration)
        app.launchEnvironment["NARU_TEST_SKIP_SETTINGS_STORE_LOAD"] = "1"
        try forwardRequiredCandidateSettings(to: app)
        try forwardSeededPhysicalProfileIfPresent(to: app)
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Connections"].waitForExistence(timeout: 8),
            "Physical sustained gate must start from the connection grid"
        )
        openNewestPhysicalCard(in: app)

        guard let connect = waitForConnectButton(in: app, timeout: 8) else {
            attachFailureArtifacts(app: app, name: "physical-sustained-no-connect-button")
            XCTAssertTrue(false, "Connect button must be visible for the injected physical profile")
            return
        }
        connect.tap()
        app.tap()

        let activeBadge = app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] %@", "Active")).firstMatch
        let failureBadge = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Failed")).firstMatch
        XCTAssertTrue(
            waitForActiveSession(activeBadge: activeBadge, failureBadge: failureBadge, timeout: 30),
            "Expected physical sustained gate to reach Active before starting interactions"
        )

        attachSustainedCandidateConfiguration(duration: sustainedDuration)
        performSustainedInteractionCycle(in: app)

        let deadline = Date().addingTimeInterval(sustainedDuration)
        var nextInteractionAt = Date().addingTimeInterval(min(30, max(5, sustainedDuration / 3)))
        while Date() < deadline {
            XCTAssertFalse(failureBadge.exists, "Physical sustained gate must not enter a failed session state")
            if Date() >= nextInteractionAt {
                performSustainedInteractionCycle(in: app)
                nextInteractionAt = Date().addingTimeInterval(min(30, max(5, sustainedDuration / 3)))
            }
            usleep(500_000)
        }

        relayDiagnosticExportIfAvailable(in: app)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "physical-sustained-candidate-final"
        attachment.lifetime = .keepAlways
        add(attachment)

        revealControlsIfNeeded(in: app)
        XCTAssertTrue(
            activeBadge.waitForExistence(timeout: 3) || app.descendants(matching: .any)["naru.session.viewport"].exists,
            "Expected physical sustained gate to remain in the session surface"
        )
        XCTAssertFalse(failureBadge.exists, "Physical sustained gate finished in a failed state")

        let pipEvidence = exercisePiPWatchEnterExit(in: app)
        emitPhysicalPiPEvidence(pipEvidence)
        let pipAttachment = XCTAttachment(string: pipEvidence.jsonString())
        pipAttachment.name = "physical-pip-enter-exit-evidence"
        pipAttachment.lifetime = .keepAlways
        add(pipAttachment)
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

    private func waitForActiveSession(
        activeBadge: XCUIElement,
        failureBadge: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if activeBadge.exists {
                return true
            }
            if failureBadge.exists {
                return false
            }
            usleep(250_000)
        }
        return activeBadge.exists
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

    private func forwardSeededPhysicalProfileIfPresent(to app: XCUIApplication) throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["NARU_PHYSICAL_E2E_HOST"], !host.isEmpty,
              let password = env["NARU_PHYSICAL_E2E_PASSWORD"], !password.isEmpty
        else {
            return
        }

        let profileID = UUID()
        let credentialRef = "vnc-password:\(profileID.uuidString)"
        let helperVideoSeed = try helperVideoSeedConfiguration(
            profileID: profileID,
            environment: env
        )
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_ID"] = profileID.uuidString
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_NAME"] = env["NARU_PHYSICAL_E2E_NAME"] ?? "Physical E2E Mac"
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = host
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_PORT"] = env["NARU_PHYSICAL_E2E_PORT"] ?? "5900"
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST_KIND"] = env["NARU_PHYSICAL_E2E_HOST_KIND"] ?? "privateAddress"
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_CREDENTIAL_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_PASSWORD"] = password

        if let helperVideoSeed {
            app.launchEnvironment["NARU_TEST_SEED_HELPER_VIDEO_ENABLED"] = "1"
            app.launchEnvironment["NARU_TEST_SEED_HELPER_VIDEO_SECRET_REF"] = helperVideoSeed.secretRef
            app.launchEnvironment["NARU_TEST_SEED_HELPER_VIDEO_PAIRING_FINGERPRINT"] =
                helperVideoSeed.pairingFingerprint
            app.launchEnvironment["NARU_TEST_INJECT_HELPER_VIDEO_KEYCHAIN_REF"] = helperVideoSeed.secretRef
            app.launchEnvironment["NARU_TEST_INJECT_HELPER_VIDEO_KEYCHAIN_PASSWORD"] =
                helperVideoSeed.pairingSecret
        }
    }

    private func helperVideoSeedConfiguration(
        profileID: UUID,
        environment env: [String: String]
    ) throws -> HelperVideoSeedConfiguration? {
        let secret = env["NARU_PHYSICAL_E2E_HELPER_VIDEO_PAIRING_SECRET"]?.trimmedNonEmpty
        let fingerprint = env["NARU_PHYSICAL_E2E_HELPER_VIDEO_PAIRING_FINGERPRINT"]?.trimmedNonEmpty
        guard secret != nil || fingerprint != nil else {
            return nil
        }
        guard let secret, let fingerprint else {
            XCTFail(
                "NARU_PHYSICAL_E2E_HELPER_VIDEO_PAIRING_SECRET and " +
                    "NARU_PHYSICAL_E2E_HELPER_VIDEO_PAIRING_FINGERPRINT must be set together"
            )
            throw PhysicalSustainedGateConfigurationError.invalidSetting(
                "helper-video-pairing"
            )
        }

        return HelperVideoSeedConfiguration(
            secretRef: "helper-video-token:\(profileID.uuidString)",
            pairingSecret: secret,
            pairingFingerprint: fingerprint
        )
    }

    private func sustainedCandidateDuration() throws -> TimeInterval {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["NARU_PHYSICAL_E2E_SUSTAINED_SECONDS"], !raw.isEmpty else {
            throw XCTSkip("Set NARU_PHYSICAL_E2E_SUSTAINED_SECONDS=600 to run the 10 minute physical gate")
        }
        guard let seconds = TimeInterval(raw), seconds > 0 else {
            XCTFail("NARU_PHYSICAL_E2E_SUSTAINED_SECONDS must be a positive number")
            return 0
        }
        return seconds
    }

    private func forwardRequiredCandidateSettings(to app: XCUIApplication) throws {
        let mappings: [(source: String, target: String, allowed: Set<String>)] = [
            (
                "NARU_PHYSICAL_E2E_STREAM_POWER_MODE",
                "NARU_TEST_STREAM_POWER_MODE",
                ["balanced", "power-saver"]
            ),
            (
                "NARU_PHYSICAL_E2E_STREAM_ENCODING_MODE",
                "NARU_TEST_STREAM_ENCODING_MODE",
                [
                    "standard",
                    "local-low-latency-rgb565",
                    "zrle-compression-0",
                    "zrle-compression-0-rgb565",
                    "adaptive-good-full"
                ]
            ),
            (
                "NARU_PHYSICAL_E2E_STARTUP_PREFLIGHT_MODE",
                "NARU_TEST_STARTUP_PREFLIGHT_MODE",
                ["disabled", "one-hidden-frame"]
            ),
            (
                "NARU_PHYSICAL_E2E_STARTUP_GLANCE_SCALE_MODE",
                "NARU_TEST_STARTUP_GLANCE_SCALE_MODE",
                ["standard-045", "minimal-035", "glance-025"]
            )
        ]

        let env = ProcessInfo.processInfo.environment
        for mapping in mappings {
            guard let value = env[mapping.source], !value.isEmpty else {
                XCTFail("\(mapping.source) is required for the physical sustained candidate gate")
                throw PhysicalSustainedGateConfigurationError.missingSetting(mapping.source)
            }
            guard mapping.allowed.contains(value) else {
                XCTFail("\(mapping.source) must be one of \(mapping.allowed.sorted().joined(separator: "|"))")
                throw PhysicalSustainedGateConfigurationError.invalidSetting(mapping.source)
            }
            app.launchEnvironment[mapping.target] = value
        }
    }

    private func performSustainedInteractionCycle(in app: XCUIApplication) {
        let viewport = app.descendants(matching: .any)["naru.session.viewport"].firstMatch
        if viewport.waitForExistence(timeout: 3), viewport.isHittable {
            viewport.pinch(withScale: 1.45, velocity: 1)
            drag(
                in: viewport,
                from: CGVector(dx: 0.72, dy: 0.52),
                to: CGVector(dx: 0.28, dy: 0.48)
            )
            viewport.pinch(withScale: 0.85, velocity: -1)
        }

        exerciseTrackpadCandidateIfAvailable(in: app)
        exerciseComposeCandidateIfAvailable(in: app)
    }

    private func exerciseTrackpadCandidateIfAvailable(in app: XCUIApplication) {
        revealControlsIfNeeded(in: app)
        let pointerMode = app.buttons["naru.session.pointerMode"]
        guard pointerMode.waitForExistence(timeout: 1), pointerMode.isHittable else {
            return
        }

        pointerMode.tap()
        let trackpadSurface = app.descendants(matching: .any)["naru.session.trackpadSurface"].firstMatch
        if trackpadSurface.waitForExistence(timeout: 2), trackpadSurface.isHittable {
            drag(
                in: trackpadSurface,
                from: CGVector(dx: 0.35, dy: 0.35),
                to: CGVector(dx: 0.72, dy: 0.68)
            )
        }
        pointerMode.tap()
    }

    private func exerciseComposeCandidateIfAvailable(in app: XCUIApplication) {
        let env = ProcessInfo.processInfo.environment
        guard env["NARU_PHYSICAL_E2E_SKIP_COMPOSE"] != "1" else {
            return
        }

        let editor = composeEditor(in: app)
        guard editor.waitForExistence(timeout: 2), editor.isHittable else {
            return
        }

        editor.tap()
        let composeText = env["NARU_PHYSICAL_E2E_COMPOSE_TEXT"] ?? "naru sustained gate"
        editor.typeText(composeText)
        let send = app.buttons["naru.input.send"]
        if send.waitForExistence(timeout: 2), send.isEnabled {
            send.tap()
        }
    }

    private func relayDiagnosticExportIfAvailable(in app: XCUIApplication) {
        guard let payload = waitForDiagnosticExportRelay(in: app, timeout: 15) else {
            let attachment = XCTAttachment(string: "status=missing")
            attachment.name = "physical-diagnostic-export-relay-missing"
            attachment.lifetime = .keepAlways
            add(attachment)
            return
        }

        emitXcodeLogBlock(
            begin: "NARU_DIAGNOSTIC_EXPORT_BEGIN",
            end: "NARU_DIAGNOSTIC_EXPORT_END",
            payload: payload
        )
    }

    private func waitForDiagnosticExportRelay(in app: XCUIApplication, timeout: TimeInterval) -> String? {
        let relay = app.descendants(matching: .any)["naru.test.diagnosticExportRelay"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if relay.exists,
               let payload = relay.value as? String,
               payload.contains("\"schemaVersion\"") {
                return payload
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    private func exercisePiPWatchEnterExit(in app: XCUIApplication) -> PhysicalPiPEvidence {
        revealControlsIfNeeded(in: app)
        let pipButton = app.buttons["naru.session.pipWatch"]
        guard pipButton.waitForExistence(timeout: 3) else {
            return PhysicalPiPEvidence.blocked(
                enterStatus: "buttonMissing",
                exitStatus: "notAttempted",
                issueCodes: ["physical-pip-enter-control-missing"],
                setupActionLabels: ["inspect-physical-pip-enter-control"]
            )
        }

        guard pipButton.isEnabled else {
            return PhysicalPiPEvidence.blocked(
                enterStatus: "buttonDisabled",
                exitStatus: "notAttempted",
                issueCodes: ["physical-pip-unavailable"],
                setupActionLabels: ["inspect-physical-pip-controller-support"]
            )
        }

        pipButton.tap()
        let pipDisplay = app.descendants(matching: .any)["naru.session.pipDisplayLayer"].firstMatch
        let watchingStatus = app.staticTexts["Watching in PiP"]
        let entered = pipDisplay.waitForExistence(timeout: 5) || watchingStatus.waitForExistence(timeout: 1)
        guard entered else {
            return PhysicalPiPEvidence.blocked(
                enterStatus: "watchingNotObserved",
                exitStatus: "notAttempted",
                issueCodes: ["physical-pip-enter-failed"],
                setupActionLabels: ["inspect-physical-pip-enter-exit"]
            )
        }

        app.activate()
        revealControlsIfNeeded(in: app)
        let disconnect = app.buttons["naru.session.disconnect"]
        guard disconnect.waitForExistence(timeout: 4), disconnect.isEnabled else {
            return PhysicalPiPEvidence.blocked(
                enterStatus: "entered",
                exitStatus: "disconnectUnavailable",
                issueCodes: ["physical-pip-exit-control-missing"],
                setupActionLabels: ["inspect-physical-pip-enter-exit"]
            )
        }

        disconnect.tap()
        let connect = app.buttons["naru.session.connect"]
        let exited = connect.waitForExistence(timeout: 5) || app.staticTexts["Connections"].waitForExistence(timeout: 2)
        guard exited else {
            return PhysicalPiPEvidence.blocked(
                enterStatus: "entered",
                exitStatus: "sessionStillActive",
                issueCodes: ["physical-pip-exit-failed"],
                setupActionLabels: ["inspect-physical-pip-enter-exit"]
            )
        }

        return PhysicalPiPEvidence(
            status: "passed",
            enterStatus: "entered",
            exitStatus: "exited",
            issueCodes: [],
            setupActionLabels: []
        )
    }

    private func emitPhysicalPiPEvidence(_ evidence: PhysicalPiPEvidence) {
        emitXcodeLogBlock(
            begin: "NARU_PHYSICAL_PIP_EVIDENCE_BEGIN",
            end: "NARU_PHYSICAL_PIP_EVIDENCE_END",
            payload: evidence.jsonString()
        )
    }

    private func emitXcodeLogBlock(begin: String, end: String, payload: String) {
        let text = "\n\(begin)\n\(payload)\n\(end)\n"
        FileHandle.standardError.write(Data(text.utf8))
    }

    private func composeEditor(in app: XCUIApplication) -> XCUIElement {
        let lifecycleIdentifier = NSPredicate(format: "identifier BEGINSWITH %@", "naru.input.editor;")
        let lifecycleEditor = app.descendants(matching: .any).matching(lifecycleIdentifier).firstMatch
        if lifecycleEditor.exists {
            return lifecycleEditor
        }

        let identified = app.descendants(matching: .any)["naru.input.editor"].firstMatch
        if identified.exists {
            return identified
        }

        return app.textViews["Remote input text"]
    }

    private func revealControlsIfNeeded(in app: XCUIApplication) {
        let reveal = app.buttons["naru.session.controls.reveal"]
        if reveal.exists, reveal.isHittable {
            reveal.tap()
        }
    }

    private func drag(in element: XCUIElement, from start: CGVector, to end: CGVector) {
        let startCoordinate = element.coordinate(withNormalizedOffset: start)
        let endCoordinate = element.coordinate(withNormalizedOffset: end)
        startCoordinate.press(forDuration: 0.05, thenDragTo: endCoordinate)
    }

    private func attachSustainedCandidateConfiguration(duration: TimeInterval) {
        let env = ProcessInfo.processInfo.environment
        let composeClass = Self.composePayloadClass(env["NARU_PHYSICAL_E2E_COMPOSE_TEXT"])
        let text = [
            "target=iphone-sustained-usability-v2",
            "durationSeconds=\(Self.secondsString(duration))",
            "streamPowerMode=\(env["NARU_PHYSICAL_E2E_STREAM_POWER_MODE"] ?? "default")",
            "streamEncodingMode=\(env["NARU_PHYSICAL_E2E_STREAM_ENCODING_MODE"] ?? "default")",
            "startupPreflightMode=\(env["NARU_PHYSICAL_E2E_STARTUP_PREFLIGHT_MODE"] ?? "default")",
            "startupGlanceScaleMode=\(env["NARU_PHYSICAL_E2E_STARTUP_GLANCE_SCALE_MODE"] ?? "default")",
            "composePayloadClass=\(composeClass)",
            "diagnosticExport=look for the final NARU_DIAGNOSTIC_EXPORT block in xcodebuild logs"
        ].joined(separator: "\n")
        let attachment = XCTAttachment(string: text)
        attachment.name = "physical-sustained-candidate-config"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func composePayloadClass(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "default-ascii"
        }
        return value.unicodeScalars.allSatisfy(\.isASCII) ? "ascii" : "unicode"
    }

    private static func secondsString(_ value: TimeInterval) -> String {
        let rounded = Int(value.rounded())
        if abs(value - TimeInterval(rounded)) < 0.001 {
            return "\(rounded)"
        }
        return String(format: "%.1f", value)
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

private enum PhysicalSustainedGateConfigurationError: Error {
    case missingSetting(String)
    case invalidSetting(String)
}

private struct HelperVideoSeedConfiguration {
    let secretRef: String
    let pairingSecret: String
    let pairingFingerprint: String
}

private struct PhysicalPiPEvidence: Codable {
    let schemaVersion: Int
    let mode: String
    let status: String
    let enterStatus: String
    let exitStatus: String
    let issueCodes: [String]
    let setupActionLabels: [String]
    let diagnosticPolicyLabels: [String]

    init(
        status: String,
        enterStatus: String,
        exitStatus: String,
        issueCodes: [String],
        setupActionLabels: [String]
    ) {
        self.schemaVersion = 1
        self.mode = "physical-iphone-helper-video-pip-evidence"
        self.status = status
        self.enterStatus = enterStatus
        self.exitStatus = exitStatus
        self.issueCodes = issueCodes
        self.setupActionLabels = setupActionLabels
        self.diagnosticPolicyLabels = [
            "physical-pip-fixed-labels-only",
            "pip-watch-only-no-input-payloads"
        ]
    }

    static func blocked(
        enterStatus: String,
        exitStatus: String,
        issueCodes: [String],
        setupActionLabels: [String]
    ) -> PhysicalPiPEvidence {
        PhysicalPiPEvidence(
            status: "blocked",
            enterStatus: enterStatus,
            exitStatus: exitStatus,
            issueCodes: issueCodes,
            setupActionLabels: setupActionLabels
        )
    }

    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
