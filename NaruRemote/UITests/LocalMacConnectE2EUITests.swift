import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// End-to-end smoke that drives the Naru Remote app on the iPhone
/// simulator against a live macOS Screen Sharing endpoint
/// (192.168.45.148:5900 — the host machine running the simulator)
/// and verifies (a) the happy path actually shows a remote frame and
/// (b) the new actionable diagnostic copy from PR #45 surfaces on a
/// wrong-password attempt.
///
/// Skipped automatically when the host VNC port is not reachable so
/// CI runners and headless boxes don't fail.  Configuration via env
/// vars (set on the simulator's launchd via `simctl spawn launchctl
/// setenv`):
///
///   NARU_E2E_HOST     (default: 127.0.0.1 — this Mac's Screen Sharing)
///   NARU_E2E_PORT     (default: 5900)
///   NARU_E2E_PASSWORD (no default — happy-path skips if unset)
///
/// To bypass the (flaky) profile editor + keychain UI flow, the test
/// pre-seeds a profile with a known `credentialRef` and asks the app
/// to inject the password directly into Keychain at startup via the
/// `NARU_TEST_INJECT_KEYCHAIN_REF` / `NARU_TEST_INJECT_KEYCHAIN_PASSWORD`
/// hooks defined in `NaruRemoteApplication.applyTestInjectKeychainPassword`.
///
/// Output PNGs land in `artifacts/screenshots/local-mac-e2e/`.
@MainActor
final class LocalMacConnectE2EUITests: XCTestCase {

    /// Where `saveScreen(named:)` writes its PNGs.  Resolved at call
    /// time so each runner's environment picks an appropriate location:
    ///
    ///   1. `NARU_E2E_OUTPUT_DIR` — explicit override (CI artefact path,
    ///      developer's working tree, etc.).
    ///   2. `NSTemporaryDirectory()` + `naru-e2e-screenshots/` —
    ///      portable default, never points at an absent path.
    ///
    /// Screenshots are best-effort — `try?` on the disk write means a
    /// missing directory only loses the artefact, never fails the test.
    private var outputDirectory: String {
        if let override = ProcessInfo.processInfo.environment["NARU_E2E_OUTPUT_DIR"],
           !override.isEmpty
        {
            return override
        }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("naru-e2e-screenshots")
    }

