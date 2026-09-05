import AppKit
import ImageIO
import XCTest

/// Spec 041 T-B5: screenshots of the menu bar app's two surfaces, driven
/// against fixture launch arguments. The store is pointed at a temp
/// directory (`--ui-test-state-dir`) and the displayed offer is a fake,
/// wire-format-valid code, so no committed PNG carries a real token or
/// this Mac's tailnet address — the same privacy rule that keeps
/// `QrPairingScreenshotsUITests` fixtures synthetic.
@MainActor
final class HelperMenuBarScreenshotsUITests: XCTestCase {

    private let outputDirectory =
        "/Users/hckim/repo/naru-remote/artifacts/screenshots/helper-menu-bar"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Tests

    func test01PairingWindowShowsQRPermissionsAndCopy() throws {
        let app = launch(extraArguments: [
            "--ui-test-open-pairing",
            "--ui-test-offer", Self.makeSampleOffer(),
            "--ui-test-state", "notPaired",
            "--ui-test-permissions", "granted",
        ])
        addTeardownBlock { app.terminate() }

        let window = app.windows["Pair with iPhone"]
        XCTAssertTrue(
            window.waitForExistence(timeout: 10),
            "the fixture launch must open the pairing window")

        let qr = app.descendants(matching: .any)["pairing-qr"].firstMatch
        // The first QR render pays a one-time CoreImage/Metal kernel
        // library load (~a minute on a cold, loaded Mac — measured), so
        // this wait must dwarf the others.
        XCTAssertTrue(
            qr.waitForExistence(timeout: 120),
            "the injected offer must render a QR card")

        let accessibilityState = app.descendants(matching: .any)["permission-accessibility-state"].firstMatch
        XCTAssertTrue(accessibilityState.waitForExistence(timeout: 5), "Accessibility row must render")
        XCTAssertEqual(accessibilityState.label, "Granted")
        let screenRecordingState = app.descendants(matching: .any)["permission-screen-recording-state"].firstMatch
        XCTAssertTrue(screenRecordingState.exists, "Screen Recording row must render")
        XCTAssertEqual(screenRecordingState.label, "Granted")

        XCTAssertTrue(app.buttons["copy-code"].exists, "the raw code must be one click to copy")
        XCTAssertTrue(app.buttons["regenerate-qr"].exists, "regeneration must be offered")

        try save("pairing.png", screenshot: window.screenshot())
    }

    func test02PairingWindowShowsConnectedState() throws {
        let app = launch(extraArguments: [
            "--ui-test-open-pairing",
            "--ui-test-offer", Self.makeSampleOffer(),
            "--ui-test-state", "connected",
            "--ui-test-permissions", "granted",
        ])
        addTeardownBlock { app.terminate() }

        XCTAssertTrue(
            app.staticTexts["Paired — iPhone connected"].waitForExistence(timeout: 120),
            "the connected fixture must replace the QR with the paired headline")
        XCTAssertFalse(
            app.descendants(matching: .any)["pairing-qr"].firstMatch.exists,
            "the QR is credential material and must be gone once paired")

        try save("paired.png", screenshot: app.windows["Pair with iPhone"].screenshot())
    }

    func test03MenuListsContractOrderAndCaptures() throws {
        let app = launch(extraArguments: [
            "--ui-test-state", "notPaired",
            "--ui-test-permissions", "granted",
        ])
        addTeardownBlock { app.terminate() }

        let statusItem = app.statusItems.firstMatch
        var droveRealStatusItem = false
        if statusItem.waitForExistence(timeout: 10) {
            statusItem.click()
            if app.menuItems["Pair with iPhone…"].waitForExistence(timeout: 5) {
                droveRealStatusItem = true
                let titles = try orderedTitles(in: app.menuItems)
                try assertOrder(titles.map { ($0, app.menuItems[$0]) })
                try saveMenuCapture(from: app, titles: titles)
            }
        }

        if !droveRealStatusItem {
            // Fallback (stated in the round report): the real status item
            // could not be driven headlessly, so the same `HelperMenu`
            // content is rendered in the preview window and captured
            // there.
            app.terminate()
            let preview = launch(extraArguments: [
                "--ui-test-open-menu-preview",
                "--ui-test-state", "notPaired",
                "--ui-test-permissions", "granted",
            ])
            addTeardownBlock { preview.terminate() }
            let window = preview.windows["Menu Preview"]
            XCTAssertTrue(
                window.waitForExistence(timeout: 10),
                "the preview fallback window must open")
            let titles = try orderedTitles(in: preview.descendants(matching: .any))
            try assertOrder(titles.map { ($0, preview.descendants(matching: .any)[$0].firstMatch) })
            try save("menu.png", screenshot: window.screenshot())
        }
    }

    // MARK: Order contract

