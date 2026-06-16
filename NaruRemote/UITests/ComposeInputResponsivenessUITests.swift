import XCTest

@MainActor
final class ComposeInputResponsivenessUITests: XCTestCase {
    func testComposeEditorAcceptsSecondKoreanSyllableAfterFirstInput() {
        let app = launchAppWithSampleProfile()
        let editor = composeEditor(in: app)
        if !editor.waitForExistence(timeout: 3) {
            openFirstConnectionCardIfPresent(app: app)
        }

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
    }

    func testActiveSessionCompactComposeEditorAcceptsSecondKoreanSyllableAfterFirstInput() {
        let app = launchAppWithActiveSessionFixture()
        let editor = composeEditor(in: app)

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
    }

    func testFocusedActiveSessionComposeSurvivesConfirmationStatusClearAfterFirstInput() {
        let app = launchAppWithActiveSessionConfirmationUnavailableFixture()
        let editor = composeEditor(in: app)
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 3),
            "Clearing the stale send result after the first syllable must not collapse the system keyboard."
        )

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
    }

    func testFocusedActiveSessionComposeAcceptsKoreanDuringTrackpadCursorStorm() {
        let app = launchAppWithActiveSessionConfirmationUnavailableFixture(
            trackpadCursorStorm: true
        )
        let editor = composeEditor(in: app)
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 2),
            "Viewport cursor mirror pressure must not collapse or freeze focused Compose input."
        )
    }

    func testFocusedActiveSessionComposeAcceptsKoreanDuringFramebufferAndCursorStorm() {
        let app = launchAppWithActiveSessionConfirmationUnavailableFixture(
            trackpadCursorStorm: true,
            framebufferFlood: true
        )
        let editor = composeEditor(in: app)
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 2),
            "Full-frame stream pressure after the first syllable must not collapse the keyboard."
        )

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 2),
            "Framebuffer flood plus cursor pressure must not freeze focused Compose input."
        )
    }

    func testFocusedActiveSessionComposeAcceptsKoreanDuringFullInteractionStorm() {
        let app = launchAppWithActiveSessionConfirmationUnavailableFixture(
            trackpadCursorStorm: true,
            framebufferFlood: true,
            modelPublishStorm: true
        )
        let editor = composeEditor(in: app)
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 2),
            "Model-published chrome pressure must not collapse the focused Compose keyboard after the first Korean/CJK syllable."
        )

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 2),
            "Frame flood, cursor storm, and model-published chrome churn must not freeze focused Compose input."
        )
    }

    func testFocusedActiveSessionComposeKeepsEditorInstanceDuringFullInteractionStorm() {
        let app = launchAppWithActiveSessionConfirmationUnavailableFixture(
            trackpadCursorStorm: true,
            framebufferFlood: true,
            modelPublishStorm: true,
            exposeComposeLifecycle: true
        )
        let editor = composeEditor(in: app)
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))

        let focusedProbe = waitForLifecycleProbe(in: app) { probe in
            probe.isFirstResponder && probe.makeCount == 1
        }
        let token = focusedProbe.instanceToken

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")
        let afterFirstInput = waitForLifecycleProbe(in: app) { probe in
            probe.instanceToken == token
                && probe.makeCount == 1
                && probe.textChangeCount >= 1
                && probe.isFirstResponder
        }

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
        let afterSecondInput = waitForLifecycleProbe(in: app) { probe in
            probe.instanceToken == token
                && probe.makeCount == 1
                && probe.textChangeCount >= afterFirstInput.textChangeCount
                && probe.isFirstResponder
        }

        XCTAssertEqual(afterSecondInput.instanceToken, token)
        XCTAssertEqual(afterSecondInput.makeCount, 1)
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 2),
            "The active UITextView instance must stay first responder while frame/cursor/model storms continue."
        )
    }

    func testFocusedActiveSessionComposeSurvivesHelperVideoHealthStorm() {
        let app = launchAppWithActiveSessionConfirmationUnavailableFixture(
            trackpadCursorStorm: true,
            framebufferFlood: true,
            modelPublishStorm: true,
            helperVideoHealthStorm: true,
            exposeComposeLifecycle: true
        )
        let editor = composeEditor(in: app)
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))

        let focusedProbe = waitForLifecycleProbe(in: app) { probe in
            probe.isFirstResponder && probe.makeCount == 1
        }
        let token = focusedProbe.instanceToken

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")
        let afterFirstInput = waitForLifecycleProbe(in: app) { probe in
            probe.instanceToken == token
                && probe.makeCount == 1
                && probe.textChangeCount >= 1
                && probe.isFirstResponder
        }

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
        let afterSecondInput = waitForLifecycleProbe(in: app) { probe in
            probe.instanceToken == token
                && probe.makeCount == 1
                && probe.textChangeCount >= afterFirstInput.textChangeCount
                && probe.isFirstResponder
        }

        XCTAssertEqual(afterSecondInput.instanceToken, token)
        XCTAssertEqual(afterSecondInput.makeCount, 1)
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 2),
            "Helper-video status churn must not remount or freeze the focused Compose editor."
        )
    }

    func testFocusedActiveSessionComposeDefersIncomingClipboardChromeDuringFullStorm() {
        let app = launchAppWithActiveSessionConfirmationUnavailableFixture(
            trackpadCursorStorm: true,
            framebufferFlood: true,
            modelPublishStorm: true,
            helperVideoHealthStorm: true,
            incomingClipboardChromeStorm: true,
            exposeComposeLifecycle: true
        )
        let editor = composeEditor(in: app)
        let keyboard = app.keyboards.firstMatch
        let incomingClipboardBanner = app.descendants(matching: .any)["naru.input.incomingClipboard.banner"]

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))

        let focusedProbe = waitForLifecycleProbe(in: app) { probe in
            probe.isFirstResponder && probe.makeCount == 1
        }
        let token = focusedProbe.instanceToken

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")
        XCTAssertFalse(
            incomingClipboardBanner.waitForExistence(timeout: 0.5),
            "Incoming clipboard review chrome must be deferred while Compose owns first-responder focus; presenting a safe-area banner here can stall Korean/CJK IME after the first syllable."
        )
        let afterFirstInput = waitForLifecycleProbe(in: app) { probe in
            probe.instanceToken == token
                && probe.makeCount == 1
                && probe.textChangeCount >= 1
                && probe.isFirstResponder
        }

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
        let afterSecondInput = waitForLifecycleProbe(in: app) { probe in
            probe.instanceToken == token
                && probe.makeCount == 1
                && probe.textChangeCount >= afterFirstInput.textChangeCount
                && probe.isFirstResponder
        }

        XCTAssertEqual(afterSecondInput.instanceToken, token)
        XCTAssertEqual(afterSecondInput.makeCount, 1)
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 2),
            "Frame/cursor/model/helper/clipboard chrome storms must not remount or freeze the focused Compose editor."
        )
    }

    func testFocusedConnectingComposeDefersLiveLayoutAfterFirstFrameAndKeepsTyping() {
        let app = launchAppWithConnectingDelayedFirstFrameFixture()
        let editor = composeEditor(in: app)
        let keyboard = app.keyboards.firstMatch
        let firstFrameMarker = app.descendants(matching: .any)["naru.test.session.firstFrameReceived"]

        XCTAssertTrue(editor.waitForExistence(timeout: 8))

        editor.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))

        let focusedProbe = waitForLifecycleProbe(in: app) { probe in
            probe.isFirstResponder && probe.makeCount == 1
        }
        let token = focusedProbe.instanceToken

        editor.typeText("입")
        waitForEditor(editor, toContain: "입")

        XCTAssertTrue(
            firstFrameMarker.waitForExistence(timeout: 4),
            "The delayed test hook must publish the first frame while Compose is focused."
        )
        let postFirstFrame = waitForLifecycleProbe(in: app) { probe in
            probe.instanceToken == token
                && probe.makeCount == 1
                && probe.isFirstResponder
        }
        XCTAssertEqual(postFirstFrame.instanceToken, token)

        editor.typeText("력")
        waitForEditor(editor, toContain: "입력")
        let afterSecondInput = waitForLifecycleProbe(in: app) { probe in
            probe.instanceToken == token
                && probe.makeCount == 1
                && probe.textChangeCount >= postFirstFrame.textChangeCount
                && probe.isFirstResponder
        }

        XCTAssertEqual(afterSecondInput.instanceToken, token)
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 2),
            "The first-frame arrival must not freeze the Korean/CJK Compose keyboard after the first syllable."
        )
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

    private func waitForEditor(
        _ editor: XCUIElement,
        toContain expectedText: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "value CONTAINS %@", expectedText)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: editor)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        let value = editor.value as? String ?? ""
        XCTAssertEqual(result, .completed, file: file, line: line)
        XCTAssertTrue(
            value.contains(expectedText),
            "Expected compose editor value to contain \(expectedText), got \(value)",
            file: file,
            line: line
        )
    }

    private func waitForLifecycleProbe(
        in app: XCUIApplication,
        timeout: TimeInterval = 4,
        matching predicate: (ComposeLifecycleProbe) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ComposeLifecycleProbe {
        let lifecycleIdentifier = NSPredicate(format: "identifier BEGINSWITH %@", "naru.input.editor;")
        let lifecycleEditor = app.descendants(matching: .any).matching(lifecycleIdentifier).firstMatch
        guard lifecycleEditor.waitForExistence(timeout: timeout) else {
            let visibleTree = String(app.debugDescription.prefix(8_000))
            XCTFail("Lifecycle probe editor is missing. accessibilityTree=\(visibleTree)", file: file, line: line)
            return .empty
        }

        let deadline = Date().addingTimeInterval(timeout)
        var latest = ComposeLifecycleProbe(raw: lifecycleEditor.identifier)
        while Date() < deadline {
            latest = ComposeLifecycleProbe(raw: lifecycleEditor.identifier)
            if let latest, predicate(latest) {
                return latest
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTFail("Lifecycle probe did not reach expected state. latest=\(lifecycleEditor.identifier)", file: file, line: line)
        return latest ?? ComposeLifecycleProbe.empty
    }

    private func launchAppWithSampleProfile() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-compose-input-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_START_PROFILE_DETAIL"] = "1"
        try? writeSeedProfiles(
            [SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")],
            to: storeURL
        )
        app.launch()
        return app
    }

    private func launchAppWithActiveSessionFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = "session-active-widescreen"
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        app.launch()
        return app
    }

    private func launchAppWithActiveSessionConfirmationUnavailableFixture(
        trackpadCursorStorm: Bool = false,
        framebufferFlood: Bool = false,
        modelPublishStorm: Bool = false,
        helperVideoHealthStorm: Bool = false,
        incomingClipboardChromeStorm: Bool = false,
        exposeComposeLifecycle: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = "session-active-compose-confirmation-unavailable"
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        if trackpadCursorStorm {
            app.launchEnvironment["NARU_TEST_TRACKPAD_CURSOR_STORM"] = "1"
        }
        if framebufferFlood {
            app.launchEnvironment["NARU_TEST_FRAMEBUFFER_FLOOD"] = "1"
        }
        if modelPublishStorm {
            app.launchEnvironment["NARU_TEST_MODEL_PUBLISH_STORM"] = "1"
        }
        if helperVideoHealthStorm {
            app.launchEnvironment["NARU_TEST_HELPER_VIDEO_HEALTH_STORM"] = "1"
        }
        if incomingClipboardChromeStorm {
            app.launchEnvironment["NARU_TEST_INCOMING_CLIPBOARD_CHROME_STORM"] = "1"
        }
        if exposeComposeLifecycle {
            app.launchEnvironment["NARU_TEST_EXPOSE_COMPOSE_LIFECYCLE"] = "1"
        }
        app.launch()
        return app
    }

    private func launchAppWithConnectingDelayedFirstFrameFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = "session-connecting-delayed-first-frame"
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        app.launchEnvironment["NARU_TEST_EXPOSE_COMPOSE_LIFECYCLE"] = "1"
        app.launchEnvironment["NARU_TEST_DELAYED_FIRST_FRAME_AFTER_FOCUS_MILLISECONDS"] = "1500"
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

    private struct ComposeLifecycleProbe {
        var instanceToken: String
        var makeCount: Int
        var updateCount: Int
        var textChangeCount: Int
        var focusEventCount: Int
        var isFirstResponder: Bool

        static let empty = ComposeLifecycleProbe(
            instanceToken: "",
            makeCount: 0,
            updateCount: 0,
            textChangeCount: 0,
            focusEventCount: 0,
            isFirstResponder: false
        )

        init?(raw: String) {
            let payload = raw.replacingOccurrences(of: "naru.input.editor;", with: "")
            let fields = payload
                .split(separator: ";")
                .reduce(into: [String: String]()) { result, field in
                    let parts = field.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { return }
                    result[String(parts[0])] = String(parts[1])
                }
            guard let token = fields["token"],
                  let make = fields["make"].flatMap(Int.init),
                  let update = fields["update"].flatMap(Int.init),
                  let change = fields["change"].flatMap(Int.init),
                  let focus = fields["focus"].flatMap(Int.init)
            else {
                return nil
            }
            self.instanceToken = token
            self.makeCount = make
            self.updateCount = update
            self.textChangeCount = change
            self.focusEventCount = focus
            self.isFirstResponder = fields["firstResponder"] == "true"
        }

        private init(
            instanceToken: String,
            makeCount: Int,
            updateCount: Int,
            textChangeCount: Int,
            focusEventCount: Int,
            isFirstResponder: Bool
        ) {
            self.instanceToken = instanceToken
            self.makeCount = makeCount
            self.updateCount = updateCount
            self.textChangeCount = textChangeCount
            self.focusEventCount = focusEventCount
            self.isFirstResponder = isFirstResponder
        }
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
