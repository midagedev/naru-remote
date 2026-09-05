import CoreGraphics
import XCTest
import NaruHelperKit
import NaruRemoteCore

/// Spec 041 T-A4/T-A5: the pairing session produces, for the same inputs,
/// the offer `NaruPairingOfferWire.encode` produces — one encoder path
/// shared by the app window and the CLI — plus a QR image sized for a
/// phone camera. The CGNAT filter is unit-tested on synthetic octets.
final class NaruHelperPairingSessionTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("naru-pairing-session-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    private func makeStore() -> NaruHelperPairingStateStore {
        NaruHelperPairingStateStore(
            fileURL: temporaryDirectory.appendingPathComponent("helper-pairing-state.json")
        )
    }

    private func makeHostInfo() -> NaruHelperPairingHostInfo {
        NaruHelperPairingHostInfo(
            label: "Test Mac",
            magicDns: "test-mac.tail1234.ts.net",
            addresses: ["100.64.0.1", "100.100.42.7"]
        )
    }

    // MARK: - Offer parity (T-A5)

    func testOfferURLEqualsWireEncodingOfTheSameInputs() throws {
        let store = makeStore()
        let hostInfo = makeHostInfo()
        let session = try NaruHelperPairingSession.begin(
            store: store,
            hostInfo: hostInfo,
            vncPort: 5902,
            vncPassword: "vnc-password-opt-in"
        )

        let expectedOffer = NaruPairingOffer(
            host: .init(
                label: hostInfo.label,
                magicDns: hostInfo.magicDns,
                addresses: hostInfo.addresses,
                vncPort: 5902
            ),
            helper: .init(
                token: session.state.token,
                fingerprint: session.state.fingerprint
            ),
            vncPassword: "vnc-password-opt-in"
        )

        // The session must go through the one shared encoder. Foundation's
        // JSONEncoder does not guarantee key order across encode call sites
        // (measured in-process: two `NaruPairingOfferWire.encode` calls with
        // equal inputs produced different key orders), so parity is asserted
        // at the decoded-value level — what the phone actually consumes.
        XCTAssertEqual(try NaruPairingOfferWire.decode(session.offerURL), expectedOffer)
        XCTAssertTrue(
            session.offerURL.hasPrefix("naru://pair?code="),
            "the offer URL uses the pairing scheme: \(session.offerURL)"
        )

        XCTAssertEqual(store.currentSecret(), session.state.token, "begin must rotate the store")
        XCTAssertEqual(session.state.fingerprint, HelperPairingSecret.fingerprint(for: session.state.token))
    }

    func testBeginRotatesPreviousToken() throws {
        let store = makeStore()
        let previous = try store.rotate()

        let session = try NaruHelperPairingSession.begin(
            store: store,
            hostInfo: makeHostInfo()
        )

        XCTAssertNotEqual(session.state.token, previous.token, "each pairing mints a fresh token")
    }

    // MARK: - QR image (T-A5)

    func testQRImageIsSquareAndAtLeast320Pixels() throws {
        let session = try NaruHelperPairingSession.begin(
            store: makeStore(),
            hostInfo: makeHostInfo()
        )

        let image = try XCTUnwrap(session.qrImage, "CoreImage must render the offer")
        XCTAssertEqual(image.width, image.height, "the QR image must be square")
        XCTAssertGreaterThanOrEqual(
            image.width,
            NaruHelperPairingSession.minimumQRPixelSize,
            "a phone camera reads ≥\(NaruHelperPairingSession.minimumQRPixelSize) px at arm's length"
        )
        XCTAssertGreaterThanOrEqual(image.height, NaruHelperPairingSession.minimumQRPixelSize)
    }

    func testEndDropsQRImage() throws {
        let session = try NaruHelperPairingSession.begin(
            store: makeStore(),
            hostInfo: makeHostInfo()
        )
        XCTAssertNotNil(session.qrImage)

        session.end()
        XCTAssertNil(session.qrImage, "the QR is credential material — dismiss drops it")
        // The token itself stays valid until the next rotation.
        XCTAssertFalse(session.offerURL.isEmpty)
    }

    // MARK: - CGNAT filter (T-A4)

    func testIsTailnetIPv4Boundaries() {
        // 100.64.0.0/10 — the /10 boundary in octet 1 is 64...127.
        XCTAssertFalse(NaruHelperPairingHostInfo.isTailnetIPv4([100, 63, 255, 255]))
        XCTAssertTrue(NaruHelperPairingHostInfo.isTailnetIPv4([100, 64, 0, 0]))
        XCTAssertTrue(NaruHelperPairingHostInfo.isTailnetIPv4([100, 127, 255, 255]))
        XCTAssertFalse(NaruHelperPairingHostInfo.isTailnetIPv4([100, 128, 0, 0]))
        XCTAssertFalse(NaruHelperPairingHostInfo.isTailnetIPv4([10, 0, 0, 1]))
        // Non-CGNAT 100.x and malformed inputs.
        XCTAssertFalse(NaruHelperPairingHostInfo.isTailnetIPv4([100, 0, 0, 1]))
        XCTAssertFalse(NaruHelperPairingHostInfo.isTailnetIPv4([100, 64, 0]))
        XCTAssertFalse(NaruHelperPairingHostInfo.isTailnetIPv4([]))
    }
}