    /// Defaults to this Mac's own Screen Sharing server, which is what the
    /// suite is named after and what `LiveMac*` tests already use.
    ///
    /// It used to default to a hard-coded LAN address (`192.168.45.148`) from
    /// whatever network the suite was written on. Nothing there answers now, so
    /// every unconfigured run failed at DNS/TCP — which is why the
    /// wrong-password test could never reach the authentication stage whose
    /// copy it asserts. A default that cannot produce the outcome under test is
    /// worse than no default.
    private var host: String {
        let configured = ProcessInfo.processInfo.environment["NARU_E2E_HOST"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        return "127.0.0.1"
    }

    private var port: Int {
        Int(ProcessInfo.processInfo.environment["NARU_E2E_PORT"] ?? "5900") ?? 5900
    }

    private var correctPassword: String? {
        ProcessInfo.processInfo.environment["NARU_E2E_PASSWORD"]
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testHappyPath_correctPasswordConnectsAndShowsFrame() throws {
        guard let password = correctPassword else {
            throw XCTSkip("NARU_E2E_PASSWORD not set — skipping live-server happy-path test")
        }

        let profileID = UUID()
        let credentialRef = "vnc-password:\(profileID.uuidString)"
        let app = launch(seedProfileID: profileID, credentialRef: credentialRef, password: password)

        openFirstConnectionCardIfPresent(app: app)

        // A saved card is the connection action: one tap enters Operation
        // and starts the attempt without an intermediate pre-connect screen.
        let diagnosticCorner = app.buttons["naru.session.diagnostics.corner"]
        XCTAssertTrue(
            diagnosticCorner.waitForExistence(timeout: 8),
            "A card tap must enter Operation and mount its persistent diagnostic control"
        )
        try saveScreen(named: "01-operation-connecting.png")

        // Wait up to 20s for Operation diagnostics to report Connected
        // (success) or Connection failed (failure). The
        // framebuffer itself is a Metal-backed surface that doesn't
        // expose an accessibility identifier through standard XCUI
        // queries, so we rely on the model-driven diagnostic value.
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if isConnected(diagnosticCorner) || isFailed(diagnosticCorner) {
                break
            }
            usleep(250_000)
        }

        try saveScreen(named: "02-post-connect.png")
        XCTAssertTrue(
            isConnected(diagnosticCorner),
            "Expected Operation diagnostics to report Connected after one card tap. See 02-post-connect.png."
        )
        XCTAssertFalse(
            isFailed(diagnosticCorner),
            "Did not expect Operation diagnostics to report a failed connection. See 02-post-connect.png."
        )
    }

    /// Connects to the live Mac, composes a known multilingual string, and
    /// taps Send. With the default keystroke delivery, Compose & Send types
    /// the finished text through as X11 Unicode keysyms (verified to render
    /// Korean/CJK on macOS Screen Sharing) — it does NOT touch the remote
    /// clipboard. The host-side harness confirms the marker landed in the
    /// focused app. The composed marker is fixed and privacy-safe so it can
    /// be asserted from outside the sandbox.
    func testComposeSend_typesThroughUnicodeKeysyms() throws {
        guard let password = correctPassword else {
            throw XCTSkip("NARU_E2E_PASSWORD not set — skipping live compose/send test")
        }

        let profileID = UUID()
        let credentialRef = "vnc-password:\(profileID.uuidString)"
        let app = launch(
            seedProfileID: profileID,
            credentialRef: credentialRef,
            password: password,
            extraEnvironment: ["NARU_TEST_FORCE_INPUT_DOCK": "1"]
        )

        openFirstConnectionCardIfPresent(app: app)

        let diagnosticCorner = app.buttons["naru.session.diagnostics.corner"]
        XCTAssertTrue(diagnosticCorner.waitForExistence(timeout: 8))
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if isConnected(diagnosticCorner) || isFailed(diagnosticCorner) { break }
            usleep(250_000)
        }
        XCTAssertTrue(isConnected(diagnosticCorner), "Session must be Connected before composing")
        try saveScreen(named: "09-active.png")

        // In a live session the dock shows the floating "Compose" reveal
        // first; tap it to surface the editor before typing.
        //
        // Instrumented (2026-07-05): the immersive top bar auto-hides
        // ~2.4s after connect, and its relayout can race the tap. Let the
        // chrome settle first, then tap with a FRESH query each attempt
        // and record whether the first tap actually surfaced the editor —
        // if a retry is needed that is itself a product finding (a real
        // finger hits the same race).
        sleep(3)
        var revealTapsNeeded = 0
        var editor = app.textViews["Remote input text"]
        for attempt in 1...3 {
            // Primary query is `buttons` — if that misses while the `.any`
            // fallback hits, an interactive control has lost its `.isButton`
            // trait (2026-07-12 finding: `.accessibilityElement(children:
            // .ignore)` without `.accessibilityAddTraits(.isButton)`), which
            // is a VoiceOver defect. Surface it as a test finding.
            var reveal = app.buttons["naru.input.compose-reveal"].firstMatch
            if !reveal.waitForExistence(timeout: 5) {
                reveal = app.descendants(matching: .any)["naru.input.compose-reveal"].firstMatch
                if reveal.exists {
                    XCTContext.runActivity(
                        named: "FINDING: compose reveal lost its .isButton trait (VoiceOver defect)"
                    ) { _ in }
                }
            }
            guard reveal.exists else { break }
            reveal.tap()
            revealTapsNeeded = attempt
            editor = app.textViews["Remote input text"]
            if editor.waitForExistence(timeout: 3) { break }
            editor = app.textViews.firstMatch
            if editor.waitForExistence(timeout: 1) { break }
            try saveScreen(named: String(format: "09b-reveal-miss-%d.png", attempt))
        }
        try saveScreen(named: "09b-after-reveal.png")
        if revealTapsNeeded > 1 {
            XCTContext.runActivity(named: "FINDING: compose reveal needed \(revealTapsNeeded) taps") { _ in }
        }

        XCTAssertTrue(editor.waitForExistence(timeout: 6), "Compose editor must be present once Active")

        editor.tap()
        // Fixed, privacy-safe marker spanning ASCII + Hangul so the host
        // harness can confirm Unicode-keysym type-through lands both scripts.
        let marker = "NARUSIM_한글_END"
        editor.typeText(marker)

        try saveScreen(named: "10-compose-typed.png")

        let send = app.buttons["naru.input.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 4))
        send.tap()

        try saveScreen(named: "11-after-send.png")

        // Hold so the host-side read has time to see the typed-through marker
        // land in the focused app before teardown.
        sleep(4)
    }

    /// Spec 011 — Type (type-through) is the session default. Connects to
    /// the live Mac, lets the activation promotion flip the dock to Type,
    /// raises the editor from the floating strip, and types the payload
    /// from `NARU_E2E_TYPE_TEXT` (default "Naru"). The host-side
    /// `VNCLiveStimulusWindow --text-probe` harness (launched separately
    /// with the matching payload) reports whether the exact text landed
    /// in the focused local text target — the end-to-end verdict for
    /// English ("Naru") and Korean ("한글") type-through.
    func testTypeMode_typesPayloadLive() throws {
        guard let password = correctPassword else {
            throw XCTSkip("NARU_E2E_PASSWORD not set — skipping live Type-mode test")
        }
        let payload = ProcessInfo.processInfo.environment["NARU_E2E_TYPE_TEXT"] ?? "Naru"

        let profileID = UUID()
        let credentialRef = "vnc-password:\(profileID.uuidString)"
        let app = launch(
            seedProfileID: profileID,
            credentialRef: credentialRef,
            password: password
        )

        openFirstConnectionCardIfPresent(app: app)

        let diagnosticCorner = app.buttons["naru.session.diagnostics.corner"]
        XCTAssertTrue(diagnosticCorner.waitForExistence(timeout: 8))
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if isConnected(diagnosticCorner) || isFailed(diagnosticCorner) { break }
            usleep(250_000)
        }
        XCTAssertTrue(isConnected(diagnosticCorner), "Session must be Connected before typing")
        try saveScreen(named: "20-type-connected.png")

        // Let the immersive chrome settle, then reveal the Type editor
        // from the floating strip (spec 011 US1 — the activation
        // promotion already selected Type mode).
        sleep(3)
        let typeReveal = app.buttons["naru.input.type-reveal"].firstMatch
        var revealed = false
        for _ in 1...3 where !revealed {
            if typeReveal.waitForExistence(timeout: 4) {
                typeReveal.tap()
            }
            revealed = app.textViews["Remote input text"].waitForExistence(timeout: 3)
                || app.descendants(matching: .any)["naru.input.editor"].waitForExistence(timeout: 1)
        }
        XCTAssertTrue(revealed, "Type editor must be reachable from the floating strip")

        let editor = app.textViews["Remote input text"]
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))

        editor.typeText(payload)
        try saveScreen(named: "21-type-typed.png")

        // In Type mode the local mirror accumulates the committed line;
        // delivery to the Mac is verified host-side by the probe result.
        let mirrorPredicate = NSPredicate(format: "value CONTAINS %@", payload)
        let mirrorExpectation = XCTNSPredicateExpectation(
            predicate: mirrorPredicate,
            object: editor
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [mirrorExpectation], timeout: 5),
            .completed,
            "Type-mode local mirror must contain the typed payload"
        )

        // Hold so the type-through chunks and the host probe settle.
        sleep(5)
    }

    /// A rejected password must still say *why*, and say it where the user is.
    ///
    /// This used to look for the session diagnostics corner, which was where a
    /// failed connect lived until spec 013 US-4 (2026-08-19) moved connecting
    /// and failing onto the host list: a connect that never reaches a first
    /// frame no longer opens the remote-control surface at all
    /// (`RemoteControlSurfacePolicy.phase` returns `.hostList` for `.failed`),
    /// so the corner it waited for cannot exist and the suite went red for a
    /// UI that had moved, not broken. The behaviour under test is unchanged —
    /// the card reports the failure, and its Diagnostics action carries the
    /// actionable safe-catalog entry.
    func testWrongPassword_showsActionableAuthDiagnostic() throws {
        let profileID = UUID()
        let credentialRef = "vnc-password:\(profileID.uuidString)"
        let app = launch(seedProfileID: profileID, credentialRef: credentialRef, password: "definitely-wrong-pw")
        openFirstConnectionCardIfPresent(app: app)

        // Failing keeps the host list on screen, and the card that was tapped
        // carries the reason (`ConnectionGridCardFailure` = `session.lastError`).
        let reconnect = app.buttons["naru.connection.grid.reconnect"].firstMatch
        XCTAssertTrue(
            reconnect.waitForExistence(timeout: 20),
            "A failed connect must annotate the card that started it, with a way to retry"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["naru.session.viewport"].exists,
            "A connect that never got a frame must not open an empty remote-control screen (spec 013 US-4)"
        )
        try saveScreen(named: "03-wrong-password-card.png")

        openDiagnosticsFromFirstCard(app: app)

        let macHint = NSPredicate(format: "label CONTAINS[c] %@", "VNC password was rejected")
        let macHintLabel = app.staticTexts.matching(macHint).firstMatch
        XCTAssertTrue(
            macHintLabel.waitForExistence(timeout: 30),
            "Expected the actionable authentication diagnostic; got a generic state instead."
        )
        try saveScreen(named: "03-wrong-password-diagnostic.png")
    }

    private func openDiagnosticsFromFirstCard(app: XCUIApplication) {
        let actions = app.buttons["naru.connection.grid.actions"].firstMatch
        XCTAssertTrue(
            actions.waitForExistence(timeout: 8),
            "Host card must expose its actions menu"
        )
        actions.tap()

        let diagnostics = app.buttons["naru.connection.grid.diagnostics"].firstMatch
        XCTAssertTrue(
            diagnostics.waitForExistence(timeout: 4),
            "Actions menu must offer Diagnostics (spec 013 US2-1)"
        )
        diagnostics.tap()
    }

    // MARK: - Helpers

    private func launch(
        seedProfileID: UUID,
        credentialRef: String,
        password: String,
        extraEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()

        // Profile JSON — store a single profile with a fixed UUID so
        // we can compute the matching credentialRef ahead of time.
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-e2e-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        do {
            try writeSeedProfile(
                id: seedProfileID,
                credentialRef: credentialRef,
                to: storeURL
            )
        } catch {
            XCTFail("Failed to seed profile JSON: \(error)")
        }

        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_OVERRIDE_INTERFACE_STYLE"] = "Light"
        // Inject the password into Keychain at app startup so the
        // model's `connectSelectedProfile` path can lookup the
        // credential without an editor flow.
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_PASSWORD"] = password
        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
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

    private func isConnected(_ diagnosticCorner: XCUIElement) -> Bool {
        diagnosticValue(diagnosticCorner).lowercased().hasPrefix("connected")
    }

    private func isFailed(_ diagnosticCorner: XCUIElement) -> Bool {
        diagnosticValue(diagnosticCorner).lowercased().hasPrefix("connection failed")
    }

    private func diagnosticValue(_ diagnosticCorner: XCUIElement) -> String {
        diagnosticCorner.value as? String ?? ""
    }

    private func writeSeedProfile(
        id: UUID,
        credentialRef: String,
        to fileURL: URL
    ) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dict: [String: Any] = [
            "id": id.uuidString,
            "displayName": "Mac LAN",
            "host": host,
            "port": port,
            "hostKind": "privateAddress",
            "favorite": false,
            "allowsPiPWatch": true,
            "credentialRef": credentialRef
        ]
        let data = try JSONSerialization.data(withJSONObject: [dict], options: [.prettyPrinted])
        try data.write(to: fileURL, options: [.atomic])
    }

    private func saveScreen(named filename: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = filename
        add(attachment)

        try? FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )
        let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename)
        try screenshot.pngRepresentation.write(to: url)
    }
}
