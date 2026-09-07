import NaruRemoteCore
import XCTest

/// Spec 042 Round A — VNC-first entry hierarchy screenshots (FR-001..003).
/// Captures the three surfaces on the canonical iPhone target into
/// `artifacts/screenshots/vnc-first/`; this round does not judge the PNGs
/// (an opus vision round does) — it proves the surfaces render with the
/// new hierarchy and records the copy contract as assertions.
///
/// Contract ↔ assertion table:
///
/// | Requirement | Contract | Test / capture |
/// |---|---|---|
/// | FR-001 | Empty home: manual add is the single primary action; the QR path is secondary and labelled optional; nothing implies the helper is required | `testEmptyHomeAndScannerStateHelperOptionalFirst` asserts `naru.home.empty.addProfile` and a secondary `naru.home.empty.scanPair` whose label reads "Add by QR", plus the "Optional — for Macs running Naru Helper." caption; captures `01-empty-home.png` |
/// | FR-002 | Scanner first line states the helper is optional and that any VNC host can be added by address | same test taps the QR entry and asserts `naru.pairing.scan.helperOptionalNote` and the "Add by QR" navigation title; captures `02-scanner.png` |
/// | FR-003 | Pairing confirmation shows the VNC endpoint first and helper details under a collapsed disclosure | `testConfirmSheetKeepsVncFirstAndHelperCollapsed` asserts `naru.pairing.confirm.helperDisclosure`, that the helper port row is absent while collapsed, and that the constitution guarantee line stays; captures `03-confirm.png` |
///
/// Self-review of defect classes these screenshots cannot catch, and what
/// this file does about each:
///
/// 1. **Dynamic Type truncation** of the new caption and scanner note —
///    both texts wrap by default (no `lineLimit`), so growth wraps instead
///    of truncating; existence assertions here prove the elements are in
///    the tree at default size only. A Dynamic Type capture pass is the
///    lead's vision-round call, not this round.
/// 2. **iPad layout** — iPhone is the canonical target (constitution §VI);
///    iPad is a graceful-scaling check listed in the spec's verification
///    matrix and owned there, not duplicated here.
/// 3. **VoiceOver order** — the scanner note is structurally first (first
///    child of the screen's VStack before the camera/paste area), which is
///    the order VoiceOver traverses; XCUITest exposes no reading-order API,
///    so this is justified structurally rather than asserted.
@MainActor
final class VncFirstScreenshotsUITests: XCTestCase {

    private let outputDirectory =
        "/Users/hckim/repo/naru-remote/artifacts/screenshots/vnc-first"

    /// FR-001 + FR-002 — launched with an empty profile store and *no*
    /// pairing code: exactly what a helper-less first-time user sees.
    func testEmptyHomeAndScannerStateHelperOptionalFirst() throws {
        let app = launch()

        // 01 — empty home. "Add a Computer" stays the single primary
        // action; the QR entry renders as secondary text with the
        // optionality stated beneath it.
        XCTAssertTrue(
            app.buttons["naru.home.empty.addProfile"].waitForExistence(timeout: 8),
            "Empty home must present the manual add action"
        )
        let scanPair = app.buttons["naru.home.empty.scanPair"]
        XCTAssertTrue(
            scanPair.waitForExistence(timeout: 8),
            "Empty home must present the QR entry"
        )
        XCTAssertTrue(
            scanPair.label.contains("Add by QR"),
            "QR entry label must name the QR path, got: \(scanPair.label)"
        )
        XCTAssertTrue(
            app.staticTexts["Optional — for Macs running Naru Helper."]
                .waitForExistence(timeout: 4),
            "Empty home must caption the QR entry as optional"
        )
        try save("01-empty-home.png")

        // 02 — scanner. The first text on the screen states the helper is
        // optional and the by-address path exists. "Enter VNC details
        // instead" renders only when the shell passes `onEnterManually`;
        // that wiring is the lead's (plan decision 6), so this test asserts
        // the optional note instead — the FR-002 first-line contract.
        scanPair.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["naru.pairing.scan.helperOptionalNote"]
                .waitForExistence(timeout: 8),
            "Scanner must lead with the helper-is-optional note"
        )
        XCTAssertTrue(
            app.navigationBars["Add by QR"].waitForExistence(timeout: 6),
            "Scanner title must read \"Add by QR\""
        )
        try save("02-scanner.png")
    }

    /// FR-003 — the confirm sheet a scan (or launch-injected code) lands
    /// on: VNC endpoint rows stand on their own, helper ports wait
    /// collapsed behind the disclosure.
    func testConfirmSheetKeepsVncFirstAndHelperCollapsed() throws {
        let offer = try Self.makeSampleOffer()
        let app = launch(withPairingCode: try NaruPairingOfferWire.encode(offer))

        XCTAssertTrue(
            app.buttons["naru.pairing.confirm.save"].waitForExistence(timeout: 8),
            "Launch-injected pairing code must present the confirm sheet"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["naru.pairing.confirm.helperDisclosure"]
                .waitForExistence(timeout: 8),
            "Confirm sheet must carry the Helper (optional) disclosure"
        )
        // Collapsed by default: the helper port row is not on screen until
        // the disclosure opens. The expected value is read from the same
        // offer instance that was encoded, not hand-copied.
        XCTAssertFalse(
            app.staticTexts[
                "text \(offer.helper.textPort) · video \(offer.helper.videoPort)"
            ].exists,
            "Helper ports must start collapsed behind the disclosure (FR-003)"
        )
        XCTAssertTrue(
            app.staticTexts[
                "Basic viewing keeps working without the helper — always, by design."
            ].exists,
            "The constitution guarantee line must stay on the confirm sheet"
        )
        try save("03-confirm.png")
    }

    // MARK: - Helpers

    /// Same launch contract as `QrPairingScreenshotsUITests`: an isolated
    /// temp profile store, load skipped, and optionally a launch-injected
    /// pairing code (the app's DEBUG-only `NARU_TEST_PAIRING_CODE` hook).
    private func launch(withPairingCode code: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"] = "1"
        if let code {
            app.launchEnvironment["NARU_TEST_PAIRING_CODE"] = code
        }
        app.launch()
        return app
    }

    /// Mirrors `QrPairingScreenshotsUITests.makeSamplePairingCode`'s offer
    /// (kept local because that helper is private); returns the offer so
    /// assertions can read field values from the same source the encode
    /// used.
    private static func makeSampleOffer() throws -> NaruPairingOffer {
        let token = HelperPairingSecret.generate()
        return NaruPairingOffer(
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
    }

    /// Attaches the screenshot and copies the PNG next to the spec 040
    /// qr-pairing captures. The > 20 KB floor is spec 042's own gate —
    /// a blank or failed surface render must fail here, not downstream.
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
        XCTAssertGreaterThan(size, 20_480, "Screenshot \(filename) must exceed 20 KB")
    }
}
