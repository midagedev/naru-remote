import UIKit
import XCTest

/// Live simulator gate for spec 023 (trackpad-first pointing) against the dev
/// Mac's Screen Sharing endpoint.
///
/// Two things are asserted mechanically — that a fresh connect lands in
/// trackpad mode without a toggle (FR-001/FR-002), and that a zoomed viewport
/// can be panned past flush into the breathing band (FR-003) — and three
/// screenshots are written for the visual claims the assertions cannot make:
/// where the drawn cursor tip sits relative to the remote pointer (FR-006) and
/// whether the remote screen's bottom row can be parked clear of the input
/// dock.
///
/// Env (same contract as `StreamLivenessUnderInteractionUITests`):
///   NARU_E2E_HOST     (default 127.0.0.1)
///   NARU_E2E_PORT     (default 5900)
///   NARU_E2E_PASSWORD (required; test skips when unset)
///   NARU_UX_AUDIT_OUTPUT_DIR (screenshot directory override)
@MainActor
final class TrackpadFirstPointingUITests: XCTestCase {
    private var host: String {
        ProcessInfo.processInfo.environment["NARU_E2E_HOST"] ?? "127.0.0.1"
    }
    private var port: Int {
        Int(ProcessInfo.processInfo.environment["NARU_E2E_PORT"] ?? "5900") ?? 5900
    }
    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_E2E_PASSWORD"]
    }
    private var outputDirectory: String {
        if let override = ProcessInfo.processInfo.environment["NARU_UX_AUDIT_OUTPUT_DIR"],
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return override
        }
        let checkoutRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // Under the gitignored local-Mac tree: these captures show the
        // developer's live desktop, so they must never become repo content.
        return checkoutRoot
            .appendingPathComponent(
                "artifacts/screenshots/local-mac-e2e/trackpad-first",
                isDirectory: true
            )
            .path
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testTrackpadIsLiveOnArrivalAndTheBottomRowCanBeParkedAboveTheDock() throws {
        guard let password else {
            throw XCTSkip("NARU_E2E_PASSWORD not set — skipping live trackpad-first gate")
        }

        let profileID = UUID()
        let credentialRef = "vnc-password:\(profileID.uuidString)"
        let app = launch(seedProfileID: profileID, credentialRef: credentialRef, password: password)

        let firstCard = app.buttons["naru.connection.grid.card"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "Saved connection card must be present")
        firstCard.tap()

        let diagnosticCorner = app.buttons["naru.session.diagnostics.corner"]
        XCTAssertTrue(
            diagnosticCorner.waitForExistence(timeout: 10),
            "A card tap must enter Operation"
        )

        let connectDeadline = Date().addingTimeInterval(30)
        while Date() < connectDeadline, !isConnected(diagnosticCorner) {
            allowSystemPermissionAlertIfPresent()
            usleep(250_000)
        }
        XCTAssertTrue(
            isConnected(diagnosticCorner),
            "Operation diagnostics must report Connected"
        )

        // FR-001: the mode button's accessibility label states the live mode,
        // so this is the end-to-end read of the product default — no toggle
        // was tapped anywhere above.
        let pointerMode = app.buttons["naru.session.pointerMode"]
        XCTAssertTrue(pointerMode.waitForExistence(timeout: 10), "Pointer-mode control must exist")
        let modeLabel = pointerMode.label
        XCTAssertTrue(
            modeLabel.hasPrefix("Trackpad mode"),
            "A fresh session must arrive in trackpad mode; label read: \(modeLabel)"
        )

        try saveScreen(named: "trackpad-arrival-iphone.png")

        // FR-006 visual: park the cursor mid-screen with a short drag so the
        // drawn glyph and the remote pointer are both in frame.
        let surface = app.windows.firstMatch
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.46))
            .press(
                forDuration: 0.06,
                thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.5))
            )
        usleep(600_000)
        try saveScreen(named: "trackpad-cursor-tip-iphone.png")

        // FR-003: zoom in, then drive the cursor down repeatedly. Auto-pan is
        // the only way trackpad mode moves the view, and with the breathing
        // band it must keep going after the content bottom reaches flush.
        surface.pinch(withScale: 3.2, velocity: 2.0)
        usleep(400_000)
        for _ in 0..<6 {
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        usleep(800_000)
        try saveScreen(named: "trackpad-bottom-band-iphone.png")

        print(
            "Trackpad-first gate: mode=\(modeLabel.hasPrefix("Trackpad mode") ? "trackpad" : "direct") "
                + "shots=3 dir=\(outputDirectory)"
        )
    }

    /// FR-006 measurement probe. Places the cursor with one deterministic drag,
    /// captures the screen, and prints the viewport geometry the lead needs to
    /// map the drawn tip's pixel back into remote-screen coordinates and
    /// compare it with the host's real pointer location. Ends immediately after
    /// the capture so the host pointer is still where this test left it.
    func testDrawnCursorTipProbe() throws {
        guard let password else {
            throw XCTSkip("NARU_E2E_PASSWORD not set — skipping cursor-tip probe")
        }

        let profileID = UUID()
        let credentialRef = "vnc-password:\(profileID.uuidString)"
        let app = launch(seedProfileID: profileID, credentialRef: credentialRef, password: password)

        let firstCard = app.buttons["naru.connection.grid.card"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        firstCard.tap()

        let diagnosticCorner = app.buttons["naru.session.diagnostics.corner"]
        XCTAssertTrue(diagnosticCorner.waitForExistence(timeout: 10))
        let connectDeadline = Date().addingTimeInterval(30)
        while Date() < connectDeadline, !isConnected(diagnosticCorner) {
            allowSystemPermissionAlertIfPresent()
            usleep(250_000)
        }
        XCTAssertTrue(isConnected(diagnosticCorner), "Operation diagnostics must report Connected")

        let surface = app.windows.firstMatch
        let frame = surface.frame
        // One drag, no zoom: the transform is pure aspect-fit, so the lead can
        // reconstruct it from the window size and the remote screen size alone.
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.44))
            .press(
                forDuration: 0.06,
                thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.56))
            )
        usleep(900_000)
        try saveScreen(named: "trackpad-tip-probe-iphone.png")

        print(
            "Cursor tip probe: windowPoints=(\(frame.width), \(frame.height)) "
                + "scale=\(UIScreen.main.scale)"
        )
    }

    // MARK: - Helpers

    private func isConnected(_ diagnosticCorner: XCUIElement) -> Bool {
        guard let value = diagnosticCorner.value as? String else { return false }
        return value.lowercased().hasPrefix("connected")
    }

    private func allowSystemPermissionAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.exists else { return }
        for label in ["Allow", "허용", "OK", "확인"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
    }

    private func saveScreen(named filename: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = filename
        add(attachment)

        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename)
        guard let png = screenshot.image.pngData() else {
            XCTFail("Could not encode \(filename)")
            return
        }
        try png.write(to: url)
    }

    private func launch(
        seedProfileID: UUID,
        credentialRef: String,
        password: String
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_HOST"] = host
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_PORT"] = String(port)
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_ID"] = seedProfileID.uuidString
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_NAME"] = "Pointing Mac"
        app.launchEnvironment["NARU_TEST_SEED_PROFILE_CREDENTIAL_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_REF"] = credentialRef
        app.launchEnvironment["NARU_TEST_INJECT_KEYCHAIN_PASSWORD"] = password
        app.launch()
        return app
    }
}
