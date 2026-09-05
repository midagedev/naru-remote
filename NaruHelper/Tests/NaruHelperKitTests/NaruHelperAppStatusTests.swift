import XCTest
import NaruHelperKit
import NaruRemoteCore

/// Spec 041 T-A6 / FR-012: diagnostics carry the fixed catalog and nothing
/// else — no token, no fingerprint, no `code=`, no address.
final class NaruHelperAppStatusTests: XCTestCase {

    func testDiagnosticsTextIsOneKeyValuePerLine() {
        let status = NaruHelperAppStatus(
            accessibility: .granted,
            screenRecording: .missing,
            textListener: .listening(port: 5974),
            videoListener: .portInUse(port: 5975),
            pairing: .connected,
            loginItem: .requiresApproval,
            version: "0.19.3"
        )

        let lines = status.diagnosticsText().components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 7)
        for line in lines {
            XCTAssertTrue(line.contains("="), "every line is key=value: \(line)")
        }
        XCTAssertTrue(lines.contains("accessibility=granted"))
        XCTAssertTrue(lines.contains("screenRecording=missing"))
        XCTAssertTrue(lines.contains("textListener=listening:5974"))
        XCTAssertTrue(lines.contains("videoListener=portInUse:5975"))
        XCTAssertTrue(lines.contains("pairing=connected"))
        XCTAssertTrue(lines.contains("loginItem=requiresApproval"))
        XCTAssertTrue(lines.contains("version=0.19.3"))
    }

    func testDiagnosticsTextCarriesNoCredentialMaterial() throws {
        // Build the status alongside a real rotated token: the redaction
        // must hold even when a live secret exists in the same process.
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("naru-app-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let store = NaruHelperPairingStateStore(
            fileURL: temporaryDirectory.appendingPathComponent("helper-pairing-state.json")
        )
        let state = try store.rotate()

        let status = NaruHelperAppStatus(
            accessibility: .granted,
            screenRecording: .granted,
            textListener: .listening(port: 5974),
            videoListener: .listening(port: 5975),
            pairing: .paired,
            loginItem: .on,
            version: "0.19.3"
        )
        let text = status.diagnosticsText()

        XCTAssertFalse(text.contains(state.token), "the pairing token never appears")
        XCTAssertFalse(
            text.contains(String(state.fingerprint.dropFirst("sha256:".count))),
            "the fingerprint hex never appears"
        )
        XCTAssertFalse(text.contains(state.fingerprint))
        XCTAssertFalse(text.contains("code="), "no pairing code fragment appears")
        XCTAssertFalse(text.contains("100."), "no CGNAT address appears")
    }
}
