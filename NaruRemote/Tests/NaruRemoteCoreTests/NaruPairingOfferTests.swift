import Foundation
import NaruRemoteCore
import XCTest

/// Spec 040 FR-001 gate: the single parser behind the in-app scanner,
/// the system-camera deep link, and the paste fallback. Round-trips and
/// every rejection class from the spec's strict-parsing rule.
final class NaruPairingOfferTests: XCTestCase {

    private func sampleOffer() -> NaruPairingOffer {
        let token = HelperPairingSecret.generate()
        return NaruPairingOffer(
            host: .init(
                label: "MacBook Pro",
                magicDns: "hckim-macbookpro",
                addresses: ["100.126.136.43"],
                vncPort: 5900
            ),
            helper: .init(token: token, fingerprint: HelperPairingSecret.fingerprint(for: token)),
            vncPassword: "vnc-secret"
        )
    }

    func testRoundTripThroughFullURL() throws {
        let offer = sampleOffer()
        let url = try NaruPairingOfferWire.encode(offer)
        XCTAssertTrue(url.hasPrefix("naru://pair?code="), "expected the canonical wire form, got \(url.prefix(20))…")
        let decoded = try NaruPairingOfferWire.decode(url)
        XCTAssertEqual(decoded, offer)
    }

    /// Spec 041 FR-003: the app's QR and the CLI's QR must carry the same
    /// code for the same inputs. Foundation's JSONEncoder orders keys
    /// arbitrarily per call (measured 2026-09-05: two encodes in one
    /// process differed), so the encoder pins `.sortedKeys`.
    func testEncodeIsByteDeterministicAcrossCalls() throws {
        let offer = NaruPairingOffer(
            host: .init(label: "Det Mac", magicDns: "det.example.ts.net", addresses: ["100.64.0.9"]),
            helper: .init(token: "dGVzdC10b2tlbi1kZXRlcm1pbmlzbQ", fingerprint: "sha256:" + String(repeating: "ab", count: 32)),
            vncPassword: "pw"
        )
        var seen = Set<String>()
        for _ in 0..<50 {
            seen.insert(try NaruPairingOfferWire.encode(offer))
        }
        XCTAssertEqual(seen.count, 1, "encode must be byte-identical for equal inputs")
    }

    func testRoundTripWithoutVncPassword() throws {
        var offer = sampleOffer()
        offer.vncPassword = nil
        let decoded = try NaruPairingOfferWire.decode(try NaruPairingOfferWire.encode(offer))
        XCTAssertEqual(decoded, offer)
        XCTAssertNil(decoded.vncPassword)
    }

    func testBareBase64CodeIsAcceptedLikeTheURL() throws {
        // The paste fallback receives whatever the user copied from the
        // terminal — the full URL or the bare code (Orca parity).
        let offer = sampleOffer()
        let url = try NaruPairingOfferWire.encode(offer)
        let code = url.replacingOccurrences(of: "naru://pair?code=", with: "")
        XCTAssertEqual(try NaruPairingOfferWire.decode(code), offer)
        XCTAssertEqual(try NaruPairingOfferWire.decode("  \(url)\n"), offer, "surrounding whitespace is tolerated")
    }

    func testOnlyTheExactPairHostCarriesAuthMaterial() throws {
        let offer = sampleOffer()
        var components = URLComponents(string: try NaruPairingOfferWire.encode(offer))!
        components.host = "pairing"
        let impostor = components.url!.absoluteString
        XCTAssertThrowsError(try NaruPairingOfferWire.decode(impostor)) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .malformedURL)
        }
    }

    func testWrongSchemeIsRejected() throws {
        let offer = sampleOffer()
        let url = try NaruPairingOfferWire.encode(offer)
            .replacingOccurrences(of: "naru://", with: "evil://")
        XCTAssertThrowsError(try NaruPairingOfferWire.decode(url)) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .malformedURL)
        }
    }

    func testMissingCodeQueryIsRejected() {
        XCTAssertThrowsError(try NaruPairingOfferWire.decode("naru://pair")) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .malformedURL)
        }
    }

    func testStandardBase64CharactersInCodeAreRejected() {
        // `+`, `/`, and padding must never appear — the charset check is
        // what makes the code copy-safe in shells and QR-safe.
        XCTAssertThrowsError(try NaruPairingOfferWire.decode("naru://pair?code=ab+cd")) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .malformedCode)
        }
        XCTAssertThrowsError(try NaruPairingOfferWire.decode("naru://pair?code=abcd==")) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .malformedCode)
        }
    }

    func testNonJSONPayloadIsRejected() throws {
        let junk = Data("not json".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try NaruPairingOfferWire.decode(junk)) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .malformedPayload)
        }
    }

    func testWrongVersionIsRejectedNotGuessed() throws {
        let token = HelperPairingSecret.generate()
        let hostJSON = """
        {"v":999,"host":{"label":"M","magicDns":null,"addresses":["100.1.1.1"],"vncPort":5900},\
        "helper":{"textPort":5974,"videoPort":5975,"token":"\(token)",\
        "fingerprint":"\(HelperPairingSecret.fingerprint(for: token))"}}
        """
        let code = Data(hostJSON.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try NaruPairingOfferWire.decode(code)) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .unsupportedVersion)
        }
    }

    func testFingerprintDriftIsRejected() throws {
        var offer = sampleOffer()
        offer.helper.fingerprint = "sha256:" + String(repeating: "0", count: 63)
        XCTAssertThrowsError(try NaruPairingOfferWire.encodeAndDecodeForTest(offer)) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .invalidField)
        }
        offer.helper.fingerprint = "sha256:" + String(repeating: "A", count: 64)
        XCTAssertThrowsError(try NaruPairingOfferWire.encodeAndDecodeForTest(offer)) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .invalidField)
        }
    }

    func testOfferWithNoAddressAndNoMagicDnsIsRejected() throws {
        var offer = sampleOffer()
        offer.host.magicDns = nil
        offer.host.addresses = []
        XCTAssertThrowsError(try NaruPairingOfferWire.encodeAndDecodeForTest(offer)) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .noReachableAddress)
        }
    }

    func testOversizedInputIsRejectedBeforeParsing() {
        let huge = String(repeating: "a", count: NaruPairingOfferWire.maxInputCharacters + 1)
        XCTAssertThrowsError(try NaruPairingOfferWire.decode(huge)) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .inputTooLong
            )
        }
    }

    func testEmptyAndBlankInputsAreRejected() {
        XCTAssertThrowsError(try NaruPairingOfferWire.decode("")) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .inputTooLong)
        }
        XCTAssertThrowsError(try NaruPairingOfferWire.decode("   ")) { error in
            XCTAssertEqual(error as? NaruPairingOfferError, .inputTooLong)
        }
    }
}

private extension NaruPairingOfferWire {
    /// Test-only helper: encode then decode, so rejection cases can be
    /// expressed against a struct rather than hand-built JSON.
    static func encodeAndDecodeForTest(_ offer: NaruPairingOffer) throws -> NaruPairingOffer {
        try decode(try encode(offer))
    }
}
