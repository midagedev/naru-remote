import Foundation
import XCTest
@testable import NaruRemoteCore

/// Spec 042 FR-006 (Round D): per-profile screen-source pin
/// (`automatic` / `vncOnly`) on `HelperVideoConnectionConfiguration`.
///
/// ## Contract ↔ assertion table
///
/// | Contract | Assertion |
/// |----------|-----------|
/// | The preference exists with exactly the two FR-006 cases, defaulting
///   to `automatic` (pre-042 behaviour). |
///   `testCasesAndDefault` — `CaseIterable.allCases == [.automatic,
///   .vncOnly]`; a bare `init()` decodes as `.automatic`. |
/// | Decode: absent key (a pre-042 store) → `.automatic`. |
///   `testDecodeAbsentKeyDefaultsToAutomatic`. |
/// | Decode: `"vncOnly"` round-trips. |
///   `testDecodeVncOnlyRawValue`. |
/// | Decode: unknown raw string (a future client wrote a new case) →
///   `.automatic`, not a decode failure. |
///   `testDecodeUnknownRawValueFallsBackToAutomatic`. |
/// | Decode: a wrong-typed value is corruption, and throws like every
///   other field in this configuration (sibling fields use
///   `decodeIfPresent(Bool/String.self)`, which throws on type
///   mismatch). |
///   `testDecodeWrongTypeThrows`. |
/// | Encode always writes the key — a `.automatic` profile saved by this
///   build still carries the field for future readers. |
///   `testEncodeAlwaysWritesTransportPreference`. |
/// | Revoking keeps the stored preference (FR-006: revocation forgets
///   the secret, not the screen-source choice). |
///   `testRevokedConfigurationKeepsStoredPreference`. |
final class HelperVideoTransportPreferenceTests: XCTestCase {

    // MARK: - Cases and default

    func testCasesAndDefault() throws {
        XCTAssertEqual(HelperVideoTransportPreference.allCases, [.automatic, .vncOnly])
        XCTAssertEqual(
            HelperVideoConnectionConfiguration().transportPreference,
            .automatic
        )
    }

    // MARK: - Decode matrix

    func testDecodeAbsentKeyDefaultsToAutomatic() throws {
        let decoded = try Self.decodeConfiguration(
            #"""
            {"isEnabled": true}
            """#
        )
        XCTAssertEqual(decoded.transportPreference, .automatic)
    }

    func testDecodeVncOnlyRawValue() throws {
        let decoded = try Self.decodeConfiguration(
            #"""
            {"isEnabled": true, "transportPreference": "vncOnly"}
            """#
        )
        XCTAssertEqual(decoded.transportPreference, .vncOnly)
    }

    func testDecodeUnknownRawValueFallsBackToAutomatic() throws {
        // Forward compatibility: a future client writing a new case must
        // not make the profile unreadable here.
        let decoded = try Self.decodeConfiguration(
            #"""
            {"isEnabled": true, "transportPreference": "holographic"}
            """#
        )
        XCTAssertEqual(decoded.transportPreference, .automatic)
    }

    func testDecodeWrongTypeThrows() throws {
        XCTAssertThrowsError(
            try Self.decodeConfiguration(
                #"""
                {"isEnabled": true, "transportPreference": 42}
                """#
            )
        )
    }

    // MARK: - Encode

    func testEncodeAlwaysWritesTransportPreference() throws {
        for preference in HelperVideoTransportPreference.allCases {
            let encoded = try Self.encodeConfiguration(
                HelperVideoConnectionConfiguration(
                    isEnabled: true,
                    pairingSecretRef: "helper-video-token:desk",
                    pairingFingerprint: "sha256:helper-video",
                    transportPreference: preference
                )
            )
            XCTAssertTrue(
                encoded.contains(#""transportPreference":"\#(preference.rawValue)""#),
                "Encoded JSON must always carry the transportPreference key for \(preference): \(encoded)"
            )

            let roundTripped = try Self.decodeConfiguration(encoded)
            XCTAssertEqual(roundTripped.transportPreference, preference)
        }
    }

    // MARK: - Revocation keeps the choice

    func testRevokedConfigurationKeepsStoredPreference() throws {
        let revoked = HelperVideoConnectionConfiguration(
            isEnabled: true,
            isRevoked: true,
            pairingSecretRef: "helper-video-token:desk",
            pairingFingerprint: "sha256:helper-video",
            transportPreference: .vncOnly
        )
        // Revocation clears the pairing material but not the screen-source
        // choice — re-pairing restores the user's previous preference.
        XCTAssertFalse(revoked.isEnabled)
        XCTAssertTrue(revoked.isRevoked)
        XCTAssertNil(revoked.pairingSecretRef)
        XCTAssertNil(revoked.pairingFingerprint)
        XCTAssertEqual(revoked.transportPreference, .vncOnly)
    }

    // MARK: - Helpers

    private static func decodeConfiguration(_ json: String) throws -> HelperVideoConnectionConfiguration {
        try JSONDecoder().decode(
            HelperVideoConnectionConfiguration.self,
            from: Data(json.utf8)
        )
    }

    private static func encodeConfiguration(
        _ configuration: HelperVideoConnectionConfiguration
    ) throws -> String {
        let data = try JSONEncoder().encode(configuration)
        return String(decoding: data, as: UTF8.self)
    }
}
