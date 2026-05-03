import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// Drives the simulator through the canonical Naru Remote screens and
/// saves PNGs for an offline UX & design audit.  No assertions on
/// visual quality — those happen in vision review.  Only sanity
/// assertions that the screenshots wrote out non-empty.
///
/// Output directory is hard-coded to the repo's `artifacts/` tree to
/// match `DirectKeystrokeKeyboardScreenshotsUITests` and friends.
/// TODO: parameterise once the screenshot loop is unified.
///
/// One test method per state-group, no shared mutable state, so the
/// run order is irrelevant and any single state can be exercised in
/// isolation via `-only-testing`.
@MainActor
final class UXAuditScreenshotsUITests: XCTestCase {

    private let outputDirectory = "/Users/hckim/repo/naru-remote/artifacts/screenshots/ux-audit"

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

        // On compact width (iPhone) the sidebar collapses into the
        // detail column; the "Add Profile" toolbar button only shows
        // when the sidebar is visible.  Open it via the back-link
        // navigation toolbar.
        revealSidebarIfNeeded(app: app)

        let addProfile = app.buttons["Add Profile"]
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

    // MARK: - iPhone — selected profile + diagnostics

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

        let checksButton = findChecksButton(in: app)
        XCTAssertTrue(
            checksButton.waitForExistence(timeout: 8),
            "Run Checks button must be visible with a profile selected"
        )

        // State 4: profile selected
        try saveScreen(named: "04-profile-selected-\(deviceTag)-\(mode.suffix).png")

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
        XCTAssertTrue(
            diagnosticsApp.staticTexts["Diagnostics"].waitForExistence(timeout: 8),
            "Diagnostics summary must be mounted"
        )
        // The fixture's first stage is "Host resolved" — wait for
        // it so we know the rows are mounted in the SwiftUI tree.
        XCTAssertTrue(
            diagnosticsApp.staticTexts["Host resolved"].waitForExistence(timeout: 4),
            "Diagnostic rows must render before screenshot"
        )
        // The DiagnosticSummaryView lives at the bottom of the
        // detail-column ScrollView, below SessionViewportView; on
        // iPhone it sits below the fold at first paint.  Scroll up
        // by swiping inside the detail content so the diagnostic
        // rows are actually visible in the captured PNG.
        let detail = diagnosticsApp.scrollViews.firstMatch
        if detail.exists {
            detail.swipeUp()
            detail.swipeUp()
        } else {
            diagnosticsApp.swipeUp()
            diagnosticsApp.swipeUp()
        }
        // Re-confirm a row is still visible after the scroll.
        _ = diagnosticsApp.staticTexts["Host resolved"].waitForExistence(timeout: 2)
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
        let app = launchApp(mode: mode)

