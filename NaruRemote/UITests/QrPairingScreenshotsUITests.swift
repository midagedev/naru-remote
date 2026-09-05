import NaruRemoteCore
import XCTest

/// Captures iPhone-simulator screenshots of the spec 040 QR pairing
/// flow. The simulator has no camera, so the app's
/// `NARU_TEST_PAIRING_CODE` launch-environment hook injects a full,
/// validly-signed pairing code at launch — the exact confirm sheet a real
/// scan or `naru://` deep link produces — and the test also drives the
/// scanner sheet's paste-fallback surface. Replaces the spec 010
/// onboarding screenshot test retired with that flow.
@MainActor
final class QrPairingScreenshotsUITests: XCTestCase {

    private let outputDirectory =
        "/Users/hckim/repo/naru-remote/artifacts/screenshots/qr-pairing"

    func testCapturesScannerAndConfirmSheetOnIPhone() throws {
        let app = launch(withPairingCode: try Self.makeSamplePairingCode())

        // 01 — the confirm sheet a scan (or system-camera deep link)
        // lands on, before anything is saved.
        XCTAssertTrue(
            app.buttons["naru.pairing.confirm.save"].waitForExistence(timeout: 8),
            "Launch-injected pairing code must present the confirm sheet"
        )
        try save("01-confirm.png")

        app.buttons["naru.pairing.confirm.save"].tap()
        XCTAssertTrue(
            app.buttons["naru.connection.grid.scanPair"].waitForExistence(timeout: 8),
            "Saving the offer must land on the connections grid with the QR entry"
        )
        try save("02-after-save-grid.png")

        // 03 — the scanner surface with its paste fallback (no camera in
        // the simulator, which is exactly the fallback path's shot).
        app.buttons["naru.connection.grid.scanPair"].tap()
        XCTAssertTrue(
            app.otherElements["naru.pairing.scan.placeholder"].waitForExistence(timeout: 6)
                || app.textFields["naru.pairing.scan.pasteField"].waitForExistence(timeout: 6),
            "Scanner sheet must present with the paste fallback"
        )
        try save("03-scanner.png")
    }

    func testInvalidInjectedCodeShowsScannerNotCrash() throws {
        let app = launch(withPairingCode: "naru://pair?code=definitely-not-valid")
        // No confirm sheet may appear; the app stays on the home grid.
        XCTAssertFalse(
            app.buttons["naru.pairing.confirm.save"].waitForExistence(timeout: 4),
            "An invalid code must never present the confirm sheet"
        )
        XCTAssertTrue(
            app.buttons["naru.connection.grid.add"].waitForExistence(timeout: 8)
                || app.buttons["naru.home.empty.addProfile"].waitForExistence(timeout: 8),
            "The app must remain usable after an invalid code"
        )
    }

    // MARK: - Helpers

    private func launch(withPairingCode code: String) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        app.launchEnvironment["NARU_TEST_PAIRING_CODE"] = code
        app.launch()
        return app
    }

    /// A real wire-format code: encode through the same Core type the
    /// helper CLI uses, so the screenshot shows production field values.
    private static func makeSamplePairingCode() throws -> String {
        let token = HelperPairingSecret.generate()
        let offer = NaruPairingOffer(
            host: .init(
                label: "Studio Mac",
                magicDns: "studio.tailnet.ts.net",
                addresses: ["100.126.136.43"]
            ),
            helper: .init(
                token: token,
                fingerprint: HelperPairingSecret.fingerprint(for: token)
            ),
            vncPassword: nil
        )
        return try NaruPairingOfferWire.encode(offer)
    }

    private func save(_ filename: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = filename
        add(attachment)

        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename)
        try screenshot.pngRepresentation.write(to: url)

        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "Screenshot \(filename) must not be empty")
    }
}
