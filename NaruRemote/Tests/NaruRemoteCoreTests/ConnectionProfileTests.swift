import XCTest
@testable import NaruRemoteCore

final class ConnectionProfileTests: XCTestCase {
    func testHelperTextBridgeConfigurationRoundTripsThroughProfileJSON() throws {
        let profileID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let profile = try ConnectionProfile(
            id: profileID,
            displayName: " Desk ",
            host: " desk.tailnet.ts.net ",
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                host: " helper.tailnet.ts.net ",
                port: 5975,
                pairingSecretRef: " helper-token:desk ",
                pairingFingerprint: " sha256:helper "
            )
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)

        XCTAssertEqual(decoded.id, profileID)
        XCTAssertEqual(decoded.displayName, "Desk")
        XCTAssertEqual(decoded.host, "desk.tailnet.ts.net")
        XCTAssertEqual(decoded.helperTextBridge?.isEnabled, true)
        XCTAssertEqual(decoded.helperTextBridge?.host, "helper.tailnet.ts.net")
        XCTAssertEqual(decoded.helperTextBridge?.port, 5975)
        XCTAssertEqual(decoded.helperTextBridge?.pairingSecretRef, "helper-token:desk")
        XCTAssertEqual(decoded.helperTextBridge?.pairingFingerprint, "sha256:helper")
    }

    func testHelperVideoConfigurationRoundTripsThroughProfileJSON() throws {
        let profileID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let profile = try ConnectionProfile(
            id: profileID,
            displayName: " Desk ",
            host: " desk.tailnet.ts.net ",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: " helper-video-token:desk ",
                pairingFingerprint: " sha256:helper-video "
            )
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)

        XCTAssertEqual(decoded.id, profileID)
        XCTAssertEqual(decoded.helperVideo?.isEnabled, true)
        XCTAssertEqual(decoded.helperVideo?.isRevoked, false)
        XCTAssertEqual(decoded.helperVideo?.pairingSecretRef, "helper-video-token:desk")
        XCTAssertEqual(decoded.helperVideo?.pairingFingerprint, "sha256:helper-video")
    }

    func testRevokedHelperVideoConfigurationClearsPairingMaterial() throws {
        let configuration = HelperVideoConnectionConfiguration(
            isEnabled: true,
            isRevoked: true,
            pairingSecretRef: "helper-video-token:desk",
            pairingFingerprint: "sha256:helper-video"
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(HelperVideoConnectionConfiguration.self, from: data)

        XCTAssertFalse(decoded.isEnabled)
        XCTAssertTrue(decoded.isRevoked)
        XCTAssertNil(decoded.pairingSecretRef)
        XCTAssertNil(decoded.pairingFingerprint)
    }

    func testLegacyHelperVideoConfigurationDecodesRevokedDefaultAsFalse() throws {
        let json = """
        {
          "isEnabled": true,
          "pairingSecretRef": "helper-video-token:desk",
          "pairingFingerprint": "sha256:helper-video"
        }
        """

        let decoded = try JSONDecoder().decode(
            HelperVideoConnectionConfiguration.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(decoded.isEnabled)
        XCTAssertFalse(decoded.isRevoked)
        XCTAssertEqual(decoded.pairingSecretRef, "helper-video-token:desk")
        XCTAssertEqual(decoded.pairingFingerprint, "sha256:helper-video")
    }

    func testProfileJSONWithoutHelperConfigurationDecodesAsNil() throws {
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "displayName": "Desk",
          "host": "desk.tailnet.ts.net",
          "port": 5900
        }
        """

        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: Data(json.utf8))

        XCTAssertNil(decoded.helperTextBridge)
        XCTAssertNil(decoded.helperVideo)
        XCTAssertEqual(decoded.hostKind, .magicDNS)
        XCTAssertTrue(decoded.allowsPiPWatch)
    }

    func testHelperConfigurationRejectsInvalidPort() throws {
        XCTAssertThrowsError(
            try HelperTextBridgeConnectionConfiguration(isEnabled: true, port: 70_000)
        ) { error in
            XCTAssertEqual(error as? ConnectionProfileValidationError, .invalidHelperPort(70_000))
        }
    }
}
