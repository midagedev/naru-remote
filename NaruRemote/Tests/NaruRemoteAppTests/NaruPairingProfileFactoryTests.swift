import NaruRemoteApp
import NaruRemoteCore
import XCTest

/// Spec 040: the QR offer → persistence translation. The credential
/// reference scheme must match the profile editor's exactly, so a
/// QR-paired profile is indistinguishable from an editor-created one
/// downstream (US-1 SC-2, FR-004).
final class NaruPairingProfileFactoryTests: XCTestCase {

    private func sampleOffer(
        label: String = "MacBook Pro",
        host: String? = "hckim-macbookpro",
        addresses: [String] = ["100.126.136.43"],
        withPassword: Bool = true
    ) throws -> NaruPairingOffer {
        let token = HelperPairingSecret.generate()
        return NaruPairingOffer(
            host: .init(
                label: label,
                magicDns: host,
                addresses: addresses
            ),
            helper: .init(
                token: token,
                fingerprint: HelperPairingSecret.fingerprint(for: token)
            ),
            vncPassword: withPassword ? "vnc-secret" : nil
        )
    }

    func testProfileCarriesEditorIdenticalCredentialReferences() throws {
        let offer = try sampleOffer()
        let profile = try NaruPairingProfileFactory.makeProfile(offer: offer, existingID: nil)

        XCTAssertEqual(profile.displayName, "MacBook Pro")
        XCTAssertEqual(profile.host, "hckim-macbookpro")
        XCTAssertEqual(profile.hostKind, .magicDNS)
        XCTAssertEqual(profile.port, 5900)
        XCTAssertEqual(
            profile.credentialRef,
            "vnc-password:\(profile.id.uuidString)",
            "must match the editor's reference scheme"
        )
        XCTAssertEqual(profile.helperTextBridge?.pairingSecretRef, "helper-token:\(profile.id.uuidString)")
        XCTAssertEqual(profile.helperVideo?.pairingSecretRef, "helper-video-token:\(profile.id.uuidString)")
        XCTAssertEqual(profile.helperTextBridge?.pairingFingerprint, offer.helper.fingerprint)
        XCTAssertEqual(profile.helperVideo?.pairingFingerprint, offer.helper.fingerprint)
        XCTAssertTrue(profile.helperTextBridge?.isEnabled == true)
        XCTAssertTrue(profile.helperVideo?.isEnabled == true)
    }

    func testPasswordlessOfferLeavesCredentialRefNil() throws {
        let offer = try sampleOffer(withPassword: false)
        let profile = try NaruPairingProfileFactory.makeProfile(offer: offer, existingID: nil)
        XCTAssertNil(profile.credentialRef)
        XCTAssertNil(NaruPairingProfileFactory.makeCredentialUpdate(for: offer).vncPassword)
    }

    func testRePairKeepsProfileIDSoKeychainReferencesSurvive() throws {
        let offer = try sampleOffer()
        let existingID = UUID()
        let profile = try NaruPairingProfileFactory.makeProfile(offer: offer, existingID: existingID)
        XCTAssertEqual(profile.id, existingID)
        XCTAssertEqual(profile.helperTextBridge?.pairingSecretRef, "helper-token:\(existingID.uuidString)")
    }

    func testExistingProfileMatchPrefersHostThenLabel() throws {
        let offer = try sampleOffer(label: "Renamed Mac", host: "same-host")
        let byHost = try ConnectionProfile(displayName: "Different name", host: "same-host")
        let byLabel = try ConnectionProfile(displayName: "Renamed Mac", host: "other-host")
        let unrelated = try ConnectionProfile(displayName: "Third", host: "third-host")

        XCTAssertEqual(
            NaruPairingProfileFactory.existingProfileID(for: offer, in: [unrelated, byHost]),
            byHost.id
        )
        XCTAssertEqual(
            NaruPairingProfileFactory.existingProfileID(for: offer, in: [unrelated, byLabel]),
            byLabel.id
        )
        XCTAssertNil(NaruPairingProfileFactory.existingProfileID(for: offer, in: [unrelated]))
    }

    func testMagicDnsFallbackUsesFirstAddressAsPrivateKind() throws {
        let offer = try sampleOffer(host: nil)
        XCTAssertEqual(NaruPairingProfileFactory.hostString(for: offer), "100.126.136.43")
        let profile = try NaruPairingProfileFactory.makeProfile(offer: offer, existingID: nil)
        XCTAssertEqual(profile.hostKind, .privateAddress)
    }

    func testCredentialUpdateHandsSecretsToKeychainPathOnly() throws {
        let offer = try sampleOffer()
        let update = NaruPairingProfileFactory.makeCredentialUpdate(for: offer)
        XCTAssertEqual(update.vncPassword, "vnc-secret")
        XCTAssertEqual(update.helperPairingSecret, offer.helper.token)
        XCTAssertEqual(update.helperVideoPairingSecret, offer.helper.token)
    }
}