        let editor = app.textViews["Remote input text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.tap()
        editor.typeText("Hello world")

        // State 7: compose mode with text typed, Send enabled.
        try saveScreen(named: "07-compose-text-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — direct mode pages

    func testDirectQwerty_light() throws {
        try runDirectMode(mode: .light, deviceTag: "iphone", page: .qwerty)
    }

    func testDirectQwerty_dark() throws {
        try runDirectMode(mode: .dark, deviceTag: "iphone", page: .qwerty)
    }

    func testDirectSpecial_light() throws {
        try runDirectMode(mode: .light, deviceTag: "iphone", page: .special)
    }

    func testDirectSpecial_dark() throws {
        try runDirectMode(mode: .dark, deviceTag: "iphone", page: .special)
    }

    private enum DirectPage { case qwerty, special }

    private func runDirectMode(mode: ColorMode, deviceTag: String, page: DirectPage) throws {
        let app = launchAppSuppressingDirectWarning(mode: mode)

        XCTAssertTrue(app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8))

        let directSegment = app.buttons["Direct"]
        XCTAssertTrue(directSegment.waitForExistence(timeout: 4))
        directSegment.tap()

        let qKey = app.buttons["Key q"]
        XCTAssertTrue(qKey.waitForExistence(timeout: 4))

        if page == .qwerty {
            try saveScreen(named: "08-direct-qwerty-\(deviceTag)-\(mode.suffix).png")
            return
        }

        let pageToggle = app.buttons["Switch keyboard page"]
        XCTAssertTrue(pageToggle.waitForExistence(timeout: 2))
        pageToggle.tap()

        XCTAssertTrue(app.buttons["Key f1"].waitForExistence(timeout: 4))
        try saveScreen(named: "09-direct-special-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — direct mode warning dialog

    func testDirectWarningDialog_light() throws {
        try runDirectWarningDialog(mode: .light, deviceTag: "iphone")
    }

    func testDirectWarningDialog_dark() throws {
        try runDirectWarningDialog(mode: .dark, deviceTag: "iphone")
    }

    private func runDirectWarningDialog(mode: ColorMode, deviceTag: String) throws {
        // Deliberately do NOT suppress the warning so we can capture
        // it on first Direct entry.
        let app = launchApp(mode: mode)

        let directSegment = app.buttons["Direct"]
        XCTAssertTrue(directSegment.waitForExistence(timeout: 8))
        directSegment.tap()

        let confirm = app.buttons["Got it"].firstMatch
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 4),
            "Direct-mode warning must show on first activation"
        )

        try saveScreen(named: "10-direct-warning-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — sticky modifier locked

    func testStickyModifierLocked_light() throws {
        try runStickyModifierLocked(mode: .light, deviceTag: "iphone")
    }

    func testStickyModifierLocked_dark() throws {
        try runStickyModifierLocked(mode: .dark, deviceTag: "iphone")
    }

    private func runStickyModifierLocked(mode: ColorMode, deviceTag: String) throws {
        let app = launchAppPrelockingControl(mode: mode)

        XCTAssertTrue(app.buttons["Key q"].waitForExistence(timeout: 8))

        let pageToggle = app.buttons["Switch keyboard page"]
        XCTAssertTrue(pageToggle.waitForExistence(timeout: 2))
        pageToggle.tap()

        XCTAssertTrue(
            app.buttons["Control modifier, locked"].waitForExistence(timeout: 4),
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
        let app = launchApp(mode: mode)

        let pip = app.buttons["PiP Watch"]
        XCTAssertTrue(pip.waitForExistence(timeout: 8))
        XCTAssertFalse(pip.isEnabled, "PiP Watch must be disabled with no session")

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

        XCTAssertTrue(
            app.staticTexts["MagicDNS did not resolve"].waitForExistence(timeout: 8),
            "Failed-stage row must be visible"
        )

        try saveScreen(named: "15-diagnostic-error-dns-\(deviceTag)-\(mode.suffix).png")
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

        // Wait for detail column to settle (auto-selected first
        // profile lands here on iPhone), then navigate back to the
        // sidebar so the screenshot shows the profile list.
        XCTAssertTrue(app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8))
        revealSidebarIfNeeded(app: app)
        XCTAssertTrue(
            app.staticTexts["Studio Mac"].waitForExistence(timeout: 4),
            "Sidebar should display seeded profiles after back-navigation"
        )

        try saveScreen(named: "14-sidebar-multiple-\(deviceTag)-\(mode.suffix).png")
    }

    // MARK: - iPhone — sidebar with per-profile diagnostic verdicts (state #14b)

    func testSidebarMultipleProfilesWithVerdicts_light() throws {
        try runSidebarMultipleProfilesWithVerdicts(mode: .light, deviceTag: "iphone")
    }

    func testSidebarMultipleProfilesWithVerdicts_dark() throws {
        try runSidebarMultipleProfilesWithVerdicts(mode: .dark, deviceTag: "iphone")
    }

    private func runSidebarMultipleProfilesWithVerdicts(mode: ColorMode, deviceTag: String) throws {
        // Closes UX punch-list #109.  The four profiles in the
        // `sidebar-with-verdicts` fixture deliberately mirror the
        // `runSidebarMultipleProfiles` seed (Studio Mac / Office Linux
        // / Home NUC / Public test) but pre-populate
        // `lastDiagnosticVerdict` with one of each color so the
        // colored leading status dots actually render in the captured
        // PNG (passed = green, warning = amber, failed = red, unknown
        // = gray).
        let app = launchAppWithFixture(.sidebarWithVerdicts, mode: mode)

        XCTAssertTrue(app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8))
        revealSidebarIfNeeded(app: app)
        XCTAssertTrue(
            app.staticTexts["Studio Mac"].waitForExistence(timeout: 4),
            "Sidebar should display fixture profiles after back-navigation"
        )

        try saveScreen(named: "14-sidebar-multiple-with-verdicts-\(deviceTag)-\(mode.suffix).png")
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
                    XCTAssertTrue(app.staticTexts["Remote Input Dock"].waitForExistence(timeout: 8))
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
                    _ = findChecksButton(in: app).waitForExistence(timeout: 8)
                    try saveScreen(named: "04-profile-selected-ipad-\(orientationTag)-\(mode.suffix).png")
                    app.terminate()
                }

                // State 7 — compose with text
                do {
                    let app = launchApp(mode: mode)
                    let editor = app.textViews["Remote input text"]
                    XCTAssertTrue(editor.waitForExistence(timeout: 8))
                    editor.tap()
                    editor.typeText("Hello world")
                    try saveScreen(named: "07-compose-text-ipad-\(orientationTag)-\(mode.suffix).png")
                    app.terminate()
                }

                // State 8 — direct mode QWERTY
                do {
                    let app = launchAppSuppressingDirectWarning(mode: mode)
                    let directSegment = app.buttons["Direct"]
                    XCTAssertTrue(directSegment.waitForExistence(timeout: 8))
                    directSegment.tap()
                    XCTAssertTrue(app.buttons["Key q"].waitForExistence(timeout: 4))
                    try saveScreen(named: "08-direct-qwerty-ipad-\(orientationTag)-\(mode.suffix).png")
                    app.terminate()
                }
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

    private func launchApp(mode: ColorMode, seedProfiles: [SeedProfile] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uxaudit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
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
    }

    /// Launch the app with a `NARU_TEST_FIXTURE_SNAPSHOT` token that
    /// drives the model to a deterministic synthetic state — see
    /// `UXAuditFixtures.swift`.
    private func launchAppWithFixture(_ token: FixtureToken, mode: ColorMode) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uxaudit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = token.rawValue
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

        init(displayName: String, host: String, port: Int = 5900, hostKind: String = "magicDNS") {
            self.id = UUID()
            self.displayName = displayName
            self.host = host
            self.port = port
            self.hostKind = hostKind
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
    private func revealSidebarIfNeeded(app: XCUIApplication) {
        // SwiftUI's NavigationSplitView exposes a back button on
        // the navigation bar when the sidebar is collapsed.  The
        // accessibility label is localised but the system identifier
        // for the leading nav button is "Naru Remote" (the sidebar
        // title).  Try a few selectors.
        let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if backButton.exists && backButton.isHittable {
            backButton.tap()
        }
    }


    /// `app.buttons["Checks"]` matches by accessibilityIdentifier
    /// first, but an ancestor in the SwiftUI tree clobbers per-button
    /// identifiers with `naru.app.detail` (same finding as the
    /// existing `DirectKeystrokeKeyboardScreenshotsUITests`).  Match
    /// by accessibility label predicate instead.
    private func findChecksButton(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label == 'Checks'")
        return app.buttons.matching(predicate).firstMatch
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
}
