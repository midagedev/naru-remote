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

        // Spec 013: a connection that fails (this seeded host does not
        // resolve) returns to the host list on its own — there is no
        // recovery screen between the list and remote control — and the
        // failing card carries the reason plus a Reconnect action.
        openFirstConnectionCardIfPresent(app: app)
        XCTAssertTrue(
            app.buttons["naru.connection.grid.card"].firstMatch.waitForExistence(timeout: 10),
            "A failed connection must return to the host list by itself."
        )
        XCTAssertFalse(
            app.staticTexts["naru.operation.recovery"].exists,
            "The recovery card is retired (spec 013)."
        )
        let reconnect = app.buttons["naru.connection.grid.reconnect"].firstMatch
        XCTAssertTrue(
            reconnect.waitForExistence(timeout: 6),
            "The failing host card must offer Reconnect inline."
        )
        try saveScreen(named: "04b-connection-grid-failed-\(deviceTag)-\(mode.suffix).png")

        // State 5: diagnostics populated.  Closes UX punch-list #007
        // — previously this state re-launched the app and tapped the
        // Checks pill, but `runConnectionChecks()` only seeds two
        // stages and the second flips to .running asynchronously, so
        // the screenshot landed before any rows rendered and was
        // byte-identical to #04.  Drive the state through the
        // `NARU_TEST_FIXTURE_SNAPSHOT=diagnostics-populated` hook
        // instead — four deterministic stages including the running
        // authentication row.
        // Spec 013 moved the diagnostics entry point onto the host card's
        // actions menu — the capsule now belongs to a live session only.
        let diagnosticsApp = launchAppWithFixture(.diagnosticsPopulated, mode: mode)
        openDiagnosticsFromFirstCard(app: diagnosticsApp)
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

        let fnRow = app.descendants(matching: .any)["naru.input.accessory.fn-row"].firstMatch
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
        // Spec 013: diagnostics for a host that is not in session are
        // reached from the host card's actions menu, not from a surface
        // between the list and remote control.
        openDiagnosticsFromFirstCard(app: app)

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

    // MARK: - App Store marketing captures
    //
    // Five slots, one story each, in the order they should appear on the
    // product page:
    //
    //   1 hosts        — every computer on the tailnet, one tap away
    //   2 session      — the remote screen live on the phone
    //   3 compose      — Hangul composed locally, sent whole
    //   4 function row — Esc / Tab / ⌃C / F-keys over a live session
    //   5 diagnostics  — when it does not connect, which stage failed
    //
    // These are separate from the audit captures above because the two
    // jobs disagree: an audit frame wants every failure badge visible at
    // once, a store frame wants one healthy, legible claim.  Both device
    // families run the same five methods; `storeDeviceTag` names the
    // output and `saveStoreScreen` refuses a capture whose pixel size is
    // not one App Store Connect accepts for that family, so a wrong
    // simulator fails here instead of at upload.

    func testStoreHostList_light() throws {
        try runStoreHostList(mode: .light)
    }

    func testStoreHostList_dark() throws {
        try runStoreHostList(mode: .dark)
    }

    func testStoreLiveSession_light() throws {
        try runStoreLiveSession(mode: .light)
    }

    func testStoreLiveSession_dark() throws {
        try runStoreLiveSession(mode: .dark)
    }

    func testStoreKoreanCompose_light() throws {
        try runStoreKoreanCompose(mode: .light)
    }

    func testStoreKoreanCompose_dark() throws {
        try runStoreKoreanCompose(mode: .dark)
    }

    func testStoreFunctionRow_light() throws {
        try runStoreFunctionRow(mode: .light)
    }

    func testStoreFunctionRow_dark() throws {
        try runStoreFunctionRow(mode: .dark)
    }

    func testStoreDiagnosticsPassed_light() throws {
        try runStoreDiagnosticsPassed(mode: .light)
    }

    func testStoreDiagnosticsPassed_dark() throws {
        try runStoreDiagnosticsPassed(mode: .dark)
    }

    private func runStoreHostList(mode: ColorMode) throws {
        applyStoreOrientation()
        let app = launchStoreApp(.storeConnectionGrid, mode: mode)

        XCTAssertTrue(
            app.staticTexts["Connections"].waitForExistence(timeout: 8),
            "Store host-list capture needs the connection grid"
        )
        XCTAssertTrue(app.staticTexts["Studio Mac"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts["Reachable"].firstMatch.waitForExistence(timeout: 4),
            "Store host-list capture must show healthy reachability, not a probe in flight"
        )
        XCTAssertFalse(
            app.staticTexts["Unreachable"].exists,
            "Store slot 1 must not advertise a broken connection"
        )

        try saveStoreScreen(slot: 1, named: "hosts", mode: mode)
    }

    private func runStoreLiveSession(mode: ColorMode) throws {
        // Landscape on the phone too, unlike every other slot. The hero
        // viewport is aspect-FILL by design — letterboxing a 16:9 desktop
        // into a portrait phone would leave it unreadably small — so a
        // portrait capture crops the remote screen mid-word. Slot 2's whole
        // claim is "your actual desktop, whole", so it gets the orientation
        // that can show it. Apple accepts either orientation per slot.
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launchStoreApp(.storeSessionActive, mode: mode)

        XCTAssertTrue(
            waitForCompactComposeReveal(in: app, timeout: 8).exists,
            "Store session capture needs the live-session dock mounted"
        )
        // A user-explicit reveal pins the session bar open, so the title,
        // quality chip and Session tools stay in frame for the capture
        // instead of racing the 2.4 s auto-hide.
        revealSessionControlsIfNeeded(app: app)
        XCTAssertTrue(
            waitForStableElement(in: app, identifier: "naru.session.tools.menu", timeout: 4).exists,
            "Store session capture should show the session chrome"
        )

        // Let the Metal view present a settled frame.
        sleep(3)

        try saveStoreScreen(slot: 2, named: "session", mode: mode)
    }

    private func runStoreKoreanCompose(mode: ColorMode) throws {
        applyStoreOrientation()
        // The draft text arrives on the fixture snapshot, not through
        // `typeText`: a store capture must not depend on the simulator's
        // IME state or on the one-time QuickPath sheet losing a race.
        let app = launchStoreApp(.storeSessionKoreanCompose, mode: mode)

        // A seeded non-empty draft already mounts the editor — the dock only
        // offers the compose-reveal affordance when there is no text to show.
        // Accept either entry so the capture does not depend on which one the
        // dock picks.
        var editor = waitForRemoteInputEditor(in: app, timeout: 6)
        if !editor.exists {
            let composeReveal = waitForCompactComposeReveal(in: app, timeout: 4)
            XCTAssertTrue(composeReveal.exists, "Store compose capture needs the compose affordance")
            composeReveal.tap()
            editor = waitForRemoteInputEditor(in: app, timeout: 4)
        }
        XCTAssertTrue(editor.exists, "Store compose capture needs the expanded editor")
        // Focus so the keyboard is in frame: the slot's claim is "you compose
        // this on the phone", which needs the keyboard visible.
        if !(app.keyboards.firstMatch.waitForExistence(timeout: 1)) {
            editor.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 4)
        }
        // The QuickPath tutorial rides on the keyboard's first appearance,
        // so it has to be dismissed after the keyboard, not before it.
        dismissSystemKeyboardOnboardingIfPresent(in: app)
        dismissSystemKeyboardOnboardingIfPresent(in: app)

        let predicate = NSPredicate(format: "value CONTAINS %@", "회의록")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: editor)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: 6),
            .completed,
            "Store slot 3 must visibly hold the seeded Hangul draft"
        )
        XCTAssertTrue(
            waitForStableElement(in: app, identifier: "naru.input.accessory.strip", timeout: 4).exists,
            "Store slot 3 should show the accessory strip riding above the editor"
        )
        switchToKoreanSoftKeyboardIfAvailable(in: app)
        hideSoftKeyboardForTabletCaptureIfNeeded(in: app)

        try saveStoreScreen(slot: 3, named: "compose-korean", mode: mode)
    }

    private func runStoreFunctionRow(mode: ColorMode) throws {
        applyStoreOrientation()
        // Unlike the audit strip capture (which forces the dock without a
        // session), the store slot shows the strip where a user meets it:
        // expanded over a live remote screen.
        let app = launchStoreApp(.storeSessionActive, mode: mode, suppressDirectWarning: true)

        let typeReveal = waitForStableElement(in: app, identifier: "naru.input.type-reveal", timeout: 8)
        XCTAssertTrue(typeReveal.exists, "Store function-row capture needs one-tap Type")
        typeReveal.tap()

        XCTAssertTrue(
            waitForRemoteInputEditor(in: app, timeout: 4).exists,
            "Type mode must open the compact editor before the Fn expansion"
        )
        // A pristine capture simulator shows the one-time QuickPath tutorial
        // where the keyboard belongs; left up, it eats the bottom half of
        // the frame (observed on the first store run).
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 4)
        dismissSystemKeyboardOnboardingIfPresent(in: app)
        // Korean here too: the strip's whole point is that these keys stay
        // reachable while an IME keyboard owns the bottom of the screen.
        switchToKoreanSoftKeyboardIfAvailable(in: app)

        let fnToggle = waitForStableElement(in: app, identifier: "naru.input.accessory.fn", timeout: 4)
        XCTAssertTrue(fnToggle.exists, "Store function-row capture needs the Fn toggle")
        fnToggle.tap()

        let fnRow = app.descendants(matching: .any)["naru.input.accessory.fn-row"].firstMatch
        if !fnRow.waitForExistence(timeout: 4) {
            // Same transient-status tap theft the audit capture guards
            // against; the expansion is local-only, so retrying it emits
            // no remote key event.
            fnToggle.tap()
        }
        XCTAssertTrue(
            fnRow.waitForExistence(timeout: 4),
            "Store slot 4 must show the expanded function row"
        )
        XCTAssertFalse(
            app.buttons["Continue"].exists,
            "The system QuickPath sheet must be gone before the store capture"
        )
        hideSoftKeyboardForTabletCaptureIfNeeded(in: app)
        XCTAssertTrue(
            fnRow.exists,
            "The function row must survive putting the soft keyboard away"
        )

        try saveStoreScreen(slot: 4, named: "function-row", mode: mode)
    }

    private func runStoreDiagnosticsPassed(mode: ColorMode) throws {
        applyStoreOrientation()
        let app = launchStoreApp(.storeDiagnosticsPassed, mode: mode)

        openDiagnosticsFromFirstCard(app: app)
        XCTAssertTrue(
            app.navigationBars["Diagnostics"].waitForExistence(timeout: 6),
            "Store diagnostics capture needs the diagnostics sheet"
        )
        XCTAssertTrue(
            app.staticTexts["Host resolved"].waitForExistence(timeout: 4),
            "Diagnostic rows must render before the capture"
        )
        XCTAssertTrue(
            app.staticTexts["First frame received"].waitForExistence(timeout: 4),
            "Store slot 5 must show a run that reached the first frame"
        )

        try saveStoreScreen(slot: 5, named: "diagnostics", mode: mode)
    }

    // MARK: - Helpers — App Store captures

    /// Launches a store fixture, telling it which remote-screen aspect this
    /// device wants (see `UXAuditFixtures.storeDesktop`).
    private func launchStoreApp(
        _ token: FixtureToken,
        mode: ColorMode,
        suppressDirectWarning: Bool = false
    ) -> XCUIApplication {
        launchAppWithFixture(
            token,
            mode: mode,
            suppressDirectWarning: suppressDirectWarning,
            desktopAspect: isStoreTabletCapture ? "tablet" : nil
        )
    }

    /// Tablet-only: put the soft keyboard away before the capture.
    ///
    /// On a 13" iPad the soft keyboard eats half the screen and squeezes the
    /// remote screen into a band the aspect-fill viewport then crops
    /// mid-glyph — and it is the wrong story besides: the iPad scenario this
    /// app is built for is an external keyboard and mouse, where the dock
    /// keeps its strip and the remote screen keeps the screen. The editor
    /// and its text stay mounted; only the keyboard leaves.
    ///
    /// No-op on iPhone, where the soft keyboard *is* the story.
    private func hideSoftKeyboardForTabletCaptureIfNeeded(in app: XCUIApplication) {
        guard isStoreTabletCapture else { return }
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }

        // `exists` outlives visibility: iPadOS keeps a zero-height keyboard
        // element parked below the window once it is down, and its dismiss
        // key is then unhittable. Ask geometry, not existence.
        func keyboardCoversScreen() -> Bool {
            let window = app.windows.firstMatch.frame
            let frame = keyboard.frame
            return frame.height > 1 && frame.intersects(window)
        }
        guard keyboardCoversScreen() else { return }

        // The dismiss key's accessibility label follows the *system*
        // language, not the keyboard's, so both spellings are tried; and it
        // is exposed as a key on some iPadOS versions and a button on
        // others.
        // Matched by label predicate, not by subscript: the dismiss key
        // carries only an accessibility label (no identifier), and
        // `buttons["..."]` matches identifiers.
        let labels = ["키보드 가리기", "Hide keyboard", "Hide Keyboard", "Dismiss", "키보드 숨기기"]
        for label in labels {
            let predicate = NSPredicate(format: "label == %@", label)
            for query in [app.buttons, app.keys] {
                let candidate = query.matching(predicate).firstMatch
                if candidate.exists, candidate.isHittable {
                    candidate.tap()
                    _ = keyboard.waitForNonExistence(timeout: 3)
                    if !keyboardCoversScreen() { return }
                }
            }
        }

        XCTFail(
            """
            The soft keyboard is still covering the tablet capture and no \
            dismiss key could be tapped. Keyboard element tree:
            \(keyboard.debugDescription)
            """
        )
    }

    /// Best effort: when the capture simulator has the Korean keyboard
    /// installed *after* English (see `docs/store-screenshots.md`), a globe
    /// tap puts 두벌식 on screen, so slot 3 shows the keyboard a Korean user
    /// actually composes with instead of a QWERTY under Hangul text.
    ///
    /// Deliberately non-fatal and deliberately not the source of the text:
    /// the draft comes from the fixture, so a simulator without the Korean
    /// keyboard still produces a usable — just less pointed — capture.
    /// Keeping English first in the keyboard list also keeps every other
    /// test's `typeText` on a Latin layout.
    private func switchToKoreanSoftKeyboardIfAvailable(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 4) else { return }

        // Idempotent on purpose: the soft-keyboard language is system state
        // that survives app launches, so a slot that runs after another
        // Korean capture already has 두벌식 up. Tapping the globe anyway
        // would cycle it away and make the capture depend on test order.
        if keyboard.keys["ㅁ"].exists { return }

        let globe = keyboard.buttons["Next keyboard"]
        guard globe.waitForExistence(timeout: 2) else { return }

        // The globe cycles the installed keyboards, so allow one extra tap
        // in case the first lands on Emoji.
        for _ in 0..<2 {
            guard globe.isHittable else { return }
            globe.tap()
            if keyboard.keys["ㅁ"].waitForExistence(timeout: 2) {
                return
            }
        }
    }

    /// Store PNGs live beside the audit tree, not inside it, so a
    /// screenshot sweep never mixes marketing frames into an audit set.
    private var storeOutputDirectory: String {
        URL(fileURLWithPath: outputDirectory)
            .deletingLastPathComponent()
            .appendingPathComponent("store", isDirectory: true)
            .path
    }

    /// iPhone is the canonical portrait design target (constitution §VI);
    /// the iPad slots are shot in landscape because that is where the
    /// external-keyboard-and-mouse story the iPad screenshots sell
    /// actually happens.
    private func applyStoreOrientation() {
        #if canImport(UIKit)
        XCUIDevice.shared.orientation = isStoreTabletCapture ? .landscapeLeft : .portrait
        #endif
    }

    private var isStoreTabletCapture: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    /// Names the store display family, not the simulator model — App
    /// Store Connect has one 6.9" iPhone slot and one 13" iPad slot, and
    /// `saveStoreScreen` proves the capture actually fits it.
    private var storeDeviceTag: String {
        isStoreTabletCapture ? "ipad13" : "iphone69"
    }

    private func saveStoreScreen(
        slot: Int,
        named name: String,
        mode: ColorMode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let filename = String(
            format: "store-%02d-%@-%@-%@.png",
            slot,
            name,
            storeDeviceTag,
            mode.suffix
        )
        try saveScreen(named: filename, in: storeOutputDirectory)
        assertStoreImageIsUploadable(filename, file: file, line: line)
    }

    /// Fails the capture when App Store Connect would reject the file: a
    /// pixel size that is not one of the accepted sizes for this display
    /// family, or a surviving alpha channel.  Without this the run is green
    /// and the rejection happens later, in the upload UI, with no hint about
    /// which simulator or which code path produced the file.
    private func assertStoreImageIsUploadable(
        _ filename: String,
        file: StaticString,
        line: UInt
    ) {
        #if canImport(UIKit)
        let url = URL(fileURLWithPath: storeOutputDirectory).appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)?.cgImage
        else {
            XCTFail("Store capture \(filename) could not be decoded", file: file, line: line)
            return
        }

        let size = [image.width, image.height].sorted()
        // App Store Connect, 2026-08: 6.9" iPhone accepts 1320×2868 or
        // 1290×2796; 13" iPad accepts 2064×2752 or 2048×2732. Either
        // orientation of each pair is allowed, hence the sorted compare.
        let accepted: [[Int]] = isStoreTabletCapture
            ? [[2064, 2752], [2048, 2732]]
            : [[1320, 2868], [1290, 2796]]
        XCTAssertTrue(
            accepted.contains(size),
            """
            Store capture \(filename) is \(image.width)×\(image.height), which App Store Connect \
            does not accept for the \(storeDeviceTag) slot. Expected one of \
            \(accepted.map { "\($0[0])×\($0[1])" }.joined(separator: " or ")) — \
            re-run on iPhone 17 Pro Max or iPad Pro 13-inch.
            """,
            file: file,
            line: line
        )

        // App Store Connect rejects screenshots carrying an alpha channel.
        let opaqueAlphaInfos: Set<CGImageAlphaInfo> = [.none, .noneSkipFirst, .noneSkipLast]
        XCTAssertTrue(
            opaqueAlphaInfos.contains(image.alphaInfo),
            """
            Store capture \(filename) still has an alpha channel \
            (\(image.alphaInfo.rawValue)); App Store Connect refuses those. The capture \
            path must render opaque — see `orientedPngData`.
            """,
            file: file,
            line: line
        )
        #endif
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
        case storeConnectionGrid = "store-connection-grid"
        case storeSessionActive = "store-session-active"
        case storeSessionKoreanCompose = "store-session-korean-compose"
        case storeDiagnosticsPassed = "store-diagnostics-passed"
    }

    /// Launch the app with a `NARU_TEST_FIXTURE_SNAPSHOT` token that
    /// drives the model to a deterministic synthetic state — see
    /// `UXAuditFixtures.swift`.
    private func launchAppWithFixture(
        _ token: FixtureToken,
        mode: ColorMode,
        suppressDirectWarning: Bool = false,
        desktopAspect: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uxaudit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = token.rawValue
        if let desktopAspect {
            app.launchEnvironment["NARU_TEST_FIXTURE_DESKTOP"] = desktopAspect
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
    /// Spec 013 entry point: open a host card's actions menu and tap
    /// Diagnostics. Replaces the retired Operation-surface capsule tap for
    /// hosts that are not in a live session.
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

    private func saveScreen(named filename: String, in directory: String? = nil) throws {
        let outputDirectory = directory ?? self.outputDirectory
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
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
        let rendered = renderer.image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: outSize))
        }
        // `format.opaque` is not enough: on a P3 device the renderer picks an
        // extended-range backing store and the encoded PNG keeps a
        // premultiplied alpha channel — which App Store Connect refuses, and
        // which every rotated capture (all landscape and all iPad store
        // shots) carried until this was pinned.  Re-encode through an
        // explicitly alpha-free bitmap instead of trusting the renderer.
        return alphaFreePngData(from: rendered)
            ?? rendered.pngData()
            ?? screenshot.pngRepresentation
        #else
        return screenshot.pngRepresentation
        #endif
    }

    #if canImport(UIKit)
    /// Re-encodes an image through a `noneSkipLast` bitmap, so the PNG has no
    /// alpha channel at all.
    private func alphaFreePngData(from image: UIImage) -> Data? {
        guard let source = image.cgImage else { return nil }
        guard let context = CGContext(
            data: nil,
            width: source.width,
            height: source.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: source.width, height: source.height)
        )
        guard let flattened = context.makeImage() else { return nil }
        return UIImage(cgImage: flattened).pngData()
    }
    #endif
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