    /// The contract order of spec 041 T-B4. The login-item row's title
    /// depends on the system-reported state, so both spellings are
    /// accepted at that position.
    private func orderedTitles(in query: XCUIElementQuery) throws -> [String] {
        let plain = "Start at login"
        let needsApproval = "Start at login (needs approval in System Settings)"
        let toggleTitle: String
        if query[plain].firstMatch.exists {
            toggleTitle = plain
        } else if query[needsApproval].firstMatch.exists {
            toggleTitle = needsApproval
        } else {
            XCTFail("the Start at login row must render in either state spelling")
            throw XCTSkip("unreachable — failure recorded above")
        }
        return [
            "Not paired",
            "Accessibility: Granted",
            "Screen Recording: Granted",
            "Pair with iPhone…",
            toggleTitle,
            "Revoke pairing…",
            "Copy Diagnostics",
            "Naru Helper 1.0.0 (1)",
            "Quit",
        ]
    }

    private func assertOrder(_ items: [(String, XCUIElement)]) throws {
        var previousMinY: CGFloat = -.infinity
        for (title, element) in items {
            XCTAssertTrue(element.exists, "the menu must list \(title)")
            if element.exists {
                XCTAssertGreaterThanOrEqual(
                    element.frame.minY,
                    previousMinY,
                    "\(title) must not precede the preceding contract item")
                previousMinY = element.frame.minY
            }
        }
    }

    // MARK: Capture helpers

    /// Mirrors `QrPairingScreenshotsUITests.save(_:)` (the reference UI
    /// test): attachment plus a PNG written into the repo's artifacts
    /// tree, with the non-empty check.
    private func save(_ filename: String, screenshot: XCUIScreenshot) throws {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = filename
        add(attachment)
        try writePNG(screenshot.pngRepresentation, as: filename)
    }

    /// The open menu belongs to the screen, not to a window the test can
    /// screenshot element-wise, so `menu.png` crops the screen capture to
    /// the union frame of the asserted menu items (+ margin) — a
    /// committed artifact must not carry the rest of the desktop.
    private func saveMenuCapture(from app: XCUIApplication, titles: [String]) throws {
        var union: CGRect?
        for title in titles {
            let item = app.menuItems[title]
            union = union.map { $0.union(item.frame) } ?? item.frame
        }
        guard let rect = union else {
            XCTFail("no menu item frames to crop")
            return
        }
        let screenShot = XCUIScreen.main.screenshot()
        let cropped = try Self.crop(
            screenShot.pngRepresentation,
            toScreenRect: rect.insetBy(dx: -8, dy: -8))

        let attachment = XCTAttachment(
            uniformTypeIdentifier: "public.png",
            name: "menu.png",
            payload: cropped,
            userInfo: nil)
        attachment.lifetime = .keepAlways
        add(attachment)
        try writePNG(cropped, as: "menu.png")
    }

    private func writePNG(_ png: Data, as filename: String) throws {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename)
        try png.write(to: url)

        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "Screenshot \(filename) must not be empty")
    }

    /// `rect` is in screen points (top-left origin, the space
    /// `XCUIElement.frame` reports); the display's backing scale converts
    /// it to PNG pixels.
    private static func crop(_ png: Data, toScreenRect rect: CGRect) throws -> Data {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw CaptureError.unreadable
        }
        let screenPoints = NSScreen.main?.frame.size
            ?? NSSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let scale = CGFloat(image.width) / max(screenPoints.width, 1)
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale)
        guard let cropped = image.cropping(to: pixelRect.intersection(
            CGRect(x: 0, y: 0, width: image.width, height: image.height)))
        else {
            throw CaptureError.unreadable
        }
        let rep = NSBitmapImageRep(cgImage: cropped)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.unwritable
        }
        return data
    }

    private enum CaptureError: Error {
        case unreadable
        case unwritable
    }

    // MARK: Launch helpers

    private func launch(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // UI tests never touch the real `~/.naru` state (spec 041 T-B5):
        // the fixture flag points the whole process at a temp directory.
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-helper-uitest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: stateDirectory, withIntermediateDirectories: true)
        app.launchArguments = [
            "--ui-test",
            "--ui-test-state-dir", stateDirectory.path,
        ] + extraArguments
        app.launch()
        return app
    }

    /// A wire-format-valid fake offer — the same JSON/base64url shape
    /// `NaruPairingOfferWire.encode` produces (and the same shape the
    /// reference `QrPairingScreenshotsUITests.makeSamplePairingCode`
    /// builds) with fixture values: a fingerprint of 64 lowercase hex
    /// under `sha256:`, a CGNAT-range address, and a base64url token.
    private static func makeSampleOffer() -> String {
        let json = """
        {"helper":{"fingerprint":"sha256:\(String(repeating: "ab", count: 32))","textPort":5974,"token":"UklOR19VSU5UX09GRkVS","videoPort":5975},"host":{"addresses":["100.127.0.1"],"label":"Studio Mac","magicDns":"studio-mac.example.ts.net","vncPort":5900},"v":1}
        """
        let code = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "naru://pair?code=\(code)"
    }
}
