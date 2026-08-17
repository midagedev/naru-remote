import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// Drives the simulator through the canonical Naru Remote screens and
/// saves PNGs for an offline UX & design audit.  No assertions on
/// visual quality — those happen in vision review.  Only sanity
/// assertions that the screenshots wrote out non-empty.
///
/// Output directory defaults to this checkout's `artifacts/` tree so isolated
/// worktrees do not write screenshots into the main repo checkout. A configured
/// test environment can still override it with `NARU_UX_AUDIT_OUTPUT_DIR`.
///
/// One test method per state-group, no shared mutable state, so the
/// run order is irrelevant and any single state can be exercised in
/// isolation via `-only-testing`.
@MainActor
final class UXAuditScreenshotsUITests: XCTestCase {

    private let outputDirectory = UXAuditScreenshotsUITests.defaultOutputDirectory()

    private static func defaultOutputDirectory() -> String {
        let override = ProcessInfo.processInfo.environment["NARU_UX_AUDIT_OUTPUT_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty {
            return override
        }

        let testSource = URL(fileURLWithPath: #filePath)
        let checkoutRoot = testSource
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return checkoutRoot
            .appendingPathComponent("artifacts/screenshots/ux-audit", isDirectory: true)
            .path
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        // Default to portrait so iPhone screenshots reflect the
        // canonical phone-first design target (constitution §VI).
        // The iPad test forces landscape inside its body.
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - iPhone — empty home (zero saved profiles, single CTA)

    func testEmptyHome_light() throws {
        try runEmptyHome(mode: .light, deviceTag: "iphone")
    }

    func testEmptyHome_dark() throws {
        try runEmptyHome(mode: .dark, deviceTag: "iphone")
    }

    private func runEmptyHome(mode: ColorMode, deviceTag: String) throws {
        let app = launchApp(mode: mode)

        // First-launch surface (spec FR-015): zero profiles → exactly
        // one primary CTA into the profile editor, no checklist.
        XCTAssertTrue(
            app.buttons["naru.home.empty.addProfile"].waitForExistence(timeout: 8),
            "Empty-home Add Computer CTA must be visible after launch"
        )
        try saveScreen(named: "01-firstlaunch-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — profile editor (add)

    func testProfileEditorAdd_light() throws {
        try runProfileEditorAdd(mode: .light, deviceTag: "iphone")
    }

    func testProfileEditorAdd_dark() throws {
        try runProfileEditorAdd(mode: .dark, deviceTag: "iphone")
    }

    private func runProfileEditorAdd(mode: ColorMode, deviceTag: String) throws {
        let app = launchApp(mode: mode)

        // First launch (zero profiles) lands on the full-screen empty
        // home (spec FR-015); its single CTA opens the add-profile sheet.
        // The sidebar "Add Profile" toolbar button only exists once a
        // profile has been saved.
        let addProfile = app.buttons["naru.home.empty.addProfile"]
        XCTAssertTrue(addProfile.waitForExistence(timeout: 8))
        addProfile.tap()

        XCTAssertTrue(app.navigationBars["Add Profile"].waitForExistence(timeout: 4))
        // Brief settle so the form lays out.
        XCTAssertTrue(app.textFields["Profile name"].waitForExistence(timeout: 2))

        // State 2: empty form
        try saveScreen(named: "02-profile-editor-empty-\(deviceTag)-\(mode.suffix).png")

        // State 3: filled form
        let nameField = app.textFields["Profile name"]
        let hostField = app.textFields["MagicDNS or private host"]
        nameField.tap()
        nameField.typeText("Studio Mac")
        hostField.tap()
        hostField.typeText("studio.tailnet.ts.net")
        // Dismiss keyboard so the form layout looks like the
        // resting "I just typed and tapped Done" state.
        app.toolbars.buttons["Return"].tap(if: \.exists)

        try saveScreen(named: "03-profile-editor-filled-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — connection grid + diagnostics

    func testProfileSelectedAndDiagnostics_light() throws {
        try runProfileSelectedAndDiagnostics(mode: .light, deviceTag: "iphone")
    }

    func testProfileSelectedAndDiagnostics_dark() throws {
        try runProfileSelectedAndDiagnostics(mode: .dark, deviceTag: "iphone")
    }

    private func runProfileSelectedAndDiagnostics(mode: ColorMode, deviceTag: String) throws {
        // Pre-seed a profile so the app auto-selects it and lands
        // directly on the detail column on iPhone — no sidebar
        // back-navigation needed.
        let app = launchApp(
            mode: mode,
            seedProfiles: [
                SeedProfile(
                    displayName: "Studio Mac",
                    host: "studio.tailnet.ts.net"
                )
            ]
        )

        XCTAssertTrue(
            app.staticTexts["Connections"].waitForExistence(timeout: 8),
            "Connection grid must be the default entry point with saved profiles"
        )
        XCTAssertTrue(
            app.buttons["naru.connection.grid.card"].firstMatch.waitForExistence(timeout: 4),
            "Connection grid must render at least one profile card"
        )

        // State 4: default connection grid with a saved profile.
        try saveScreen(named: "04-connection-grid-\(deviceTag)-\(mode.suffix).png")

        openFirstConnectionCardIfPresent(app: app)
        let returnToGrid = app.buttons["naru.operation.connections"]
        XCTAssertTrue(
            returnToGrid.waitForExistence(timeout: 4),
            "Operation must keep Connections directly reachable."
        )
        returnToGrid.tap()
        XCTAssertTrue(
            app.buttons["naru.connection.grid.card"].firstMatch.waitForExistence(timeout: 4),
            "Returning from profile detail must restore the connection grid."
        )
        openFirstConnectionCardIfPresent(app: app)
        XCTAssertTrue(
            app.buttons["naru.session.diagnostics.corner"].waitForExistence(timeout: 4),
            "Operation must keep diagnostics visible without a stacked third screen"
        )
        let sessionTools = app.buttons["naru.session.tools.menu"]
        if !sessionTools.exists {
            let reveal = app.buttons["naru.session.controls.reveal"]
            XCTAssertTrue(reveal.waitForExistence(timeout: 4))
            reveal.tap()
        }
        XCTAssertTrue(
            sessionTools.waitForExistence(timeout: 4),
            "Operation must expose secondary stream and PiP controls from one Session tools menu"
        )
        XCTAssertFalse(
            app.buttons["naru.session.streamPowerMode"].exists,
            "Profile detail must not keep stream tuning as a permanent primary button on iPhone"
        )
        XCTAssertFalse(
            app.buttons["naru.session.pointerMode"].exists,
            "Profile detail must not show disabled pointer mode before a session is active"
        )

        // State 5: diagnostics populated.  Closes UX punch-list #007
        // — previously this state re-launched the app and tapped the
        // Checks pill, but `runConnectionChecks()` only seeds two
        // stages and the second flips to .running asynchronously, so
        // the screenshot landed before any rows rendered and was
        // byte-identical to #04.  Drive the state through the
        // `NARU_TEST_FIXTURE_SNAPSHOT=diagnostics-populated` hook
        // instead — four deterministic stages including the running
        // authentication row.
        let diagnosticsApp = launchAppWithFixture(.diagnosticsPopulated, mode: mode)
        let diagnosticCorner = diagnosticsApp.buttons["naru.session.diagnostics.corner"]
        XCTAssertTrue(
            diagnosticCorner.waitForExistence(timeout: 8),
            "Persistent Operation diagnostic capsule must be mounted"
        )
        diagnosticCorner.tap()
        XCTAssertTrue(
            diagnosticsApp.navigationBars["Diagnostics"].waitForExistence(timeout: 4),
            "Capsule must open the full diagnostics sheet"
        )
        XCTAssertTrue(
            diagnosticsApp.staticTexts["Host resolved"].waitForExistence(timeout: 4),
            "Diagnostic rows must render in the sheet before screenshot"
        )
        try saveScreen(named: "05-diagnostics-populated-\(deviceTag)-\(mode.suffix).png")
    }


    // MARK: - iPhone — compose dock with text

    func testComposeDockWithText_light() throws {
        try runComposeDockWithText(mode: .light, deviceTag: "iphone")
    }

    func testComposeDockWithText_dark() throws {
        try runComposeDockWithText(mode: .dark, deviceTag: "iphone")
    }

    private func runComposeDockWithText(mode: ColorMode, deviceTag: String) throws {
        let app = launchAppWithSampleProfile(mode: mode)
        openFirstConnectionCardIfPresent(app: app)

        let editor = app.textViews["Remote input text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        // Focus the editor and wait for the system keyboard BEFORE typing —
        // typeText raced the async first-responder handoff on the reworked
        // Operation surface (2026-07-12 flake).
        editor.tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        enterStoreComposeText(
            "안녕하세요 · Hello · こんにちは",
            into: editor,
            in: app
        )

        // State 7: compose mode with text typed, Send enabled.
        try saveScreen(named: "07-compose-text-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — shared accessory key strip (spec 011)

    func testAccessoryStrip_light() throws {
        try runAccessoryStrip(mode: .light, deviceTag: "iphone", expandFn: false)
    }

    func testAccessoryStrip_dark() throws {
        try runAccessoryStrip(mode: .dark, deviceTag: "iphone", expandFn: false)
    }

    func testAccessoryStripFn_light() throws {
        try runAccessoryStrip(mode: .light, deviceTag: "iphone", expandFn: true)
    }

    func testAccessoryStripFn_dark() throws {
        try runAccessoryStrip(mode: .dark, deviceTag: "iphone", expandFn: true)
    }

    func testStoreIPadAccessoryStripFn_light() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        try runAccessoryStrip(mode: .light, deviceTag: "ipad-landscape", expandFn: true)
    }

    private func runAccessoryStrip(mode: ColorMode, deviceTag: String, expandFn: Bool) throws {
        let app = launchAppSuppressingDirectWarningWithSampleProfile(mode: mode)
        openFirstConnectionCardIfPresent(app: app)

        XCTAssertTrue(app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8))

        let strip = waitForStableElement(
            in: app,
            identifier: "naru.input.accessory.strip",
            timeout: 4
        )
        XCTAssertTrue(
            strip.exists,
            "The shared accessory strip (modifiers + Esc/Tab/arrows) must ride above the editor in both dock modes."
        )

        if !expandFn {
            try saveScreen(named: "08-accessory-strip-\(deviceTag)-\(mode.suffix).png")
            return
        }

        let fnToggle = app.buttons["naru.input.accessory.fn"]
        XCTAssertTrue(fnToggle.waitForExistence(timeout: 4))
        fnToggle.tap()

        let fnRow = app.otherElements["naru.input.accessory.fn-row"]
        if !fnRow.waitForExistence(timeout: 4) {
            // A transient operation-status update can steal the first
            // SwiftUI tap during screenshot setup. Retry the local-only
            // expansion once; it never emits a remote key event.
            fnToggle.tap()
        }
        XCTAssertTrue(
            fnRow.waitForExistence(timeout: 4),
            "The Fn expansion must reveal the function-row keys."
        )
        try saveScreen(named: "09-accessory-fn-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — sticky modifier locked

    func testStickyModifierLocked_light() throws {
        try runStickyModifierLocked(mode: .light, deviceTag: "iphone")
    }

    func testStickyModifierLocked_dark() throws {
        try runStickyModifierLocked(mode: .dark, deviceTag: "iphone")
    }

    private func runStickyModifierLocked(mode: ColorMode, deviceTag: String) throws {
        // Deliberately NO card tap: opening a card starts a real connect,
        // and both the profile switch and a fast DNS failure reset
        // `stickyModifierState` — wiping the launch prelock before the
        // screenshot. The legacy detail-start key forces the dock without
        // a session, which is the focused-input-dock path this capture
        // needs. Spec 011: the modifiers render on the shared accessory
        // strip, so no Direct-mode entry is required.
        let app = launchAppPrelockingControlWithSampleProfile(mode: mode)

        XCTAssertTrue(
            app.buttons["Control modifier, locked"].waitForExistence(timeout: 8),
            "Control modifier must be locked via prelock hook"
        )

        try saveScreen(named: "11-modifier-locked-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — PiP Watch disabled

    func testPiPWatchDisabled_light() throws {
        try runPiPWatchDisabled(mode: .light, deviceTag: "iphone")
    }

    func testPiPWatchDisabled_dark() throws {
        try runPiPWatchDisabled(mode: .dark, deviceTag: "iphone")
    }

    private func runPiPWatchDisabled(mode: ColorMode, deviceTag: String) throws {
        let app = launchAppWithSampleProfile(mode: mode)
        openFirstConnectionCardIfPresent(app: app)

        XCTAssertTrue(
            waitForStableElement(
                in: app,
                identifier: "naru.session.tools.menu",
                timeout: 8
            ).exists,
            "PiP Watch must stay behind the Session tools menu before a session is active"
        )
        XCTAssertFalse(
            app.buttons["PiP Watch"].exists,
            "PiP Watch must not be a permanent primary button with no session"
        )

        try saveScreen(named: "13-pip-disabled-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — incoming clipboard banner (state #12)

    func testIncomingClipboardBanner_light() throws {
        try runIncomingClipboardBanner(mode: .light, deviceTag: "iphone")
    }

    func testIncomingClipboardBanner_dark() throws {
        try runIncomingClipboardBanner(mode: .dark, deviceTag: "iphone")
    }

    private func runIncomingClipboardBanner(mode: ColorMode, deviceTag: String) throws {
        // Closes UX punch-list coverage gap: incoming-clipboard
        // banner accept/dismiss visual was never captured.  Drive
        // through the `incoming-clipboard` fixture which seeds an
        // .active session and calls `recordIncomingClipboard(...)`
        // post-init, so the banner mounts above the dock at first
        // paint.
        let app = launchAppWithFixture(.incomingClipboard, mode: mode)

        XCTAssertTrue(
            app.otherElements["naru.input.incomingClipboard.preview"]
                .waitForExistence(timeout: 8) ||
            app.staticTexts["Remote clipboard ready"].waitForExistence(timeout: 4),
            "Incoming clipboard banner must be visible"
        )

        try saveScreen(named: "12-incoming-clipboard-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — diagnostic error (DNS) — state #15

    func testDiagnosticErrorDNS_light() throws {
        try runDiagnosticErrorDNS(mode: .light, deviceTag: "iphone")
    }

    func testDiagnosticErrorDNS_dark() throws {
        try runDiagnosticErrorDNS(mode: .dark, deviceTag: "iphone")
    }

    private func runDiagnosticErrorDNS(mode: ColorMode, deviceTag: String) throws {
        // Closes UX punch-list coverage gap: connection error states
        // (DNS fails, RFB handshake fails, auth required) were never
        // captured.  Start with the most-common case — DNS failure
        // — using the `diagnostic-error-dns` fixture, which seeds a
        // `ConnectionDiagnosticRun` whose only stage is the catalog
        // DNS-failed result.
        let app = launchAppWithFixture(.diagnosticErrorDNS, mode: mode)

        // The Operation rework moved stage rows off the first paint and
        // behind the persistent corner capsule — the failed row now lives
        // in the medium-detent diagnostics sheet the capsule presents.
        let corner = app.buttons["naru.session.diagnostics.corner"].firstMatch
        XCTAssertTrue(
            corner.waitForExistence(timeout: 8),
            "Diagnostics corner must be mounted on the Operation surface"
        )
        corner.tap()

        // Sheet rows use `.accessibilityElement(children: .combine)`, so the
        // title is never a standalone static text — match by containment.
        let failedRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "MagicDNS did not resolve")
        ).firstMatch
        XCTAssertTrue(
            failedRow.waitForExistence(timeout: 8) ||
            app.otherElements.matching(
                NSPredicate(format: "label CONTAINS %@", "MagicDNS did not resolve")
            ).firstMatch.waitForExistence(timeout: 4),
            "Failed-stage row must be visible in the diagnostics sheet"
        )

        try saveScreen(named: "15-diagnostic-error-dns-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — live session, widescreen hero viewport (state #16)

    func testSessionActiveWidescreen_light() throws {
        try runSessionActiveWidescreen(mode: .light, deviceTag: "iphone")
    }

    func testSessionActiveWidescreen_dark() throws {
        try runSessionActiveWidescreen(mode: .dark, deviceTag: "iphone")
    }

    func testSessionActiveTrackpadCursor_light() throws {
        try runSessionActiveTrackpadCursor(mode: .light, deviceTag: "iphone")
    }

    func testSessionActiveTrackpadCursor_dark() throws {
        try runSessionActiveTrackpadCursor(mode: .dark, deviceTag: "iphone")
    }

    func testSessionActiveTypeMode_light() throws {
        try runSessionActiveTypeMode(mode: .light, deviceTag: "iphone")
    }

    func testSessionActiveTypeMode_dark() throws {
        try runSessionActiveTypeMode(mode: .dark, deviceTag: "iphone")
    }

    private func runSessionActiveWidescreen(
        mode: ColorMode,
        deviceTag: String,
        terminateAfterCapture: Bool = false
    ) throws {
        // Screen-first hero viewport (spec 003 FR-001): an `.active`
        // session carrying a real 16:9 framebuffer.  Confirms the remote
        // screen renders at the server's true aspect ratio and — once the
        // hero layout lands — dominates the detail column.  The Compose
        // quick-key strip (Esc / Tab / ⌃C / ↑ / ↓) is also visible here
        // because the session is active (FR-013), so this is the canonical
        // capture for grading the live-session surface against Google
        // Remote Desktop.
        let app = launchAppWithFixture(.sessionActiveWidescreen, mode: mode)

        let composeReveal = waitForCompactComposeReveal(in: app, timeout: 8)
        XCTAssertTrue(
            composeReveal.exists,
            "Active-session compact compose affordance must be reachable"
        )
        revealSessionControlsIfNeeded(app: app)
        XCTAssertTrue(
            waitForStableElement(
                in: app,
                identifier: "naru.session.tools.menu",
                timeout: 4
            ).exists,
            "Active-session immersive controls must expose secondary stream and PiP controls from one Session tools menu"
        )
        XCTAssertFalse(
            app.buttons["naru.session.checks"].exists,
            "Active-session immersive controls must not keep Checks as a permanent primary button"
        )
        XCTAssertTrue(
            waitForStableElement(
                in: app,
                identifier: "naru.input.mac-controls.menu",
                timeout: 4
            ).exists,
            "Active-session compact dock must keep Mac controls reachable from a menu"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["naru.input.mac-controls"].exists,
            "Active-session compact dock must not permanently reserve height for the Mac controls strip"
        )

        sleep(3)

        try saveScreen(named: "16-session-active-widescreen-\(deviceTag)-\(mode.suffix).png")

        composeReveal.tap()
        let compactEditor = waitForRemoteInputEditor(in: app, timeout: 4)
        XCTAssertTrue(
            compactEditor.exists,
            "Active-session compact compose field must expand from the affordance"
        )
        compactEditor.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 5),
            "System keyboard must rise from the compact live-session input field"
        )

        let modeToggle = waitForStableElement(
            in: app,
            identifier: "naru.input.mode-toggle",
            timeout: 3
        )
        XCTAssertTrue(
            modeToggle.isHittable,
            "Keyboard system chrome must not cover the one-tap Type/Compose mode switch."
        )

        try saveScreen(named: "17-session-active-keyboard-\(deviceTag)-\(mode.suffix).png")

        if terminateAfterCapture {
            app.terminate()
        }
    }

    private func runSessionActiveTypeMode(
        mode: ColorMode,
        deviceTag: String,
        terminateAfterCapture: Bool = false
    ) throws {
        // Spec 011: Type (type-through) is the default dock surface for
        // an active session. The floating idle strip offers one-tap
        // "Type"; the compact editor takes the reserved inset, the
        // hardware-key responder rides along, and the mode stays one
        // tap from Compose.
        let app = launchAppWithFixture(
            .sessionActiveWidescreen,
            mode: mode,
            suppressDirectWarning: true
        )

        let typeReveal = waitForStableElement(
            in: app,
            identifier: "naru.input.type-reveal",
            timeout: 8
        )
        XCTAssertTrue(
            typeReveal.exists,
            "The active-session floating strip must offer one-tap Type."
        )
        typeReveal.tap()

        let compactEditor = waitForRemoteInputEditor(in: app, timeout: 4)
        XCTAssertTrue(
            compactEditor.exists,
            "Type mode must open the compact editor in the reserved inset."
        )
        XCTAssertTrue(
            waitForStableElement(
                in: app,
                identifier: "naru.input.mode-toggle",
                timeout: 4
            ).exists,
            "Type mode must keep Compose one tap away."
        )

        try saveScreen(named: "19-session-active-type-\(deviceTag)-\(mode.suffix).png")

        if terminateAfterCapture {
            app.terminate()
        }
    }

    private func runSessionActiveTrackpadCursor(
        mode: ColorMode,
        deviceTag: String,
        terminateAfterCapture: Bool = false
    ) throws {
        let app = launchAppWithFixture(.sessionActiveTrackpadCursor, mode: mode)

        XCTAssertTrue(
            waitForCompactComposeReveal(in: app, timeout: 8).exists,
            "Active-session compact compose affordance must be reachable"
        )

        sleep(3)

        try saveScreen(named: "18-session-active-trackpad-cursor-\(deviceTag)-\(mode.suffix).png")

        if terminateAfterCapture {
            app.terminate()
        }
    }

    // MARK: - iPhone — sidebar with multiple profiles

    func testSidebarMultipleProfiles_light() throws {
        try runSidebarMultipleProfiles(mode: .light, deviceTag: "iphone")
    }

    func testSidebarMultipleProfiles_dark() throws {
        try runSidebarMultipleProfiles(mode: .dark, deviceTag: "iphone")
    }

    private func runSidebarMultipleProfiles(mode: ColorMode, deviceTag: String) throws {
        let app = launchApp(
            mode: mode,
            seedProfiles: [
                SeedProfile(
                    displayName: "Studio Mac",
                    host: "studio.tailnet.ts.net",
                    hostKind: "magicDNS"
                ),
                SeedProfile(
                    displayName: "Office Linux",
                    host: "office.tailnet.ts.net",
                    hostKind: "magicDNS"
                ),
                SeedProfile(
                    displayName: "Home NUC",
                    host: "10.0.0.42",
                    hostKind: "privateAddress"
                ),
                SeedProfile(
                    displayName: "Public test",
                    host: "203.0.113.5",
                    hostKind: "advancedManualPublicEndpoint"
                )
            ]
        )

        XCTAssertTrue(
            app.staticTexts["Connections"].waitForExistence(timeout: 8),
            "Connection grid should display seeded profiles after launch"
        )
        XCTAssertTrue(app.staticTexts["Studio Mac"].waitForExistence(timeout: 4))

        try saveScreen(named: "14-connection-grid-multiple-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — grid with previews and reachability states (state #14b)

    func testSidebarMultipleProfilesWithVerdicts_light() throws {
        try runSidebarMultipleProfilesWithVerdicts(mode: .light, deviceTag: "iphone")
    }

    func testSidebarMultipleProfilesWithVerdicts_dark() throws {
        try runSidebarMultipleProfilesWithVerdicts(mode: .dark, deviceTag: "iphone")
    }

    func testStoreIPadConnectionGridWithVerdicts_light() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        try runSidebarMultipleProfilesWithVerdicts(
            mode: .light,
            deviceTag: "ipad-landscape"
        )
    }

    private func runSidebarMultipleProfilesWithVerdicts(mode: ColorMode, deviceTag: String) throws {
        // Fixture pre-populates both last diagnostic verdicts and the
        // launch reachability states that now drive connection-grid
        // card badges (reachable / checking / password / unreachable /
        // unknown) without waiting on real network probes.
        let app = launchAppWithFixture(.sidebarWithVerdicts, mode: mode)

        XCTAssertTrue(
            app.staticTexts["Connections"].waitForExistence(timeout: 8),
            "Connection grid should display fixture profiles after launch"
        )
        XCTAssertTrue(app.staticTexts["Studio Mac"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts["Reachable"].waitForExistence(timeout: 4),
            "Fixture should render a reachable grid badge"
        )
        XCTAssertTrue(
            app.images["naru.connection.grid.preview.thumbnail"].firstMatch.waitForExistence(timeout: 4)
                || app.otherElements["naru.connection.grid.preview.thumbnail"].firstMatch.waitForExistence(timeout: 1),
            "Fixture should render at least one stored preview thumbnail"
        )

        try saveScreen(named: "14-connection-grid-multiple-with-verdicts-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPad — graceful scaling

    func testIPadStates() throws {
        // Capture each iPad state in BOTH portrait and landscape so
        // the audit can grade iPad layout in both orientations
        // (closes UX punch-list #206).  PR #36 fixed the rotation
        // metadata so landscape PNGs are no longer 90° off.
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            let orientationTag: String
            switch orientation {
            case .portrait: orientationTag = "portrait"
            case .landscapeLeft, .landscapeRight: orientationTag = "landscape"
            default: orientationTag = "portrait"
            }

            for mode in [ColorMode.light, ColorMode.dark] {
                XCUIDevice.shared.orientation = orientation

                // State 1 — empty state
                do {
                    let app = launchApp(mode: mode)
                    XCTAssertTrue(app.buttons["naru.home.empty.addProfile"].waitForExistence(timeout: 8))
                    try saveScreen(named: "01-firstlaunch-ipad-\(orientationTag)-\(mode.suffix).png")
                    app.terminate()
                }

                // State 4 — profile selected (pre-seeded via JSON)
                do {
                    let app = launchApp(
                        mode: mode,
                        seedProfiles: [
                            SeedProfile(
                                displayName: "Studio Mac",
                                host: "studio.tailnet.ts.net"
                            )
                        ]
                    )
                    XCTAssertTrue(app.staticTexts["Connections"].waitForExistence(timeout: 8))
                    try saveScreen(named: "04-connection-grid-ipad-\(orientationTag)-\(mode.suffix).png")
                    app.terminate()
                }

                // State 7 — compose with text
                do {
                    let app = launchAppWithSampleProfile(mode: mode)
                    openFirstConnectionCardIfPresent(app: app)
                    let editor = app.textViews["Remote input text"]
                    XCTAssertTrue(editor.waitForExistence(timeout: 8))
                    // Same stabilization as runComposeDockWithText — typeText
                    // raced the async first-responder handoff on the reworked
                    // Operation surface (2026-07-12 flake).
                    editor.tap()
                    _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
                    enterStoreComposeText(
                        "안녕하세요 · Hello · こんにちは",
                        into: editor,
                        in: app
                    )
                    try saveScreen(named: "07-compose-text-ipad-\(orientationTag)-\(mode.suffix).png")
                    app.terminate()
                }

                // State 8 — shared accessory key strip
                do {
                    let app = launchAppSuppressingDirectWarningWithSampleProfile(mode: mode)
                    openFirstConnectionCardIfPresent(app: app)
                    XCTAssertTrue(
                        waitForStableElement(
                            in: app,
                            identifier: "naru.input.accessory.strip",
                            timeout: 8
                        ).exists,
                        "The accessory strip must render above the editor on iPad too."
                    )
                    try saveScreen(named: "08-accessory-strip-ipad-\(orientationTag)-\(mode.suffix).png")
                    app.terminate()
                }

                // States 16/17 — active session and keyboard-expanded Compose
                try runSessionActiveWidescreen(
                    mode: mode,
                    deviceTag: "ipad-\(orientationTag)",
                    terminateAfterCapture: true
                )

                // State 18 — active trackpad cursor surface
                try runSessionActiveTrackpadCursor(
                    mode: mode,
                    deviceTag: "ipad-\(orientationTag)",
                    terminateAfterCapture: true
                )
            }
        }
    }

    // MARK: - Helpers — launching

    private enum ColorMode {
        case light
        case dark

        var suffix: String {
            switch self {
            case .light: return "light"
            case .dark: return "dark"
            }
        }
    }

    private func launchApp(
        mode: ColorMode,
        seedProfiles: [SeedProfile] = [],
        forceInputDock: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uxaudit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        if forceInputDock {
            // Input-dock screenshots drive Compose/Direct on a selected
            // profile without a live socket; the dock is otherwise a
            // session-only surface (see NaruRemoteAppShell.showsInputDock).
            app.launchEnvironment["NARU_TEST_FORCE_INPUT_DOCK"] = "1"
        }
        if !seedProfiles.isEmpty {
            try? writeSeedProfiles(seedProfiles, to: storeURL)
        }
        applyColorMode(mode, to: app)
        app.launch()
        return app
    }

    private func launchAppSuppressingDirectWarning(mode: ColorMode) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uxaudit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        applyColorMode(mode, to: app)
        app.launch()
        return app
    }

    private func launchAppWithSampleProfile(mode: ColorMode) -> XCUIApplication {
        launchApp(
            mode: mode,
            seedProfiles: [
                SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")
            ],
            forceInputDock: true
        )
    }

    private func launchAppSuppressingDirectWarningWithSampleProfile(mode: ColorMode) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uxaudit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        app.launchEnvironment["NARU_TEST_FORCE_INPUT_DOCK"] = "1"
        try? writeSeedProfiles(
            [SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")],
            to: storeURL
        )
        applyColorMode(mode, to: app)
        app.launch()
        return app
    }

    /// Subset of `UXAuditFixtureToken` mirrored into the UITest
    /// target — the production enum lives in
    /// `NaruRemote/iOSApp/UXAuditFixtures.swift` and is not visible
    /// here because UITests don't link the iOS-app sources.
    /// Keep these raw values in sync with that enum.
    private enum FixtureToken: String {
        case diagnosticsPopulated = "diagnostics-populated"
        case diagnosticErrorDNS = "diagnostic-error-dns"
        case incomingClipboard = "incoming-clipboard"
        case sidebarWithVerdicts = "sidebar-with-verdicts"
        case sessionActiveWidescreen = "session-active-widescreen"
        case sessionActiveTrackpadCursor = "session-active-trackpad-cursor"
    }

    /// Launch the app with a `NARU_TEST_FIXTURE_SNAPSHOT` token that
    /// drives the model to a deterministic synthetic state — see
    /// `UXAuditFixtures.swift`.
    private func launchAppWithFixture(
        _ token: FixtureToken,
        mode: ColorMode,
        suppressDirectWarning: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uxaudit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = token.rawValue
        if token == .diagnosticsPopulated || token == .diagnosticErrorDNS {
            app.launchEnvironment["NARU_TEST_START_OPERATION_SURFACE"] = "1"
        }
        if suppressDirectWarning {
            app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        }
        applyColorMode(mode, to: app)
        app.launch()
        return app
    }

    private func launchAppPrelockingControl(mode: ColorMode) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uxaudit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        app.launchEnvironment["NARU_TEST_PRELOCK_MODIFIERS"] = "control"
        applyColorMode(mode, to: app)
        app.launch()
        return app
    }

    private func launchAppPrelockingControlWithSampleProfile(mode: ColorMode) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uxaudit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        app.launchEnvironment["NARU_TEST_PRELOCK_MODIFIERS"] = "control"
        // Detail-start + forced dock: the prelock keyboard must be
        // screenshot-able WITHOUT starting a real connect, because any
        // session reset wipes the locked modifier state.
        app.launchEnvironment["NARU_TEST_START_PROFILE_DETAIL"] = "1"
        try? writeSeedProfiles(
            [SeedProfile(displayName: "Studio Mac", host: "studio.tailnet.ts.net")],
            to: storeURL
        )
        applyColorMode(mode, to: app)
        app.launch()
        return app
    }

    /// Plain-data shape for pre-seeding the profile store JSON file
    /// used by `FileConnectionProfilePersistence.loadProfiles`.  We
    /// intentionally write the JSON ourselves rather than importing
    /// `NaruRemoteCore` into the UITest target — the existing
    /// `naru.profile.add` UI path is the contract we are testing
    /// elsewhere; here we just need a profile to land on detail.
    fileprivate struct SeedProfile {
        let id: UUID
        let displayName: String
        let host: String
        let port: Int
        let hostKind: String  // "magicDNS" | "privateAddress" | "advancedManualPublicEndpoint"
        /// Points at no injected Keychain item on purpose. Card-driven UI
        /// audits must reach a deterministic Operation failure immediately,
        /// not leave XCTest waiting for a real DNS/TCP timeout.
        let credentialRef: String

        init(displayName: String, host: String, port: Int = 5900, hostKind: String = "magicDNS") {
            let id = UUID()
            self.id = id
            self.displayName = displayName
            self.host = host
            self.port = port
            self.hostKind = hostKind
            self.credentialRef = "vnc-password:\(id.uuidString)"
        }
    }

    private func writeSeedProfiles(_ profiles: [SeedProfile], to fileURL: URL) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        let array: [[String: Any]] = profiles.map { p in
            [
                "id": p.id.uuidString,
                "displayName": p.displayName,
                "host": p.host,
                "port": p.port,
                "hostKind": p.hostKind,
                "credentialRef": p.credentialRef,
                "favorite": false,
                "allowsPiPWatch": true
            ]
        }
        let data = try JSONSerialization.data(
            withJSONObject: array,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    private func applyColorMode(_ mode: ColorMode, to app: XCUIApplication) {
        // `-AppleInterfaceStyle Dark` is a macOS user-default key and
        // is silently ignored on iOS (UX punch-list #001).  The
        // production app reads `NARU_TEST_OVERRIDE_INTERFACE_STYLE`
        // on launch and forces the root scene's color scheme via
        // `.preferredColorScheme(...)` — see
        // `NaruRemoteApplication.testOverrideColorScheme()`.
        switch mode {
        case .light:
            app.launchEnvironment["NARU_TEST_OVERRIDE_INTERFACE_STYLE"] = "Light"
        case .dark:
            app.launchEnvironment["NARU_TEST_OVERRIDE_INTERFACE_STYLE"] = "Dark"
        }
    }

    // MARK: - Helpers — navigation

    /// On compact width the sidebar may be collapsed.  Tap the
    /// system back-button on the navigation bar if it exists.
    private func openFirstConnectionCardIfPresent(app: XCUIApplication) {
        let gridHeading = app.staticTexts["Connections"]
        guard gridHeading.waitForExistence(timeout: 3) else {
            return
        }

        let firstCard = app.buttons["naru.connection.grid.card"].firstMatch
        XCTAssertTrue(
            firstCard.waitForExistence(timeout: 4),
            "Connection grid card must be tappable before entering session detail"
        )
        firstCard.tap()
    }

    /// A fresh App Store capture simulator can show the one-time iOS
    /// QuickPath tutorial over the system keyboard after the first typed text.
    /// Dismiss that system-owned onboarding so screenshots show the product UI.
    private func dismissSystemKeyboardOnboardingIfPresent(in app: XCUIApplication) {
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 2) {
            continueButton.tap()
            _ = continueButton.waitForNonExistence(timeout: 2)
        }
    }

    private func enterStoreComposeText(
        _ text: String,
        into editor: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        editor.tap()
        editor.typeText(text)
        dismissSystemKeyboardOnboardingIfPresent(in: app)

        // On a pristine simulator the first type event opens QuickPath
        // onboarding instead of reaching the editor. Re-focus and type once
        // more only when that system sheet consumed the original input.
        let currentValue = editor.value as? String ?? ""
        if currentValue.isEmpty {
            editor.tap()
            editor.typeText(text)
        }

        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: editor)
        let result = XCTWaiter().wait(for: [expectation], timeout: 4)
        XCTAssertEqual(
            result,
            .completed,
            "Store Compose capture must visibly contain its multilingual text.",
            file: file,
            line: line
        )
    }


    /// Match by accessibility label so the audit stays anchored to
    /// visible UI copy rather than SwiftUI container identifier
    /// reshuffling.
    private func findChecksButton(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label == 'Checks'")
        return app.buttons.matching(predicate).firstMatch
    }

    private func waitForRemoteInputEditor(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement {
        let textView = app.textViews["Remote input text"]
        if textView.waitForExistence(timeout: timeout) {
            return textView
        }
        let textField = app.textFields["Remote input text"]
        _ = textField.waitForExistence(timeout: 1)
        return textField
    }

    private func waitForCompactComposeReveal(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement {
        let button = app.buttons["naru.input.compose-reveal"]
        if button.waitForExistence(timeout: timeout) {
            return button
        }

        let anyElement = app.descendants(matching: .any)["naru.input.compose-reveal"]
        _ = anyElement.waitForExistence(timeout: 1)
        return anyElement
    }

    private func waitForStableElement(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval
    ) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: timeout) {
            return button
        }

        let anyElement = app.descendants(matching: .any)[identifier]
        _ = anyElement.waitForExistence(timeout: 1)
        return anyElement
    }

    private func revealSessionControlsIfNeeded(app: XCUIApplication) {
        // The immersive bar mounts VISIBLE and auto-hides 2.4 s later, so a
        // bare "tools menu exists" check can pass during the bar's dismiss
        // transition and leave the caller waiting on chrome that is already
        // gone (2026-07-12 widescreen audit failure).  The deterministic
        // sequence is the opposite: wait for the auto-hide to produce the
        // reveal handle, then tap it — a user-explicit reveal pins the bar
        // open (no auto-hide timer), which is exactly what a screenshot needs.
        let reveal = app.buttons["naru.session.controls.reveal"].firstMatch
        if reveal.waitForExistence(timeout: 6) {
            reveal.tap()
            return
        }

        // Reveal never appeared: the bar is being held open (VoiceOver or
        // an interaction suppressed the timer). If the menu is there, done;
        // otherwise fall back to coordinate taps along the top strip.
        if app.buttons["naru.session.tools.menu"].exists ||
            app.descendants(matching: .any)["naru.session.tools.menu"].exists {
            return
        }
        for y in [0.075, 0.095, 0.12] {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y)).tap()
            let menu = waitForStableElement(
                in: app,
                identifier: "naru.session.tools.menu",
                timeout: 1
            )
            if menu.exists { return }
        }
    }

    // MARK: - Helpers — saving

    private func saveScreen(named filename: String) throws {
        // `XCUIScreen.main.screenshot()` returns the framebuffer at
        // the device's portrait pixel orientation; rotated (landscape)
        // screenshots come back 90° off — UX punch-list #002.
        // Re-orient the captured `UIImage` via the current device
        // orientation before encoding to PNG so the saved file reads
        // upright.
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = filename
        add(attachment)

        let fm = FileManager.default
        try? fm.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )

        let pngData = orientedPngData(from: screenshot)

        let url = URL(fileURLWithPath: outputDirectory)
            .appendingPathComponent(filename)
        try pngData.write(to: url)

        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "Screenshot \(filename) must not be empty")
    }

    /// Rotates the simulator screenshot so the PNG reads upright in
    /// the current interface orientation.  `XCUIScreen.main.screenshot()`
    /// always returns the framebuffer at the device's native
    /// portrait pixel orientation, so a landscape capture has the
    /// status bar on the side.  We map the simulator orientation to
    /// `UIImage.Orientation` and re-encode through `UIGraphicsImageRenderer`
    /// so the resulting PNG is byte-rotated, not metadata-rotated.
    private func orientedPngData(from screenshot: XCUIScreenshot) -> Data {
        #if canImport(UIKit)
        let cg = screenshot.image.cgImage
        let scale = screenshot.image.scale
        let orientation: UIImage.Orientation
        switch XCUIDevice.shared.orientation {
        case .landscapeLeft:
            // `.landscapeLeft` = home button on the right edge of the
            // device.  Empirically the framebuffer arrives such that
            // tagging it with `.left` re-renders content upright with
            // the status bar on top of the landscape PNG.
            orientation = .left
        case .landscapeRight:
            orientation = .right
        case .portraitUpsideDown:
            orientation = .down
        default:
            orientation = .up
        }
        guard orientation != .up, let cg else {
            return screenshot.pngRepresentation
        }
        let oriented = UIImage(cgImage: cg, scale: scale, orientation: orientation)
        let outSize = oriented.size
        let renderer = UIGraphicsImageRenderer(size: outSize)
        let rendered = renderer.image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: outSize))
        }
        return rendered.pngData() ?? screenshot.pngRepresentation
        #else
        return screenshot.pngRepresentation
        #endif
    }
}

private extension XCUIElement {
    /// Tap when `condition` holds; otherwise skip without failing
    /// the test.  Used for "dismiss keyboard if a Return key is
    /// exposed by SwiftUI's toolbar" — a fragile a11y target.
    func tap(if condition: (XCUIElement) -> Bool) {
        if condition(self) {
            tap()
        }
    }

    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
